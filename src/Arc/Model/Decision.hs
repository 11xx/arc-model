{- | Validation of a requested action.

'decide' reads a replayed history and the observations, and answers with
either a basis naming the facts it relied on or a structured refusal.
'execute' re-checks that the basis still holds before producing a plan;
'recordIntegration' is the separate step that puts the effect in the
ledger. A permission alone never records anything.
-}
module Arc.Model.Decision
    ( decide
    , authorizationFor
    , gateEvidence
    , newestWaiver
    , execute
    , ExecutionPlan(..)
    , recordIntegration
    ) where

import Arc.Model.Basis
import Arc.Model.Declaration qualified as Declaration
import Arc.Model.Gate
import Arc.Model.Identifiers
import Arc.Model.Ledger
import Arc.Model.Ledger.Integration qualified as Integration
import Arc.Model.Observations ( Observations )
import Arc.Model.Observations qualified as Observations
import Arc.Model.Observed ( newest )
import Arc.Model.Policy ( Policy )
import Arc.Model.Policy qualified as Policy
import Arc.Model.State
import Arc.Model.State qualified as State

import Data.Maybe ( listToMaybe )
import Data.Set qualified as Set


-- | Decide whether an integration is permitted now.
decide :: Observations -> ChangeState -> Decision
decide observations state
  | Just closure <- state.closed          = Refused (RefusedClosed closure)
  | state.iterating                       = Refused RefusedIterating
  | not (null observations.blockedBy)     = Refused (RefusedBlockedBy observations.blockedBy)
  | otherwise = case latestPatchset state of
      Nothing -> Refused RefusedNoPatchset
      Just patchset
        | observations.head /= patchset.revision
          -> Refused (RefusedHeadMoved observations.head patchset.revision)
        | not (null openFindings)
          -> Refused (RefusedBlockingFindings openFindings)
        | verdictContested state
          -> Refused (RefusedContestedVerdict (map (.event) (activeVerdicts state)))
        | policy.requireDeclaredActor && not observations.invokerDeclared
          -> Refused RefusedUndeclaredActor
        | otherwise -> case authorizationFor policy state patchset of
            Left refusal        -> Refused refusal
            Right authorization -> case gateEvidence observations state of
              Left refusals -> Refused (RefusedGates refusals)
              Right gates   -> case Set.lookupMin state.holds of
                Just hold -> Refused (RefusedHoldActive hold)
                Nothing   -> Permitted DecisionBasis
                  { patchset         = patchset.patchsetId
                  , head             = patchset.revision
                  , tree             = observations.evaluatedTree
                  , targetBranch     = observations.targetBranch
                  , target           = observations.target
                  , policy           = policy
                  , authorization    = authorization
                  , gates            = gates
                  , consumedFindings = openFindings
                  , consumedHolds    = []
                  }
  where
    openFindings = openBlockingFindings state
    policy       = observations.policy

-- | The recorded approval or waiver that lets this patchset stand.
authorizationFor :: Policy -> ChangeState -> Patchset -> Either Refusal Authorization
authorizationFor policy state patchset =
  case governingVerdict state of
    Nothing -> case waiver of
      Just debt -> Right (AuthorizedByWaiver debt.debtId)
      Nothing   -> Left RefusedNoApproval
    Just verdict
      | verdict.kind == Approved && verdict.patchset == patchset.patchsetId ->
          if selfApprovalRejected verdict
            then case waiver of
              Just debt -> Right (AuthorizedByVerdictUnderWaiver verdict.event debt.debtId)
              Nothing   -> Left (RefusedSelfApproval verdict.event (effectiveActor verdict) (effectiveContributors patchset))
            else Right (AuthorizedByVerdict verdict.event)
      | verdict.kind /= Approved && verdict.patchset == patchset.patchsetId ->
          -- a refusal on the current patchset is the action itself: a waiver
          -- declares a missing review, it does not clear an answer
          Left (RefusedVerdictStands verdict.kind verdict.event)
      | otherwise -> case waiver of
          Just debt -> Right (AuthorizedByWaiver debt.debtId)
          Nothing   -> case verdict.kind of
            Approved -> Left (RefusedStaleApproval verdict.event verdict.patchset)
            _refused -> Left RefusedNoApproval
  where
    waiver = newestWaiver state patchset.patchsetId
    selfApprovalRejected verdict
      = policy.independentVerdictRequired
      && policy.forbidSelfApproval
      && (verdict.assumed || effectiveActor verdict `Set.member` effectiveContributors patchset)

