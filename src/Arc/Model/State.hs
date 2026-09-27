{- | The replayed ledger.

'replay' folds append-only events into a state. It decides nothing and
refuses nothing; it only answers what happened. Validation is a separate
function over the replayed state and the observations, so a reader can
always ask what the ledger says without asking what it permits.
-}
module Arc.Model.State
    ( ChangeState(..)
    , emptyState
    , replay
    , latestPatchset
    , patchsetById
    , activeVerdicts
    , verdictContested
    , governingVerdict
    , findingResolved
    , openBlockingFindings
    , openAuditFindings
    , debtsForPatchset
    , latestIntegration
    , historicalAuthorization
    , activeIntegration
    ) where

import Arc.Model.Identifiers
import Arc.Model.Ledger ( Closure, Event(..) )
import Arc.Model.Ledger.Audit ( Audit )
import Arc.Model.Ledger.Claim ( Claim )
import Arc.Model.Ledger.Claim qualified as Claim
import Arc.Model.Ledger.Debt ( Debt )
import Arc.Model.Ledger.Debt qualified as Debt
import Arc.Model.Ledger.Disposition ( Disposition )
import Arc.Model.Ledger.Disposition qualified as Disposition
import Arc.Model.Ledger.Finding ( Finding )
import Arc.Model.Ledger.Finding qualified as Finding
import Arc.Model.Ledger.Integration ( Authorization, IntegrationRecord )
import Arc.Model.Ledger.Integration qualified as Integration
import Arc.Model.Ledger.Patchset ( Patchset )
import Arc.Model.Ledger.Patchset qualified as Patchset
import Arc.Model.Ledger.Verdict ( Verdict, VerdictRelation(..) )
import Arc.Model.Ledger.Verdict qualified as Verdict
import Arc.Model.Ledger.Verification ( Verification )
import Arc.Model.Observed ( newest )

import Data.List ( sortOn )
import Data.Maybe ( listToMaybe )
import Data.Set ( Set )
import Data.Set qualified as Set


data ChangeState = ChangeState
  { change        :: !ChangeId
  , patchsets     :: ![Patchset]
  , verdicts      :: ![Verdict]
  , findings      :: ![Finding]
  , dispositions  :: ![Disposition]
  , verifications :: ![Verification]
  , debts         :: ![Debt]
  , audits        :: ![Audit]
  , claims        :: ![Claim]
  , holds         :: !(Set HoldId)
  , integrations  :: ![IntegrationRecord]
  , closed        :: !(Maybe Closure)
  , iterating     :: !Bool
  }
  deriving stock (Eq, Ord, Show)

emptyState :: ChangeId -> ChangeState
emptyState change = ChangeState
  { change        = change
  , patchsets     = []
  , verdicts      = []
  , findings      = []
  , dispositions  = []
  , verifications = []
  , debts         = []
  , audits        = []
  , claims        = []
  , holds         = Set.empty
  , integrations  = []
  , closed        = Nothing
  , iterating     = False
  }

-- | Fold events into state. Nothing here reads the clock, the filesystem, or
-- the Git repository.
replay :: ChangeId -> [Event] -> ChangeState
replay change = foldl' step (emptyState change)
  where
    step state = \case
      PatchsetRecorded value     -> state { patchsets     = state.patchsets     <> [value] }
      VerdictRecorded value      -> state { verdicts      = state.verdicts      <> [value] }
      FindingRecorded value      -> state { findings      = state.findings      <> [value] }
      FindingDisposed value      -> state { dispositions  = state.dispositions  <> [value] }
      VerificationRecorded value -> state { verifications = state.verifications <> [value] }
      DebtDeclared value         -> state { debts         = state.debts         <> [value] }
      AuditRecorded value        -> state { audits        = state.audits        <> [value] }
      ClaimStarted value         -> state { claims        = state.claims        <> [value] }
      IntegrationRecorded value  -> state { integrations  = state.integrations  <> [value] }
      ClaimExpired claim         -> state { claims        = map (expire claim) state.claims }
      HoldSet hold               -> state { holds         = Set.insert hold state.holds }
      HoldReleased hold          -> state { holds         = Set.delete hold state.holds }
      ChangeClosed closure       -> state { closed        = Just closure }
      IteratingChanged value     -> state { iterating     = value }
    expire claim value
      | value.claimId == claim = value { Claim.expired = True }
      | otherwise              = value

latestPatchset :: ChangeState -> Maybe Patchset
latestPatchset state = newest state.patchsets

patchsetById :: ChangeState -> PatchsetId -> Maybe Patchset
patchsetById state identifier = listToMaybe [ p | p <- state.patchsets, p.patchsetId == identifier ]

-- | Verdicts nothing supersedes. A corroborating verdict supports a tip
-- without replacing it.
activeVerdicts :: ChangeState -> [Verdict]
activeVerdicts state = [ v | v <- state.verdicts, not (any (supersedesSubject v) state.verdicts) ]
  where
    supersedesSubject subject other = other.relation == Supersedes && other.supersedes == Just subject.event

{- | Two verdicts replacing the same earlier verdict fork the chain. No
verdict is authoritative until one supersedes them all, so the state is
contested rather than unreviewed.
-}
verdictContested :: ChangeState -> Bool
verdictContested state = length (activeVerdicts state) > 1

governingVerdict :: ChangeState -> Maybe Verdict
governingVerdict state = case activeVerdicts state of
  [v]    -> Just v
  _other -> Nothing

findingResolved :: ChangeState -> FindingId -> Bool
findingResolved state identifier = any (\d -> d.finding == identifier && d.resolved) state.dispositions

-- | Open blocking findings from the shipped review, never the audit set.
openBlockingFindings :: ChangeState -> [FindingId]
openBlockingFindings state =
  [ f.findingId
  | f <- state.findings
  , f.blocking
  , not f.audit
  , not (findingResolved state f.findingId)
  ]

openAuditFindings :: ChangeState -> [FindingId]
openAuditFindings state =
  [ f.findingId
  | f <- state.findings
  , f.audit
  , not (findingResolved state f.findingId)
  ]

debtsForPatchset :: ChangeState -> PatchsetId -> [Debt]
debtsForPatchset state identifier = [ debt | debt <- state.debts, debt.patchset == Just identifier ]

-- | The newest recorded integration, in recording order.
latestIntegration :: ChangeState -> Maybe IntegrationRecord
latestIntegration state = newest (sortOn (.event) state.integrations)

-- | What shipped and what it rested on. A later review or audit never
-- changes this answer.
historicalAuthorization :: ChangeState -> Maybe Authorization
historicalAuthorization state = (.authorization) <$> latestIntegration state

activeIntegration :: ChangeState -> Maybe IntegrationRecord
activeIntegration = latestIntegration
