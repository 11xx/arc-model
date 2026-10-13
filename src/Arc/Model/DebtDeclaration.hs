{- | Declaring a debt, and planning the integration that declares one.

'declareDebt' is the declaration alone: what it records, what it refuses, and
when it records nothing because an equivalent debt is in force. A plan reads
the change as it would be once the debt is declared and writes nothing; its
execution declares for real and then decides as C20 does.
-}
module Arc.Model.DebtDeclaration
    ( DebtRequest(..)
    , Why(..)
    , DebtOutcome(..)
    , declareDebt
    , DebtPlan(..)
    , PlanDisposition(..)
    , plannedDebtId
    , planDeclaring
    , executeDeclaring
    ) where

import Arc.Model.Basis
import Arc.Model.Decision ( decide, execute, ExecutionPlan )
import Arc.Model.Identifiers
import Arc.Model.Ledger
import Arc.Model.Ledger.Debt qualified as Debt
import Arc.Model.Observations ( Observations )
import Arc.Model.Observed ( newest )
import Arc.Model.State
import Arc.Model.State qualified as State

import Data.Set ( Set )
import Data.Set qualified as Set


-- | What the caller of @arc debt@ or @arc integrate --debt@ supplies.
data DebtRequest = DebtRequest
  { patchset :: !(Maybe PatchsetId)  -- ^ The patchset the debt covers; absent after integration.
  , kind     :: !(Maybe DebtKind)
  , reason   :: !String
  , actor    :: !ActorId
  , read     :: !(Maybe EventId)     -- ^ The @--read@ event.
  , why      :: !(Maybe Why)         -- ^ The assessment file's contents or the @--qualifier@ flags.
  }
  deriving stock (Eq, Ord, Show)

-- | Why routing does not count a read, as the declaration supplied it.
data Why = Why
  { independence :: !Independence
  , qualifiers   :: !(Set Qualifier)
  , source       :: !AssessmentSource
  , routeVersion :: !(Maybe RouteVersion)
  }
  deriving stock (Eq, Ord, Show)

-- | A declaration writes a debt, or finds the same one in force.
data DebtOutcome = DebtWritten Debt
                 | DebtReused Debt
  deriving stock (Eq, Ord, Show)

-- C21
{- | Declare a debt. A kind other than @ineligible-review@ takes no read and
no assessment. That kind needs a read, the named verdict or the patchset's
latest, and records why routing does not count it; an eligible assessment
leaves nothing to record. A declaration that repeats an equivalent one in
force, the same record in everything but its identity, records nothing.
-}
declareDebt :: ChangeState -> DebtRequest -> Either DebtRefusal DebtOutcome
declareDebt state request = do
  ineligibleRead <- case request.kind of
    Just IneligibleReview -> Just <$> ineligibleFor
    _otherKind
      | request.read /= Nothing -> Left ReadOnOtherKind
      | otherwise               -> Right Nothing
  let candidate = Debt
        { debtId              = nextDebt
        , event               = nextEvent state
        , patchset            = request.patchset
        , declaredKind        = request.kind
        , reason              = request.reason
        , actor               = request.actor
        , ineligible          = ineligibleRead
        , trailerImplementers = request.patchset >>= patchsetById state >>= (.implementers)
        }
  pure $ case [ held | held <- state.debts, same held candidate ] of
    held : _ -> DebtReused held
    []       -> DebtWritten candidate
  where
    nextDebt = DebtId (1 + maximum (0 : [ n | Debt { debtId = DebtId n } <- state.debts ]))
    same held candidate = held { debtId = candidate.debtId, event = candidate.event } == candidate
    verdictsHere = [ v | v <- state.verdicts, Just v.patchset == request.patchset ]
    ineligibleFor = do
      named <- case request.read of
        Just event
          | any ((== event) . (.event)) verdictsHere -> Right event
          | otherwise                                -> Left (ReadNotAVerdict event)
        Nothing -> maybe (Left NoVerdictToRead) (Right . (.event)) (newest verdictsHere)
      assessed <- maybe (Left NoReasonForIneligible) Right request.why
      if assessed.independence == Eligible
        then Left EligibleAssessment
        else if Set.null assessed.qualifiers
          then Left NoReasonForIneligible
          else Right IneligibleRead
            { read         = named
            , qualifiers   = assessed.qualifiers
            , source       = assessed.source
            , routeVersion = assessed.routeVersion
            }

-- | The event the next record would carry: later than every event the state
-- holds.
nextEvent :: ChangeState -> EventId
nextEvent state = succ (maximum (EventId 0 : concat
  [ [ v.event | v <- state.verdicts ]
  , [ d.event | d <- state.debts ]
  , [ a.event | a <- state.audits ]
  , [ i.event | i <- state.integrations ]
  , [ x.event | x <- state.externalVerdicts ]
  , [ f.event | f <- state.findings ]
  , [ v.event | v <- state.verifications ]
  ]))

-- | Whether the plan would write the declaration, or the change carries it.
data PlanDisposition = WouldDeclare
                       | AlreadyDeclared DebtId
  deriving stock (Eq, Ord, Show)

-- | What @integrate --dry-run --debt@ says: the debt it reads the change
-- with, whether it would write it, and the decision made as if it were
-- declared.
data DebtPlan = DebtPlan
  { disposition :: !PlanDisposition
  , debt        :: !Debt
  , decision    :: !Decision
  }
  deriving stock (Eq, Show)

-- | The identity a plan gives the debt it would declare: no recorded debt
-- carries it, so the plan never names an event the execution has not written.
plannedDebtId :: DebtId
plannedDebtId = DebtId 0

-- C28
{- | Plan the integration as it reads once the debt is declared. A
declaration the execution would refuse is refused here, and the plan
invents no approval: every ground still stands.
-}
planDeclaring :: Observations -> ChangeState -> DebtRequest -> Either DebtRefusal DebtPlan
planDeclaring observations state request = do
  outcome <- declareDebt state request
  pure $ case outcome of
    DebtReused held   -> DebtPlan (AlreadyDeclared held.debtId) held (decide observations state)
    DebtWritten debt  ->
      let planned = debt { Debt.debtId = plannedDebtId }
      in DebtPlan WouldDeclare planned (decide observations (state { State.debts = state.debts <> [planned] }))

-- C20, C28
{- | Integrate with the debt declared. The declaration is made again against
the history as it stands now, so a debt another actor declared since the
plan, or an equivalent one the declaration now reuses, moves what the plan
named; the event the execution itself writes does not.
-}
executeDeclaring :: Observations -> ChangeState -> DebtRequest -> Decision -> Either Refusal ExecutionPlan
executeDeclaring observations state request planned = case declareDebt state request of
  Left refusal -> Left (RefusedDebt refusal)
  Right outcome -> case outcome of
    DebtReused _     -> execute observations state planned
    DebtWritten debt -> execute observations (state { State.debts = state.debts <> [debt] }) (adopt debt.debtId planned)
  where
    -- the event the execution writes is the one the plan named: no move
    adopt written = \case
      Permitted basis -> Permitted basis
        { authorization = case basis.authorization of
            AuthorizedByWaiver debt | debt == plannedDebtId                       -> AuthorizedByWaiver written
            AuthorizedByVerdictUnderWaiver verdict debt | debt == plannedDebtId -> AuthorizedByVerdictUnderWaiver verdict written
            other                                                                   -> other
        , debts         = [ if debt == plannedDebtId then written else debt | debt <- basis.debts ]
        }
      refused -> refused

