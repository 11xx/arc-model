{- | A compact plan for one history: which facts it records and which
observations it is decided under.

A scenario is a plan, not a ledger. 'Generators.build' interprets it into
events with coherent references, so shrinking can drop features without
ever leaving a dangling identifier: the causal references are regenerated,
not edited.
-}
module Scenario
    ( Scenario(..)
    , ActorPick(..)
    , GateMode(..)
    , WorktreeMode(..)
    , TargetMode(..)
    , ProbeMode(..)
    , defaultScenario
    , dangerPolicy
    , openPolicy
    , requireDeclaredPolicy
    , genAnyScenario
    , genDecisionScenario
    , genIntegratable
    , shrinkScenario
    , namedScenarios
    , namedExecutionScenarios
    ) where

import Arc.Model ( DebtKind(..), ExternalKind(..), Policy(..), VerdictKind(..) )
import Arc.Model.Policy qualified as Policy

import Test.QuickCheck


-- | Which identity records the verdict.
data ActorPick = ActorIndependent
               | ActorContributor
               | ActorAssumed
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | How the required gate's evidence relates to the declaration, tree, and
-- environment in force. The declared gate always names a probe.
data GateMode = EvidenceCovered
              | EvidenceFailing
              | EvidenceOtherTree
              | EvidenceShapeMoved
              | EvidenceOtherEnvironment
              | EvidenceUnrecordedEnvironment
              | EvidenceProbeFailed
              | EvidenceRecordUnreadable
              | EvidenceOmitted
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | What the evidence run recorded about the worktree it ran in, and where
-- a dirty-tree waiver was declared.
data WorktreeMode = WorktreeClean
                  | WorktreeDirty
                  | WorktreeDirtyWaived           -- ^ The waiver names the revision the evidence was recorded at.
                  | WorktreeDirtyWaivedElsewhere  -- ^ The waiver names the change's base, before any patchset.
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | How the target moved while the change was open.
data TargetMode = TargetContained        -- ^ The target did not move; the head's own tree is evaluated.
                | TargetBehind           -- ^ The target moved; the gate ran at the head and nobody ran the merge.
                | TargetBehindEvaluated  -- ^ The target moved; the gate ran against the merge.
                | TargetConflicting      -- ^ The target moved in a way the head does not merge with.
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | Whether a brief declares an acceptance probe, and what its runs recorded.
data ProbeMode = ProbeNone
               | ProbeDischarged       -- ^ Failed at the brief's base, passed at the head.
               | ProbeBaselinePassed   -- ^ Passed at the base as well as at the head.
               | ProbeFinalMissing     -- ^ Failed at the base; never run at the head.
               | ProbeFinalFailed      -- ^ Failed at the base and at the head.
               | ProbeUndischargeable  -- ^ The brief's base is the head: a failure and a pass at one revision.
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data Scenario = Scenario
  { patchsets         :: !Int
  , verdictOnFirst    :: !Bool
  , reviewer          :: !(Maybe ActorPick)
  , verdict           :: !VerdictKind
  , provisional       :: !Bool
  , extraContributor  :: !Bool
  , externalVerdict   :: !(Maybe ExternalKind)   -- ^ An upstream decision about the latest head.
  , debt              :: !(Maybe (Int, Maybe DebtKind))
  , gateMode          :: !GateMode
  , blockingFinding   :: !Bool
  , resolveFinding    :: !Bool
  , headMoved         :: !Bool
  , policy            :: !Policy
  , targetAfter       :: !Bool
  , policyAfter       :: !Bool
  , authorityWithheld :: !Bool                   -- ^ The store lacks integration authority when it executes.
  , audit             :: !(Maybe (VerdictKind, Bool))
  , episodeExpired    :: !Bool
  , worktree          :: !WorktreeMode
  , targetMode        :: !TargetMode
  , probe             :: !ProbeMode
  , branchMissing     :: !Bool                   -- ^ The change's branch is gone when the decision is asked.
  , conflictingGates  :: !Bool                   -- ^ A second policy layer declares the required gate differently.
  }
  deriving stock (Eq, Ord, Show)

