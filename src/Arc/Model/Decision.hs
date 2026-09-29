{- | Validation of a requested action.

'evaluate' reads a replayed history and the observations, and answers with
every ground on which the integration is refused, or with the basis it
would rest on when no ground stands. The grounds are a set listed in a
fixed presentation order; 'decide' is the first listed or the basis. 'execute' re-checks that the basis still
holds before producing a plan; 'recordIntegration' is the separate step
that puts the effect in the ledger. A permission alone never records
anything.
-}
module Arc.Model.Decision
    ( evaluate
    , refusals
    , decide
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
import Arc.Model.Observations ( IntegrationAuthority(..), Observations, TargetRelation(..) )
import Arc.Model.Observations qualified as Observations
import Arc.Model.Observed
import Arc.Model.Policy ( Policy )
import Arc.Model.Policy qualified as Policy
import Arc.Model.Probe ( probeRefusals )
import Arc.Model.State
import Arc.Model.State qualified as State

import Data.List.NonEmpty ( NonEmpty(..) )
import Data.List.NonEmpty qualified as NE
import Data.Maybe ( fromMaybe, listToMaybe )
import Data.Set qualified as Set


-- C12, C23
{- | Every ground on which the integration is refused, in presentation
order, or the basis it would rest on. The grounds are independent readings of the
same history: a moved head and an unevaluated gate are both reported, and
neither hides the other. Gate declarations two policy layers disagree on
are the one exception: there is no declaration set to evaluate against, so
that refusal stands alone.
-}
evaluate :: Observations -> ChangeState -> Either (NonEmpty Refusal) DecisionBasis
evaluate observations state
  | not (null observations.conflictingGates) = Left (RefusedConflictingDeclarations observations.conflictingGates :| [])
  | otherwise                                = evaluateDeclared observations state

-- C1, C2, C3, C5, C10, C11, C19
-- | 'evaluate' under one declaration set. It reads, so it never refuses the
-- invoker's identity; 'execute' does.
evaluateDeclared :: Observations -> ChangeState -> Either (NonEmpty Refusal) DecisionBasis
evaluateDeclared observations state = case latestPatchset state of
  Nothing       -> Left (NE.prependList preliminary (RefusedNoPatchset :| []))
  Just patchset ->
    let authorization = authorizationFor policy state patchset
        gates         = gateEvidence observations state
        probes        = probeRefusals state patchset
        grounds       = concat
          [ preliminary
          , case observations.head of
              Omitted       -> [RefusedBranchMissing]
              Observed seen -> [ RefusedHeadMoved seen patchset.revision | seen /= patchset.revision ]
          , [ RefusedNeedsRebase | observations.targetRelation == HeadConflictsWithTarget ]
          , [ RefusedMergedTreeUnevaluated observations.evaluatedTree | mergedTreeUnevaluated ]
          , [ RefusedBlockingFindings openFindings | not (null openFindings) ]
          , [ RefusedContestedVerdict (map (.event) (activeVerdicts state)) | verdictContested state ]
          , either pure (const []) authorization
          , either (pure . RefusedGates) (const []) gates
          , [ RefusedAcceptanceProbes probes | not (null probes) ]
          , [ RefusedHoldActive hold | Just hold <- [Set.lookupMin state.holds] ]
          ]
    in case (NE.nonEmpty grounds, authorization, gates) of
      (Just standing, _, _)         -> Left standing
      (Nothing, Right by, Right on) -> Right (basisOn patchset by on)
      (Nothing, Left refusal, _)    -> Left (refusal :| [])
      (Nothing, _, Left refused)    -> Left (RefusedGates refused :| [])
  where
    policy       = observations.policy
    openFindings = openBlockingFindings state
    preliminary  = concat
      [ [ RefusedClosed closure | Just closure <- [state.closed] ]
      , [ RefusedIterating | state.iterating ]
      , [ RefusedBlockedBy observations.blockedBy | not (null observations.blockedBy) ]
      ]
    -- a merge nobody ran any required gate on: evidence at the head says
    -- nothing about content neither branch committed
    required              = map fst observations.requiredGates
    mergedTreeUnevaluated
      =  observations.targetRelation == HeadBehindTarget
      && not (null required)
      && not (any (\v -> v.gate `elem` required && v.tree == observations.evaluatedTree) state.verifications)
    basisOn patchset authorization gates = DecisionBasis
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

-- C23
-- | The grounds alone, empty when the integration is permitted.
refusals :: Observations -> ChangeState -> [Refusal]
refusals observations state = either NE.toList (const []) (evaluate observations state)

-- C23
-- | Decide whether an integration is permitted now: the first standing
-- ground, or the basis.
decide :: Observations -> ChangeState -> Decision
decide observations state = either (Refused . NE.head) Permitted (evaluate observations state)

-- C4, C5, C6, C8, C9, C19
{- | The recorded approval or waiver that lets this patchset stand.

A refusal recorded on the current patchset, local or external, is the
answer: a waiver declares a missing review and does not clear one that was
given. Otherwise a local approval or waiver authorizes; an external approval
of exactly this head authorizes only where no independent review is owed,
because arc cannot verify who gave it.
-}
authorizationFor :: Policy -> ChangeState -> Patchset -> Either Refusal Authorization
authorizationFor policy state patchset
  | Just verdict <- governing, verdict.kind /= Approved, verdict.patchset == patchset.patchsetId
      = Left (RefusedVerdictStands verdict.kind verdict.event)
  | Just external <- externalHere, external.kind /= ExternalApproved
      = Left (RefusedExternalVerdictStands external.kind external.event)
  | otherwise = case local of
      Right authorization -> Right authorization
      Left refusal        -> maybe (Left refusal) Right externalAuthorization
  where
    governing    = governingVerdict state
    externalHere = externalVerdictAt state patchset.revision
    waiver       = newestWaiver state patchset.patchsetId
    local = case governing of
      Nothing -> maybe (Left RefusedNoApproval) (Right . AuthorizedByWaiver . (.debtId)) waiver
      Just verdict
        | verdict.kind == Approved && verdict.patchset == patchset.patchsetId ->
            if selfApprovalRejected verdict
              then case waiver of
                Just debt -> Right (AuthorizedByVerdictUnderWaiver verdict.event debt.debtId)
                Nothing   -> Left (RefusedSelfApproval verdict.event (effectiveActor verdict) (effectiveContributors patchset))
              else Right (AuthorizedByVerdict verdict.event)
        | otherwise -> case waiver of
            Just debt -> Right (AuthorizedByWaiver debt.debtId)
            Nothing   -> case verdict.kind of
              Approved -> Left (RefusedStaleApproval verdict.event verdict.patchset)
              _refused -> Left RefusedNoApproval
    externalAuthorization = case externalHere of
      Just external
        | external.kind == ExternalApproved, not independentRequired -> Just (AuthorizedByExternalVerdict external.event)
      _absent -> Nothing
    independentRequired = policy.independentVerdictRequired && policy.forbidSelfApproval
    selfApprovalRejected verdict
      = independentRequired
      && (verdict.assumed || effectiveActor verdict `Set.member` effectiveContributors patchset)

-- C6, C7
{- | The newest debt whose waiver binds to exactly this patchset. Later
declarations for the same patchset win; a declaration for any other
patchset waives nothing here.
-}
newestWaiver :: ChangeState -> PatchsetId -> Maybe Debt
newestWaiver state patchset = newest (debtsForPatchset state patchset)

-- C3, C12, C13, C15, C16, C19
{- | Read every required gate against the evaluated tree and the environment
its probe yields here. A gate that is required but not declared is refused
like any other missing evidence.
-}
gateEvidence :: Observations -> ChangeState -> Either [GateRefusal] [(GateName, EventId, DeclarationId)]
gateEvidence observations state =
  case [ refusal | (_, _, Left refusal) <- results ] of
    []      -> Right [ evidence | Just evidence <- map toEvidence results ]
    refused -> Left refused
  where
    results =
      [ (gate, declaration, gateGreen gate declaration observations.evaluatedTree (environmentFor declaration) waived state.verifications)
      | (gate, wanted) <- observations.requiredGates
      , let declaration = lookupDeclaration wanted
      ]
    waived = (.revision) <$> dirtyTreeWaiver state
    lookupDeclaration wanted = listToMaybe [ d | d <- observations.declarations, d.declarationId == wanted ]
    environmentFor declaration = fromMaybe Omitted $ do
      probe <- declaration >>= (.environment)
      lookup probe observations.environments
    toEvidence = \case
      (gate, Just declaration, Right reading) -> case reading.coverage of
        Covered event -> Just (gate, event, declaration.declarationId)
        _uncovered    -> Nothing
      _refused -> Nothing

-- C2, C12, C18, C20
{- | Re-check a basis against the observations at execution time. A store
that does not hold integration authority cannot act at all, an invoker
nobody declared is refused where policy requires a declared actor,
declarations two policy layers disagree on and a missing branch leave
nothing to act on, and any moved fact stands the action down; the recorded
basis is never reused.
-}
execute :: Observations -> ChangeState -> Decision -> Either Refusal ExecutionPlan
execute observations state = \case
  Refused refusal -> Left refusal
  Permitted basis
    | observations.authority == AuthorityWithheld -> Left RefusedAuthorityWithheld
    | observations.policy.requireDeclaredActor && not observations.invokerDeclared
                                                  -> Left RefusedUndeclaredActor
    | not (null observations.conflictingGates)    -> Left (RefusedConflictingDeclarations observations.conflictingGates)
    | observations.head == Omitted                -> Left RefusedBranchMissing
    | otherwise -> case moved basis of
        []    -> Right ExecutionPlan { integration = integration basis }
        facts -> Left (RefusedBasisMoved facts)
  where
    moved basis = concat
      [ [ MovedHead basis.head seen                         | Observed seen <- [observations.head], basis.head /= seen ]
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

-- C20
-- | Record the effect. An integration event carries the plan's basis, so a
-- later review can never rewrite what the merge relied upon.
recordIntegration :: EventId -> ExecutionPlan -> ChangeState -> ChangeState
recordIntegration event plan state = state { State.integrations = state.integrations <> [record] }
  where
    record = plan.integration { Integration.event = event }
