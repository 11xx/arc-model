{- | A scenario as arc commands.

The model's ledger is a list of events; arc's is what its commands append.
A plan is the sequence of commands whose appended events are the scenario's,
in the order the model records them, together with the environment the
decision is then asked in, and the moves made between the decision and an
integration. What the commands cannot express is a skip with its reason,
never an approximation.
-}
module Differential.Plan
    ( Identity(..)
    , GateRun(..)
    , Step(..)
    , Plan(..)
    , Skip(..)
    , skipText
    , plan
    , executionSkip
    ) where

import Arc.Model ( DebtKind, ExternalKind, GateResult(..), Policy, VerdictKind )
import Arc.Model.Policy qualified as Policy
import Generators ( flipPolicy, reverts )
import Scenario


-- | Who runs an arc command: a declared actor, or nobody, so that arc
-- assumes one from the harness session.
data Identity = Declared String
              | Assumed
  deriving stock (Eq, Show)

-- | How a gate run comes out, what its environment probe prints, and where
-- it runs.
data GateRun = GateRun
  { fails       :: !Bool
  , probeYields :: !(Maybe String)  -- ^ Nothing makes the probe fail, so the evidence records no identity.
  , dirty       :: !Bool            -- ^ Run with an uncommitted edit in the worktree, removed afterwards.
  , against     :: !Bool            -- ^ Run against the merge with the target rather than at the head.
  }
  deriving stock (Eq, Show)

data Step = Commit FilePath          -- ^ Commit a change to this file in the worktree.
          | Revert                   -- ^ Commit the revert of the worktree's last commit.
          | Snapshot [String]        -- ^ Record the head as a patchset, declaring these contributors.
          | Verify GateRun           -- ^ Run the declared gate at the current head.
          | Review Identity VerdictKind
          | Finding Identity         -- ^ A blocking finding, through a comment-only review the next verdict supersedes.
          | ResolveFinding           -- ^ Resolve the finding recorded last.
          | Debt (Maybe DebtKind)    -- ^ Declare a debt on the current patchset.
          | External ExternalKind    -- ^ Record an external decision about the current head.
          | CommitUnrecorded         -- ^ Commit after the last snapshot, so the head moves.
          | EditGates                -- ^ Change the gate declaration without committing it.
          | WaiveDirty               -- ^ Declare a dirty-tree waiver at the worktree's head, through an ad hoc run.
          | AdvanceTarget            -- ^ Commit on the target a file the change never touches.
          | ConflictTarget FilePath  -- ^ Commit on the target this file, which the change also adds.
          | Brief                    -- ^ Record a brief declaring the acceptance probe, based at the worktree's head.
          | ProbeBaseline Bool       -- ^ Run the probe at the brief's base; True makes it fail.
          | ProbeFinal Bool          -- ^ Run the probe at the head; True makes it fail.
          | DeleteBranch             -- ^ Remove the change's worktree and delete its branch.
          | ConflictDeclarations     -- ^ Declare the required gate again, differently, in the operator's policy layer.
          | Iterate                  -- ^ Declare that the change is iterating.
          | MoveTarget               -- ^ Commit on the target after the decision.
          | MovePolicy Policy FilePath  -- ^ Rewrite the policy the worktree reads, with this file dangerous when the policy requires independence.
          | WithholdAuthority        -- ^ Pair the store with a replica and offer it integration authority.
          | Audit VerdictKind Bool   -- ^ Audit the integrated revision; True audits as somebody other than the author.
  deriving stock (Eq, Show)

data Plan = Plan
  { policy        :: !Policy
  , touchesDanger :: !Bool            -- ^ Whether the change edits the declared dangerous path.
  , steps         :: ![Step]
  , probeAtCheck  :: !(Maybe String)  -- ^ What the probe prints where the decision is asked; Nothing fails it.
  , inWorktree    :: !Bool            -- ^ Ask from the change's worktree; False asks from the main checkout.
  , execution     :: ![Step]          -- ^ What moves between the decision and the integration.
  , audits        :: ![Step]          -- ^ What is recorded after the integration.
  }
  deriving stock (Eq, Show)

-- | Why a scenario has no plan.
data Skip = UnreadableEvidence
          | OtherTreeNeedsTwoPatchsets
          | FindingWithoutVerdict
          | DirtAgainstMerge
          | PolicyWithoutWorktree
  deriving stock (Eq, Ord, Show)

skipText :: Skip -> String
skipText = \case
  UnreadableEvidence         -> "unreadable evidence cannot be recorded through the CLI"
  OtherTreeNeedsTwoPatchsets -> "evidence at another tree needs an earlier patchset to record it at"
  FindingWithoutVerdict      -> "a finding is recorded only with a verdict"
  DirtAgainstMerge           -> "a run against the merge uses a clean checkout of its own, so it records no dirt"
  PolicyWithoutWorktree      -> "a policy moved with no worktree left would dirty the target's checkout, which integrate refuses first"

-- | Why a scenario whose decision replays has no integration to compare.
executionSkip :: Scenario -> Maybe Skip
executionSkip scenario
  | scenario.policyAfter && scenario.branchMissing = Just PolicyWithoutWorktree
  | otherwise                                      = Nothing