defaultScenario :: Scenario
defaultScenario = Scenario
  { patchsets         = 1
  , verdictOnFirst    = False
  , reviewer          = Just ActorIndependent
  , verdict           = Approved
  , provisional       = False
  , extraContributor  = False
  , externalVerdict   = Nothing
  , debt              = Nothing
  , gateMode          = EvidenceCovered
  , blockingFinding   = False
  , resolveFinding    = False
  , headMoved         = False
  , policy            = dangerPolicy
  , targetAfter       = False
  , policyAfter       = False
  , authorityWithheld = False
  , audit             = Nothing
  , episodeExpired    = False
  , worktree          = WorktreeClean
  , targetMode        = TargetContained
  , probe             = ProbeNone
  , branchMissing     = False
  , conflictingGates  = False
  }

dangerPolicy :: Policy
dangerPolicy = Policy
  { independentVerdictRequired = True
  , forbidSelfApproval         = True
  , requireDeclaredActor       = False
  }

openPolicy :: Policy
openPolicy = Policy
  { independentVerdictRequired = False
  , forbidSelfApproval         = False
  , requireDeclaredActor       = False
  }

requireDeclaredPolicy :: Policy
requireDeclaredPolicy = dangerPolicy { Policy.requireDeclaredActor = True }

{- | Histories worth naming: each pins one rule the model states, so a reader
of a differential report can find the case by what it exercises rather than
by a seed.
-}
namedScenarios :: [(String, Scenario)]
namedScenarios =
  [ ("approved",                   defaultScenario)
  , ("contributor-reviewer",       defaultScenario { reviewer = Just ActorContributor })
  , ("assumed-reviewer",           defaultScenario { reviewer = Just ActorAssumed })
  , ("assumed-reviewer-open",      defaultScenario { reviewer = Just ActorAssumed, policy = openPolicy })
  , ("self-approval-open",         defaultScenario { reviewer = Just ActorContributor, policy = openPolicy })
  , ("changes-requested",          defaultScenario { verdict = ChangesRequested })
  , ("comment-only",               defaultScenario { verdict = CommentOnly })
  , ("unreviewed",                 defaultScenario { reviewer = Nothing })
  , ("waived",                     defaultScenario { reviewer = Nothing, debt = Just (1, Nothing) })
  , ("waiver-expired",             defaultScenario { reviewer = Nothing, debt = Just (1, Nothing), patchsets = 2 })
  , ("waived-contributor",         defaultScenario { reviewer = Just ActorContributor, debt = Just (1, Nothing) })
  , ("stale-approval",             defaultScenario { patchsets = 2, verdictOnFirst = True })
  , ("finding-open",               defaultScenario { blockingFinding = True })
  , ("finding-resolved",           defaultScenario { blockingFinding = True, resolveFinding = True })
  , ("head-moved",                 defaultScenario { headMoved = True })
  , ("gate-omitted",               defaultScenario { gateMode = EvidenceOmitted })
  , ("gate-failed",                defaultScenario { gateMode = EvidenceFailing })
  , ("gate-other-tree",            defaultScenario { gateMode = EvidenceOtherTree, patchsets = 2 })
  , ("gate-declaration-changed",   defaultScenario { gateMode = EvidenceShapeMoved })
  , ("gate-other-environment",     defaultScenario { gateMode = EvidenceOtherEnvironment })
  , ("gate-environment-unrecorded", defaultScenario { gateMode = EvidenceUnrecordedEnvironment })
  , ("gate-probe-failed",          defaultScenario { gateMode = EvidenceProbeFailed })
  , ("external-approved-open",     defaultScenario { reviewer = Nothing, externalVerdict = Just ExternalApproved, policy = openPolicy })
  , ("external-approved-danger",   defaultScenario { reviewer = Nothing, externalVerdict = Just ExternalApproved })
  , ("external-beside-local",      defaultScenario { externalVerdict = Just ExternalApproved })
  , ("external-changes-requested", defaultScenario { externalVerdict = Just ExternalChangesRequested })
  , ("external-over-waiver",       defaultScenario { reviewer = Nothing, debt = Just (1, Nothing), externalVerdict = Just ExternalChangesRequested })
  , ("external-rejected",          defaultScenario { reviewer = Nothing, externalVerdict = Just ExternalRejected, policy = openPolicy })
  , ("extra-contributor",          defaultScenario { extraContributor = True })
  , ("gate-dirty",                 defaultScenario { worktree = WorktreeDirty })
  , ("gate-dirty-waived",          defaultScenario { worktree = WorktreeDirtyWaived })
  , ("gate-dirty-waived-elsewhere", defaultScenario { worktree = WorktreeDirtyWaivedElsewhere })
  , ("target-behind",              defaultScenario { targetMode = TargetBehind })
  , ("target-behind-evaluated",    defaultScenario { targetMode = TargetBehindEvaluated })
  , ("target-conflicting",         defaultScenario { targetMode = TargetConflicting })
  , ("probe-discharged",           defaultScenario { probe = ProbeDischarged })
  , ("probe-baseline-passed",      defaultScenario { probe = ProbeBaselinePassed })
  , ("probe-final-missing",        defaultScenario { probe = ProbeFinalMissing })
  , ("probe-final-failed",         defaultScenario { probe = ProbeFinalFailed })
  , ("probe-undischargeable",      defaultScenario { probe = ProbeUndischargeable })
  , ("branch-missing",             defaultScenario { branchMissing = True })
  , ("conflicting-gates",          defaultScenario { conflictingGates = True })
  ]

