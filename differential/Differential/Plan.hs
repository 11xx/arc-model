{- | A scenario as arc commands.

The model's ledger is a list of events; arc's is what its commands append.
A plan is the sequence of commands whose appended events are the scenario's,
in the order the model records them, together with the environment the
decision is then asked in. What the commands cannot express is a skip with
its reason, never an approximation.
-}
module Differential.Plan
    ( Identity(..)
    , GateRun(..)
    , Step(..)
    , Plan(..)
    , Skip(..)
    , skipText
    , plan
    ) where

import Arc.Model ( DebtKind, ExternalKind, Policy, VerdictKind )
import Arc.Model.Policy qualified as Policy
import Scenario


-- | Who runs an arc command: a declared actor, or nobody, so that arc
-- assumes one from the harness session.
data Identity = Declared String
              | Assumed
  deriving stock (Eq, Show)

-- | How a gate run comes out, and what its environment probe prints.
data GateRun = GateRun
  { fails       :: !Bool
  , probeYields :: !(Maybe String)  -- ^ Nothing makes the probe fail, so the evidence records no identity.
  }
  deriving stock (Eq, Show)

data Step = Commit FilePath          -- ^ Commit a change to this file in the worktree.
          | Snapshot [String]        -- ^ Record the head as a patchset, declaring these contributors.
          | Verify GateRun           -- ^ Run the declared gate at the current head.
          | Review Identity VerdictKind
          | Finding Identity         -- ^ A blocking finding, through a comment-only review the next verdict supersedes.
          | ResolveFinding           -- ^ Resolve the finding recorded last.
          | Debt (Maybe DebtKind)    -- ^ Declare a debt on the current patchset.
          | External ExternalKind    -- ^ Record an external decision about the current head.
          | CommitUnrecorded         -- ^ Commit after the last snapshot, so the head moves.
          | EditGates                -- ^ Change the gate declaration without committing it.
  deriving stock (Eq, Show)

data Plan = Plan
  { policy        :: !Policy
  , touchesDanger :: !Bool            -- ^ Whether the change edits the declared dangerous path.
  , steps         :: ![Step]
  , probeAtCheck  :: !(Maybe String)  -- ^ What the probe prints where the decision is asked; Nothing fails it.
  }
  deriving stock (Eq, Show)

-- | Why a scenario has no plan.
data Skip = UnreadableEvidence
          | OtherTreeNeedsTwoPatchsets
          | FindingWithoutVerdict
  deriving stock (Eq, Ord, Show)

skipText :: Skip -> String
skipText = \case
  UnreadableEvidence         -> "unreadable evidence cannot be recorded through the CLI"
  OtherTreeNeedsTwoPatchsets -> "evidence at another tree needs an earlier patchset to record it at"
  FindingWithoutVerdict      -> "a finding is recorded only with a verdict"

plan :: Scenario -> Either Skip Plan
plan scenario
  | scenario.gateMode == EvidenceRecordUnreadable                 = Left UnreadableEvidence
  | scenario.gateMode == EvidenceOtherTree && scenario.patchsets < 2 = Left OtherTreeNeedsTwoPatchsets
  | scenario.blockingFinding && scenario.reviewer == Nothing      = Left FindingWithoutVerdict
  | otherwise = Right Plan
      { policy        = scenario.policy
      , touchesDanger = touchesDanger
      , steps         = concatMap patchset [1 .. scenario.patchsets] <> afterwards
      , probeAtCheck  = if scenario.gateMode == EvidenceProbeFailed then Nothing else Just "here"
      }
  where
    touchesDanger = scenario.policy.independentVerdictRequired
    target
      | scenario.verdictOnFirst && scenario.patchsets > 1 = 1
      | otherwise                                         = scenario.patchsets
    verifyAt
      | scenario.gateMode == EvidenceOtherTree = scenario.patchsets - 1
      | otherwise                              = scenario.patchsets
    patchset index = concat
      [ [ Commit (if touchesDanger then "danger.txt" else "work.txt") ]
      , [ Snapshot (if scenario.extraContributor then ["author", "other"] else []) ]
      , [ Debt kind | Just (declaredOn, kind) <- [scenario.debt], declaredOn == index ]
      , [ Verify gateRun | index == verifyAt, scenario.gateMode /= EvidenceOmitted ]
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
      , [ CommitUnrecorded | scenario.headMoved ]
      ]
    gateRun = GateRun
      { fails       = scenario.gateMode == EvidenceFailing
      , probeYields = case scenario.gateMode of
          EvidenceOtherEnvironment      -> Just "elsewhere"
          EvidenceUnrecordedEnvironment -> Nothing
          _here                         -> Just "here"
      }
    identityOf = \case
      ActorIndependent -> Declared "reviewer"
      ActorContributor -> Declared "author"
      ActorAssumed     -> Assumed
