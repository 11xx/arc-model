{- | Gate budget suspensions, seed eligibility, and enforcement-key rules.

Budget timing, perf counters, and system clocks stay outside this pure
module: callers supply observed instants, declaration health, and raw timing
classifications, and this module answers the pure authorization rules of C31,
C32, and C33.
-}
module Arc.Model.Budget
    ( Instant(..)
    , DurationMs(..)
    , maxSuspensionDurationMs
    , SuspensionId(..)
    , SuspensionOrigin(..)
    , BudgetSuspension(..)
    , SuspensionRefusal(..)
    , admitSuspension
    , resumeSuspensions
    , suspensionCovers
    , BudgetDeclarationHealth(..)
    , BudgetRunTiming(..)
    , BudgetRefusal(..)
    , BudgetJudgment(..)
    , judgeGateBudget
    , eligibleAsWorkReference
    , eligibleAsRaiseEvidence
    , eligibleAsBasePassSeed
    , BudgetTable(..)
    , budgetTableEnforces
    ) where

import Arc.Model.Declaration ( GateEvent(..), GateResult(..) )
import Arc.Model.Identifiers ( ActorId, GateName )
import Arc.Model.Observed ( newest )

import Data.Char ( isSpace )
import Data.Maybe ( isNothing )
import Data.Set ( Set )
import Data.Set qualified as Set


-- | An abstract instant in whole milliseconds; no system clock is read.
newtype Instant = Instant Int
  deriving stock (Eq, Ord, Show)

-- | A duration in whole milliseconds.
newtype DurationMs = DurationMs Int
  deriving stock (Eq, Ord, Show)

-- C31
-- | A budget suspension ends at most 24 hours after it starts.
maxSuspensionDurationMs :: DurationMs
maxSuspensionDurationMs = DurationMs (24 * 60 * 60 * 1000)

newtype SuspensionId = SuspensionId Int
  deriving stock (Eq, Ord, Show)

-- | Whether a suspension belongs to the judging ledger or arrived from
-- another store. A store honours only its own suspensions.
data SuspensionOrigin = LocalLedger
                      | ImportedLedger
  deriving stock (Eq, Ord, Show)

-- | A recorded budget suspension on a ledger.
data BudgetSuspension = BudgetSuspension
  { suspensionId :: !SuspensionId
  , origin       :: !SuspensionOrigin
  , actor        :: !ActorId
  , reason       :: !String
  , startedAt    :: !Instant
  , endsAt       :: !Instant
  , gates        :: !(Set GateName)    -- ^ Empty covers every gate.
  , resumedAt    :: !(Maybe Instant)   -- ^ Set when @arc gates resume@ ended it early.
  }
  deriving stock (Eq, Ord, Show)

-- | Why a budget suspension declaration is refused.
data SuspensionRefusal = SuspensionNotLocal
                       | SuspensionEmptyReason
                       | SuspensionNonPositiveWindow
                       | SuspensionExceedsMaxDuration
  deriving stock (Eq, Ord, Show)

-- C31
-- | Validate a budget suspension before recording: local ledger, nonempty
-- reason, positive window, and at most 24 hours long.
admitSuspension :: BudgetSuspension -> Either SuspensionRefusal BudgetSuspension
admitSuspension suspension
  | suspension.origin /= LocalLedger               = Left SuspensionNotLocal
  | all isSpace suspension.reason                  = Left SuspensionEmptyReason
  | endMs <= startMs                               = Left SuspensionNonPositiveWindow
  | endMs - startMs > maxMs                        = Left SuspensionExceedsMaxDuration
  | otherwise                                      = Right suspension
  where
    Instant startMs    = suspension.startedAt
    Instant endMs      = suspension.endsAt
    DurationMs maxMs   = maxSuspensionDurationMs

-- C31
-- | End every local budget suspension in force at the given instant.
resumeSuspensions :: Instant -> [BudgetSuspension] -> [BudgetSuspension]
resumeSuspensions now = map resumeOne
  where
    resumeOne suspension
      | suspension.origin == LocalLedger
      , suspension.startedAt <= now
      , now < suspension.endsAt
      , isNothing suspension.resumedAt
        = suspension { resumedAt = Just now }
      | otherwise = suspension

-- C31
-- | Whether a suspension is in force on the judging ledger at @now@ and
-- covers @gate@.
suspensionCovers :: Instant -> GateName -> BudgetSuspension -> Bool
suspensionCovers now gate suspension
  =  suspension.origin == LocalLedger
  && suspension.startedAt <= now
  && now < suspension.endsAt
  && maybe True (now <) suspension.resumedAt
  && (Set.null suspension.gates || Set.member gate suspension.gates)