-- | Histories that move something between the decision and the
-- integration, named for the execution channel.
namedExecutionScenarios :: [(String, Scenario)]
namedExecutionScenarios =
  [ ("execute-target-moved",           defaultScenario { targetAfter = True })
  , ("execute-policy-loosened",        defaultScenario { policyAfter = True })
  , ("execute-policy-tightened",       defaultScenario { reviewer = Just ActorContributor, policy = openPolicy, policyAfter = True })
  , ("execute-authority-withheld",     defaultScenario { authorityWithheld = True })
  , ("execute-authority-over-refusal", defaultScenario { verdict = ChangesRequested, authorityWithheld = True })
  , ("execute-target-and-authority",   defaultScenario { targetAfter = True, authorityWithheld = True })
  ]

-- generation

-- | A generator that reaches every feature the suite claims to exercise.
genAnyScenario :: Gen Scenario
genAnyScenario = genScenarioThen genCheckTime

{- | The generator over the fields the decision rests on, with every
check-time fact at its default. Its histories for a seed are the ones
'genAnyScenario' extends: the check-time fields are drawn after the rest,
so drawing them changes none of the others.
-}
genDecisionScenario :: Gen Scenario
genDecisionScenario = genScenarioThen pure

genScenarioThen :: (Scenario -> Gen Scenario) -> Gen Scenario
genScenarioThen extend = do
  patchsets         <- choose (1, 3)
  verdictOnFirst    <- frequency [(2, pure False), (1, pure True)]
  reviewer          <- frequency [(1, pure Nothing), (3, Just <$> arbitrary), (2, pure (Just ActorIndependent))]
  verdict           <- elements [Approved, Approved, ChangesRequested, CommentOnly]
  provisional       <- frequency [(4, pure False), (1, pure True)]
  extraContributor  <- arbitrary
  externalVerdict   <- frequency [(3, pure Nothing), (2, pure (Just ExternalApproved)), (1, pure (Just ExternalChangesRequested)), (1, pure (Just ExternalRejected))]
  debt              <- frequency [(2, pure Nothing), (2, debtFor patchsets)]
  gateMode          <- frequency ((8, pure EvidenceCovered) : [ (1, pure mode) | mode <- [minBound .. maxBound], mode /= EvidenceCovered ])
  blockingFinding   <- frequency [(3, pure False), (1, pure True)]
  resolveFinding    <- frequency [(4, pure False), (1, pure True)]
  headMoved         <- frequency [(4, pure False), (1, pure True)]
  policy            <- elements [dangerPolicy, dangerPolicy, openPolicy, requireDeclaredPolicy]
  targetAfter       <- frequency [(4, pure False), (1, pure True)]
  policyAfter       <- frequency [(4, pure False), (1, pure True)]
  authorityWithheld <- frequency [(5, pure False), (1, pure True)]
  audit             <- frequency [(2, pure Nothing), (1, Just <$> ((,) <$> elements [Approved, ChangesRequested] <*> arbitrary))]
  episodeExpired    <- arbitrary
  extend defaultScenario
    { patchsets         = patchsets
    , verdictOnFirst    = verdictOnFirst
    , reviewer          = reviewer
    , verdict           = verdict
    , provisional       = provisional
    , extraContributor  = extraContributor
    , externalVerdict   = externalVerdict
    , debt              = debt
    , gateMode          = gateMode
    , blockingFinding   = blockingFinding
    , resolveFinding    = resolveFinding
    , headMoved         = headMoved
    , policy            = policy
    , targetAfter       = targetAfter
    , policyAfter       = policyAfter
    , authorityWithheld = authorityWithheld
    , audit             = audit
    , episodeExpired    = episodeExpired
    }