{- | The newest debt whose waiver binds to exactly this patchset. Later
declarations for the same patchset win; a declaration for any other
patchset waives nothing here.
-}
newestWaiver :: ChangeState -> PatchsetId -> Maybe Debt
newestWaiver state patchset = newest (debtsForPatchset state patchset)

-- | Read every required gate against the evaluated tree. A gate that is
-- required but not declared is refused like any other missing evidence.
gateEvidence :: Observations -> ChangeState -> Either [GateRefusal] [(GateName, EventId, DeclarationId)]
gateEvidence observations state =
  case [ refusal | (_, _, Left refusal) <- results ] of
    []       -> Right [ evidence | Just evidence <- map toEvidence results ]
    refusals -> Left refusals
  where
    results =
      [ (gate, declaration, gateGreen gate declaration observations.evaluatedTree state.verifications)
      | (gate, wanted) <- observations.requiredGates
      , let declaration = lookupDeclaration wanted
      ]
    lookupDeclaration wanted = listToMaybe [ d | d <- observations.declarations, d.declarationId == wanted ]
    toEvidence = \case
      (gate, Just declaration, Right reading) -> case reading.coverage of
        Covered event -> Just (gate, event, declaration.declarationId)
        _uncovered    -> Nothing
      _refused -> Nothing

-- | Re-check a basis against the observations at execution time. Any moved
-- fact stands the action down; the recorded basis is never reused.
execute :: Observations -> ChangeState -> Decision -> Either Refusal ExecutionPlan
execute observations state = \case
  Refused refusal -> Left refusal
  Permitted basis -> case moved basis of
    []    -> Right ExecutionPlan { integration = integration basis }
    facts -> Left (RefusedBasisMoved facts)
  where
    moved basis = concat
      [ [ MovedHead basis.head observations.head            | basis.head   /= observations.head ]
      , [ MovedTarget basis.target observations.target      | basis.target /= observations.target ]
      , [ MovedTree basis.tree observations.evaluatedTree   | basis.tree   /= observations.evaluatedTree ]
      , [ MovedPolicy basis.policy observations.policy      | basis.policy /= observations.policy ]
      , [ MovedPatchset basis.patchset patchset.patchsetId
        | Just patchset <- [latestPatchset state]
        , patchset.patchsetId /= basis.patchset
        ]
      ]
    integration basis = IntegrationRecord
      { event            = EventId 0
      , patchset         = basis.patchset
      , head             = basis.head
      , targetBranch     = basis.targetBranch
      , targetBefore     = basis.target
      , tree             = basis.tree
      , authorization    = basis.authorization
      , gates            = basis.gates
      , consumedFindings = basis.consumedFindings
      , consumedHolds    = basis.consumedHolds
      , policy           = basis.policy
      }

-- | The plan an execution produced. Holding one proves nothing about the
-- world; only 'recordIntegration' puts it in the ledger.
newtype ExecutionPlan = ExecutionPlan { integration :: IntegrationRecord }
  deriving stock (Eq, Ord, Show)

-- | Record the effect. An integration event carries the plan's basis, so a
-- later review can never rewrite what the merge relied upon.
recordIntegration :: EventId -> ExecutionPlan -> ChangeState -> ChangeState
recordIntegration event plan state = state { State.integrations = state.integrations <> [record] }
  where
    record = plan.integration { Integration.event = event }