-- | Declaration-level budget health. None of these errors can be lifted by
-- a budget suspension.
data BudgetDeclarationHealth = BudgetDeclarationValid
                             | BudgetMissingRequiredGate GateName
                             | BudgetExcessiveTotal
                             | BudgetOverOperatorCeiling
  deriving stock (Eq, Ord, Show)

-- | How a run's command time relates to the budget in force, apart from any
-- suspension.
data BudgetRunTiming = RunWithinBudget
                     | RunOverBudget
                     | RunUnmeasured
                     | RunBusyHostExcused
  deriving stock (Eq, Ord, Show)

-- | Why the budget judge refuses a gate run.
data BudgetRefusal = BudgetRefusedDeclaration BudgetDeclarationHealth
                   | BudgetRefusedGateOutcome GateResult
                   | BudgetRefusedUnmeasured
                   | BudgetRefusedOverBudget
  deriving stock (Eq, Ord, Show)

-- | The budget judge's answer for one gate run at the moment of judgment.
data BudgetJudgment = BudgetAccepted
                    | BudgetExcused
                    | BudgetSuspended SuspensionId
                    | BudgetRefused BudgetRefusal
  deriving stock (Eq, Ord, Show)

-- C31
{- | Judge one gate run against its declaration health, raw outcome, timing,
and the judging ledger's suspensions at @now@.

While a local suspension covers a gate, an over-budget passing run is accepted
for integration as of the moment of judgment: an earlier receipt counts while
active and is refused again once the suspension ends. Failing or not-admitted
gates, unmeasured runs, declaration-level budget errors, and publication are
never lifted by a suspension.
-}
judgeGateBudget
  :: GateEvent
  -> GateName
  -> GateResult
  -> BudgetDeclarationHealth
  -> BudgetRunTiming
  -> Instant
  -> [BudgetSuspension]
  -> BudgetJudgment
judgeGateBudget operation gate result declarationHealth timing now suspensions
  | declarationHealth /= BudgetDeclarationValid = BudgetRefused (BudgetRefusedDeclaration declarationHealth)
  | result /= GatePass                          = BudgetRefused (BudgetRefusedGateOutcome result)
  | otherwise = case timing of
      RunWithinBudget    -> BudgetAccepted
      RunBusyHostExcused -> BudgetExcused
      RunUnmeasured      -> BudgetRefused BudgetRefusedUnmeasured
      RunOverBudget -> case operation of
        Publication -> BudgetRefused BudgetRefusedOverBudget
        Integration -> case newest (filter (suspensionCovers now gate) suspensions) of
          Just active -> BudgetSuspended active.suspensionId
          Nothing     -> BudgetRefused BudgetRefusedOverBudget

-- C31
-- | Whether a clean direct pass may serve as a busy-host work reference:
-- within budget, unexcused, and recorded under no budget suspension.
eligibleAsWorkReference :: GateResult -> BudgetRunTiming -> Bool -> Bool
eligibleAsWorkReference result timing recordedUnderSuspension
  = result == GatePass && timing == RunWithinBudget && not recordedUnderSuspension

-- C32
-- | Whether a clean direct pass may establish need for a budget raise:
-- over the destination budget, unexcused, and recorded under no suspension.
eligibleAsRaiseEvidence :: GateResult -> BudgetRunTiming -> Bool -> Bool
eligibleAsRaiseEvidence result timing recordedUnderSuspension
  = result == GatePass && timing == RunOverBudget && not recordedUnderSuspension

-- C33
-- | Whether a clean direct pass may seed a cross-change base pass:
-- within budget, unexcused, and recorded under no budget suspension.
eligibleAsBasePassSeed :: GateResult -> BudgetRunTiming -> Bool -> Bool
eligibleAsBasePassSeed result timing recordedUnderSuspension
  = result == GatePass && timing == RunWithinBudget && not recordedUnderSuspension

-- | Keys present in one @[budget]@ table declaration.
data BudgetTable = BudgetTable
  { hasLanding            :: !Bool
  , hasTotal              :: !Bool
  , hasNonDefaultRaise    :: !Bool
  , hasNonDefaultRaisePer :: !Bool
  , hasNonEmptyExclude    :: !Bool
  }
  deriving stock (Eq, Ord, Show)

-- C31
{- | Whether a @[budget]@ table enforces individual budgets on every required
integration gate. A table enforces when it has no @landing@ key (the empty
table included), or when beside @landing@ it sets @total@, @raise@,
@raise_per@, or @exclude@ to other than its default.
-}
budgetTableEnforces :: BudgetTable -> Bool
budgetTableEnforces table
  =  not table.hasLanding
  || table.hasTotal
  || table.hasNonDefaultRaise
  || table.hasNonDefaultRaisePer
  || table.hasNonEmptyExclude