-- | The facts arc's check reports beside the decision: the tree evidence
-- ran on, the target's motion, acceptance probes, the branch, and the gate
-- declarations.
genCheckTime :: Scenario -> Gen Scenario
genCheckTime scenario = do
  worktree         <- frequency ((6, pure WorktreeClean) : [ (1, pure mode) | mode <- [WorktreeDirty ..] ])
  targetMode       <- frequency ((6, pure TargetContained) : [ (1, pure mode) | mode <- [TargetBehind ..] ])
  probe            <- frequency ((5, pure ProbeNone) : (2, pure ProbeDischarged) : [ (1, pure mode) | mode <- [ProbeBaselinePassed ..] ])
  branchMissing    <- frequency [(9, pure False), (1, pure True)]
  conflictingGates <- frequency [(12, pure False), (1, pure True)]
  pure scenario
    { worktree         = worktree
    , targetMode       = targetMode
    , probe            = probe
    , branchMissing    = branchMissing
    , conflictingGates = conflictingGates
    }

debtFor :: Int -> Gen (Maybe (Int, Maybe DebtKind))
debtFor count = do
  index <- choose (1, count)
  kind  <- frequency
    [ (1, pure Nothing)
    , (1, Just <$> elements [NothingRead, MergeResolutionUnread, RepairUnread, ContributorOnly, IndependentReview])
    ]
  pure (Just (index, kind))

-- | A generator restricted to histories an integration would permit. These
-- are the histories a one-invalid-transition mutation is applied to.
genIntegratable :: Gen Scenario
genIntegratable = do
  count            <- choose (1, 3)
  withApproval     <- frequency [(3, pure True), (1, pure False)]
  extraContributor <- arbitrary
  externalVerdict  <- frequency [(3, pure Nothing), (1, pure (Just ExternalApproved))]
  debt             <- frequency [(2, pure Nothing), (2, debtFor count)]
  provisional      <- frequency [(4, pure False), (1, pure True)]
  episodeExpired   <- arbitrary
  audit            <- frequency [(2, pure Nothing), (1, Just <$> ((,) <$> elements [Approved, ChangesRequested] <*> pure True))]
  integratableCheckTime defaultScenario
    { patchsets        = count
    , reviewer         = if withApproval then Just ActorIndependent else Nothing
    , extraContributor = extraContributor
    , externalVerdict  = externalVerdict
    , debt             = if withApproval then debt else Just (count, Nothing)
    , provisional      = provisional
    , episodeExpired   = episodeExpired
    , audit            = audit
    , policy           = dangerPolicy
    }