plan :: Scenario -> Either Skip Plan
plan scenario
  | scenario.gateMode == EvidenceRecordUnreadable                 = Left UnreadableEvidence
  | scenario.gateMode == EvidenceOtherTree && scenario.patchsets < 2 = Left OtherTreeNeedsTwoPatchsets
  | scenario.blockingFinding && scenario.reviewer == Nothing      = Left FindingWithoutVerdict
  | scenario.worktree /= WorktreeClean && scenario.targetMode == TargetBehindEvaluated && scenario.gateMode /= EvidenceOmitted
      = Left DirtAgainstMerge
  | otherwise = Right Plan
      { policy        = scenario.policy
      , touchesDanger = touchesDanger
      , steps         = beforehand <> concatMap patchset [1 .. scenario.patchsets] <> afterwards
      , probeAtCheck  = if scenario.gateMode == EvidenceProbeFailed then Nothing else Just "here"
      , inWorktree    = not scenario.branchMissing
      , execution     = concat
          [ [ MoveTarget | scenario.targetAfter ]
          , [ MovePolicy (flipPolicy scenario.policy) changed | scenario.policyAfter ]
          , [ WithholdAuthority | scenario.authorityWithheld ]
          ]
      , audits        = [ Audit kind independent | Just (kind, independent) <- [scenario.audit] ]
      }
  where
    touchesDanger = scenario.policy.independentVerdictRequired
    changed       = if touchesDanger then "danger.txt" else "work.txt"
    -- a probe based before the first commit runs its baseline there; one
    -- that cannot be discharged is based at the last patchset's head
    probeBasedEarly = scenario.probe `notElem` [ProbeNone, ProbeUndischargeable]
    beforehand = concat
      [ [ WaiveDirty | scenario.worktree == WorktreeDirtyWaivedElsewhere ]
      , [ AdvanceTarget | scenario.targetMode `elem` [TargetBehind, TargetBehindEvaluated] ]
      , [ Brief | probeBasedEarly ]
      , [ ProbeBaseline (scenario.probe /= ProbeBaselinePassed) | probeBasedEarly ]
      ]
    target
      | scenario.verdictOnFirst && scenario.patchsets > 1 = 1
      | otherwise                                         = scenario.patchsets
    verifyAt
      | scenario.gateMode == EvidenceOtherTree = scenario.patchsets - 1
      | otherwise                              = scenario.patchsets
    patchset index = concat
      [ [ if index == scenario.patchsets && reverts scenario then Revert else Commit changed ]
      , [ step | index == scenario.patchsets, scenario.probe == ProbeUndischargeable, step <- [Brief, ProbeBaseline True] ]
      , [ Snapshot (if scenario.extraContributor then ["author", "other"] else []) ]
      , [ Debt kind | (declaredOn, kind) <- scenario.debts, declaredOn == index ]
      , [ Verify gateRun | index == verifyAt, scenario.gateMode /= EvidenceOmitted ]
      , [ WaiveDirty | index == verifyAt, scenario.gateMode /= EvidenceOmitted, scenario.worktree == WorktreeDirtyWaived ]
      , [ Verify (furtherRun result) | (runAt, result) <- scenario.gateRuns, runAt == index ]
      , [ ProbeFinal (scenario.probe == ProbeFinalFailed) | index == scenario.patchsets, scenario.probe `notElem` [ProbeNone, ProbeFinalMissing] ]
      , if index == target then review else []
      ]
    review = concat
      [ [ Finding (Declared "other") | scenario.blockingFinding ]
      , [ ResolveFinding | scenario.blockingFinding, scenario.resolveFinding ]
      , [ Review (identityOf pick) scenario.verdict | Just pick <- [scenario.reviewer] ]
      ]
    afterwards = concat
      [ [ External kind | Just kind <- [scenario.externalVerdict] ]
      , [ EditGates | scenario.gateMode == EvidenceShapeMoved ]
      , [ ConflictTarget changed | scenario.targetMode == TargetConflicting ]
      , [ CommitUnrecorded | scenario.headMoved ]
      , [ ConflictDeclarations | scenario.conflictingGates ]
      , [ Iterate | scenario.iterating ]
      , [ DeleteBranch | scenario.branchMissing ]
      ]
    gateRun = GateRun
      { fails       = scenario.gateMode == EvidenceFailing
      , probeYields = case scenario.gateMode of
          EvidenceOtherEnvironment      -> Just "elsewhere"
          EvidenceUnrecordedEnvironment -> Nothing
          _here                         -> Just "here"
      , dirty       = scenario.worktree /= WorktreeClean
      , against     = scenario.targetMode == TargetBehindEvaluated
      }
    furtherRun result = GateRun
      { fails       = result == GateFail
      , probeYields = Just "here"
      , dirty       = False
      , against     = False
      }
    identityOf = \case
      ActorIndependent -> Declared "reviewer"
      ActorContributor -> Declared "author"
      ActorAssumed     -> Assumed
