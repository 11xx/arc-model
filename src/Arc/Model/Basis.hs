{- | What a decision rests on, and why it refused.

A permission is not a boolean. It is a basis naming the exact facts the
model relied upon, so a reader can check every one of them against the
ledger. A refusal is a structured reason, not a sentence.
-}
module Arc.Model.Basis
    ( Decision(..)
    , DecisionBasis(..)
    , Refusal(..)
    , MovedFact(..)
    , refusalTag
    , refusalText
    , basisText
    , isPermitted
    ) where

import Arc.Model.Gate ( GateRefusal, gateRefusalText )
import Arc.Model.Identifiers
import Arc.Model.Ledger ( Authorization, Closure, ExternalKind, VerdictKind )
import Arc.Model.Policy ( Policy )
import Arc.Model.Probe ( ProbeRefusal, probeRefusalText )

import Data.Set ( Set )


-- | What an integration would rest on if it ran now.
data DecisionBasis = DecisionBasis
  { patchset         :: !PatchsetId
  , head             :: !Revision
  , tree             :: !TreeId
  , targetBranch     :: !TargetBranch
  , target           :: !Revision
  , policy           :: !Policy
  , authorization    :: !Authorization
  , gates            :: ![(GateName, EventId, DeclarationId)]  -- ^ One covered, passing evaluation per required gate.
  , prerequisites    :: ![(ChangeId, EventId)]                 -- ^ Each prerequisite and the closure that integrated it.
  , consumedFindings :: ![FindingId]                           -- ^ The blocking-finding vector that had to be empty.
  , consumedHolds    :: ![HoldId]                              -- ^ The hold vector that had to be empty.
  }
  deriving stock (Eq, Ord, Show)

data Decision = Permitted DecisionBasis
              | Refused Refusal
  deriving stock (Eq, Ord, Show)

isPermitted :: Decision -> Bool
isPermitted (Permitted _) = True
isPermitted (Refused _)   = False

-- | A fact that moved between the decision and the requested execution,
-- as the recorded basis against the one rebuilt when execution computes
-- readiness again. The recorded basis is not reusable.
data MovedFact = MovedHead Revision Revision
               | MovedTarget Revision Revision
               | MovedTree TreeId TreeId
               | MovedPolicy Policy Policy
               | MovedPatchset PatchsetId PatchsetId
               | MovedAuthorization Authorization Authorization
               | MovedGates [(GateName, EventId, DeclarationId)] [(GateName, EventId, DeclarationId)]
               | MovedPrerequisites [(ChangeId, EventId)] [(ChangeId, EventId)]
               | MovedReadiness [Refusal]  -- ^ Readiness computed again refuses, on these grounds, so no basis can be rebuilt.
  deriving stock (Eq, Ord, Show)

{- | Why an integration is refused. The last three arise only when a
permitted decision is executed; every other is a ground a decision can
stand on, and a missing branch is also refused at execution.
-}
data Refusal = RefusedConflictingDeclarations [GateName]
             | RefusedClosed Closure
             | RefusedIterating
             | RefusedNoPatchset
             | RefusedBlockedBy [ChangeId]
             | RefusedBranchMissing
             | RefusedHeadMoved Revision Revision
             | RefusedNeedsRebase
             | RefusedMergedTreeUnevaluated TreeId
             | RefusedBlockingFindings [FindingId]
             | RefusedContestedVerdict [EventId]
             | RefusedVerdictStands VerdictKind EventId
             | RefusedExternalVerdictStands ExternalKind EventId
             | RefusedStaleApproval EventId PatchsetId
             | RefusedSelfApproval EventId ActorId (Set ActorId)
             | RefusedNoApproval
             | RefusedGates [GateRefusal]
             | RefusedAcceptanceProbes [ProbeRefusal]
             | RefusedHoldActive HoldId
             | RefusedAuthorityWithheld
             | RefusedUndeclaredActor
             | RefusedBasisMoved [MovedFact]
  deriving stock (Eq, Ord, Show)