-- | The check-time facts an integratable history may carry: clean or waived
-- evidence, a merge somebody evaluated, a discharged probe.
integratableCheckTime :: Scenario -> Gen Scenario
integratableCheckTime scenario = do
  worktree   <- frequency [(4, pure WorktreeClean), (1, pure WorktreeDirtyWaived)]
  targetMode <- frequency [(4, pure TargetContained), (1, pure TargetBehindEvaluated)]
  probe      <- frequency [(3, pure ProbeNone), (1, pure ProbeDischarged)]
  pure scenario
    { worktree   = worktree
    , targetMode = targetMode
    , probe      = probe
    }

instance Arbitrary Scenario where
  arbitrary = genAnyScenario
  shrink    = shrinkScenario

instance Arbitrary ActorPick where
  arbitrary    = elements [minBound .. maxBound]
  shrink value = [ candidate | candidate <- [minBound .. value], candidate /= value ]

instance Arbitrary GateMode where
  arbitrary    = elements [minBound .. maxBound]
  shrink value = [ candidate | candidate <- [minBound .. value], candidate /= value ]

{- | Structural shrinking. References are positions, so a shrink that would
leave a reference dangling is filtered out rather than edited: every
candidate keeps the causal references its events need.
-}
shrinkScenario :: Scenario -> [Scenario]
shrinkScenario scenario =
  [ candidate
  | candidate <- candidates
  , all (<= candidate.patchsets) (referencedPatchsets candidate)
  ]
  where
    candidates = concat
      [ [ scenario { patchsets = count }         | count <- [1 .. scenario.patchsets - 1] ]
      , [ scenario { verdictOnFirst = False }    | scenario.verdictOnFirst ]
      , [ scenario { reviewer = Nothing }        | scenario.reviewer /= Nothing ]
      , [ scenario { verdict = Approved }        | scenario.verdict /= Approved ]
      , [ scenario { provisional = False }       | scenario.provisional ]
      , [ scenario { extraContributor = False }  | scenario.extraContributor ]
      , [ scenario { externalVerdict = Nothing } | scenario.externalVerdict /= Nothing ]
      , [ scenario { debt = Nothing }            | scenario.debt /= Nothing ]
      , [ scenario { gateMode = mode }           | mode <- [minBound .. scenario.gateMode], mode /= scenario.gateMode ]
      , [ scenario { blockingFinding = False }   | scenario.blockingFinding ]
      , [ scenario { resolveFinding = False }    | scenario.resolveFinding ]
      , [ scenario { headMoved = False }         | scenario.headMoved ]
      , [ scenario { policy = openPolicy }       | scenario.policy /= openPolicy ]
      , [ scenario { targetAfter = False }       | scenario.targetAfter ]
      , [ scenario { policyAfter = False }       | scenario.policyAfter ]
      , [ scenario { authorityWithheld = False } | scenario.authorityWithheld ]
      , [ scenario { audit = Nothing }           | scenario.audit /= Nothing ]
      , [ scenario { episodeExpired = False }    | scenario.episodeExpired ]
      , [ scenario { worktree = mode }           | mode <- [minBound .. scenario.worktree], mode /= scenario.worktree ]
      , [ scenario { targetMode = mode }         | mode <- [minBound .. scenario.targetMode], mode /= scenario.targetMode ]
      , [ scenario { probe = mode }              | mode <- [minBound .. scenario.probe], mode /= scenario.probe ]
      , [ scenario { branchMissing = False }     | scenario.branchMissing ]
      , [ scenario { conflictingGates = False }  | scenario.conflictingGates ]
      ]
    referencedPatchsets current = case current.debt of
      Nothing         -> []
      Just (index, _) -> [index]