-- | A stable short name for a refusal, for test output and mutant
-- comparison.
refusalTag :: Refusal -> String
refusalTag = \case
  RefusedConflictingDeclarations _ -> "conflicting-declarations"
  RefusedClosed _                  -> "closed"
  RefusedIterating                 -> "iterating"
  RefusedNoPatchset                -> "no-patchset"
  RefusedBlockedBy _               -> "blocked-by"
  RefusedBranchMissing             -> "branch-missing"
  RefusedHeadMoved _ _             -> "head-moved"
  RefusedNeedsRebase               -> "needs-rebase"
  RefusedMergedTreeUnevaluated _   -> "merged-tree-unevaluated"
  RefusedBlockingFindings _        -> "blocking-findings"
  RefusedContestedVerdict _        -> "contested-verdict"
  RefusedVerdictStands _ _         -> "verdict-stands"
  RefusedExternalVerdictStands _ _ -> "external-verdict-stands"
  RefusedStaleApproval _ _         -> "stale-approval"
  RefusedSelfApproval {}           -> "self-approval"
  RefusedNoApproval                -> "no-approval"
  RefusedGates _                   -> "gates"
  RefusedAcceptanceProbes _        -> "acceptance-probes"
  RefusedHoldActive _              -> "hold-active"
  RefusedUndeclaredActor           -> "undeclared-actor"
  RefusedAuthorityWithheld         -> "authority-withheld"
  RefusedBasisMoved _              -> "basis-moved"

refusalText :: Refusal -> String
refusalText = \case
  RefusedConflictingDeclarations gates
    -> "policy layers declare these gates differently, so there is nothing to evaluate: " <> unwords (map show gates)
  RefusedClosed _           -> "the change is closed"
  RefusedIterating          -> "the change declares it is iterating"
  RefusedNoPatchset         -> "no patchset is recorded"
  RefusedBlockedBy changes  -> "blocked by " <> unwords (map show changes)
  RefusedBranchMissing      -> "the change's branch is gone"
  RefusedNeedsRebase        -> "the head does not merge with its target"
  RefusedMergedTreeUnevaluated tree
    -> "no required gate was evaluated at the merged tree " <> show tree
  RefusedNoApproval         -> "no approval and no waiver is recorded"
  RefusedGates refusals     -> unwords (map gateRefusalText refusals)
  RefusedAcceptanceProbes refusals
    -> unwords (map probeRefusalText refusals)
  RefusedHoldActive hold    -> "hold " <> show hold <> " is active"
  RefusedUndeclaredActor    -> "the acting identity is not declared and policy requires one"
  RefusedAuthorityWithheld  -> "this replica does not hold integration authority"
  RefusedBasisMoved moved   -> "the basis moved: " <> unwords (map movedText moved)
  RefusedHeadMoved observed recorded
    -> "head " <> show observed <> " is not the recorded patchset head " <> show recorded
  RefusedBlockingFindings findings
    -> "blocking findings are open: " <> unwords (map show findings)
  RefusedContestedVerdict events
    -> "the verdict chain is contested: " <> unwords (map show events)
  RefusedVerdictStands kind event
    -> "a " <> show kind <> " verdict at " <> show event <> " stands on the current patchset"
  RefusedExternalVerdictStands kind event
    -> "an external " <> show kind <> " decision at " <> show event <> " stands on the current head"
  RefusedStaleApproval event patchset
    -> "the approval at " <> show event <> " binds to " <> show patchset <> ", not the latest patchset"
  RefusedSelfApproval event actor contributors
    -> "approval at " <> show event <> " from " <> show actor
    <> " is not independent of contributors " <> show contributors
  where
    movedText = \case
      MovedHead before after     -> "head " <> show before <> " -> " <> show after
      MovedTarget before after   -> "target " <> show before <> " -> " <> show after
      MovedTree before after     -> "tree " <> show before <> " -> " <> show after
      MovedPolicy before after   -> "policy " <> show before <> " -> " <> show after
      MovedPatchset before after -> "patchset " <> show before <> " -> " <> show after
      MovedAuthorization before after -> "authorization " <> show before <> " -> " <> show after
      MovedGates before after    -> "gates " <> show before <> " -> " <> show after
      MovedPrerequisites before after -> "prerequisites " <> show before <> " -> " <> show after
      MovedReadiness grounds     -> "readiness refuses: " <> unwords (map refusalTag grounds)

basisText :: DecisionBasis -> String
basisText basis = unwords
  [ "patchset="      <> show basis.patchset
  , "head="          <> show basis.head
  , "tree="          <> show basis.tree
  , "target="        <> show basis.target
  , "authorization=" <> show basis.authorization
  ]
