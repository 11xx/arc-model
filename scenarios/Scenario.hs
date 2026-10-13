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
    , ModelPick(..)
    , AssessmentMode(..)
    , IneligibleMode(..)
    , WorktreeMode(..)
    , TargetMode(..)
    , ProbeMode(..)
    , defaultScenario
    , dangerPolicy
    , openPolicy
    , dangerPermittingSelfPolicy
    , undeclaredDangerPolicy
    , requireDeclaredPolicy
    , fastForwardPolicy
    , genAnyScenario
    , genDecisionScenario
    , genIntegratable
    , shrinkScenario
    , namedScenarios
    , namedExecutionScenarios
    , namedCoverageScenarios
    ) where

import Arc.Model ( DangerScope(..), DebtKind(..), ExternalKind(..), GateResult(..), IntegrationShape(..), Policy(..), VerdictKind(..) )
import Arc.Model.Policy qualified as Policy

import Data.List ( sortOn )
import Test.QuickCheck


-- | Which identity records the verdict.
data ActorPick = ActorIndependent
               | ActorContributor
               | ActorAssumed
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | The model a read records: none, as for a person; another model than the
-- implementer's; or the implementer's, at the effort the trailer names or at
-- another.
data ModelPick = PickUnrecorded
               | PickDistinct
               | PickImplementer
               | PickImplementerOtherEffort
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | What the assessment an audit carries says: nothing, that the read counts
-- and describes its auditor and the work, or one way it fails to.
data AssessmentMode = AssessmentNone
                    | AssessmentBound
                    | AssessmentIneligible
                    | AssessmentOtherModel
                    | AssessmentOtherEffort
                    | AssessmentNoIdentities
                    | AssessmentAuthorsOmitted
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | How an @ineligible-review@ debt says why: by qualifier flags, by an
-- assessment file whose independence is @ineligible@, or by one that says
-- the read counts, which arc refuses.
data IneligibleMode = IneligibleDeclared
                    | IneligibleAssessed
                    | IneligibleEligibleFile
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
  , priorVerdicts     :: ![(Int, ActorPick, VerdictKind)]  -- ^ Verdicts recorded before the scenario's own on the same patchset, each on the patchset it names.
  , provisional       :: !Bool
  , extraContributor  :: !Bool
  , externalVerdict   :: !(Maybe ExternalKind)   -- ^ An upstream decision about the latest head.
  , debts             :: ![(Int, Maybe DebtKind)]  -- ^ Debts in recording order, each on the patchset it names, with its declared kind.
  , gateMode          :: !GateMode
  , gateRuns          :: ![(Int, GateResult)]      -- ^ Further clean runs of the gate here, each at the head of the patchset it names.
  , revertLatest      :: !Bool                     -- ^ With three patchsets or more, the latest reverts the one before it and returns to an earlier tree.
  , iterating         :: !Bool                     -- ^ The change declares it is iterating.
  , blockingFinding   :: !Bool
  , resolveFinding    :: !Bool
  , headMoved         :: !Bool
  , policy            :: !Policy
  , targetAfter       :: !Bool
  , policyAfter       :: !Bool
  , authorityWithheld :: !Bool                   -- ^ The store lacks integration authority when it executes.
  , audit             :: !(Maybe (VerdictKind, Bool))
  , implementers      :: !Bool                   -- ^ The commits carry an @Implemented-by@ trailer naming the implementer's model.
  , reviewerModel     :: !ModelPick              -- ^ The model the scenario's own verdict records.
  , auditModel        :: !ModelPick
  , auditAssessment   :: !AssessmentMode
  , ineligibleMode    :: !IneligibleMode
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
  , priorVerdicts     = []
  , provisional       = False
  , extraContributor  = False
  , externalVerdict   = Nothing
  , debts             = []
  , gateMode          = EvidenceCovered
  , gateRuns          = []
  , revertLatest      = False
  , iterating         = False
  , blockingFinding   = False
  , resolveFinding    = False
  , headMoved         = False
  , policy            = dangerPolicy
  , targetAfter       = False
  , policyAfter       = False
  , authorityWithheld = False
  , audit             = Nothing
  , implementers      = False
  , reviewerModel     = PickUnrecorded
  , auditModel        = PickUnrecorded
  , auditAssessment   = AssessmentNone
  , ineligibleMode    = IneligibleDeclared
  , episodeExpired    = False
  , worktree          = WorktreeClean
  , targetMode        = TargetContained
  , probe             = ProbeNone
  , branchMissing     = False
  , conflictingGates  = False
  }

dangerPolicy :: Policy
dangerPolicy = Policy
  { danger               = DangerScoped
  , forbidSelfApproval   = True
  , requireDeclaredActor = False
  , shape                = ShapeMergeCommit
  }

openPolicy :: Policy
openPolicy = Policy
  { danger               = DangerOutside
  , forbidSelfApproval   = False
  , requireDeclaredActor = False
  , shape                = ShapeMergeCommit
  }

-- | A change on a declared danger path where self-approval is not forbidden.
dangerPermittingSelfPolicy :: Policy
dangerPermittingSelfPolicy = dangerPolicy { Policy.forbidSelfApproval = False }

-- | A repository that declares no danger path, where self-approval is not
-- forbidden.
undeclaredDangerPolicy :: Policy
undeclaredDangerPolicy = openPolicy { Policy.danger = DangerUndeclared }

requireDeclaredPolicy :: Policy
requireDeclaredPolicy = dangerPolicy { Policy.requireDeclaredActor = True }

-- | The danger policy under the built-in integration shape, which lands
-- only a head that already contains its target.
fastForwardPolicy :: Policy
fastForwardPolicy = dangerPolicy { Policy.shape = ShapeFastForwardOnly }

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
  , ("waived",                     defaultScenario { reviewer = Nothing, debts = [(1, Nothing)] })
  , ("waiver-expired",             defaultScenario { reviewer = Nothing, debts = [(1, Nothing)], patchsets = 2 })
  , ("waived-contributor",         defaultScenario { reviewer = Just ActorContributor, debts = [(1, Nothing)] })
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
  , ("external-over-waiver",       defaultScenario { reviewer = Nothing, debts = [(1, Nothing)], externalVerdict = Just ExternalChangesRequested })
  , ("external-rejected",          defaultScenario { reviewer = Nothing, externalVerdict = Just ExternalRejected, policy = openPolicy })
  , ("external-approved-danger-self-permitted", defaultScenario { reviewer = Nothing, externalVerdict = Just ExternalApproved, policy = dangerPermittingSelfPolicy })
  , ("external-beside-local-danger-self-permitted", defaultScenario { externalVerdict = Just ExternalApproved, policy = dangerPermittingSelfPolicy })
  , ("external-approved-danger-undeclared", defaultScenario { reviewer = Nothing, externalVerdict = Just ExternalApproved, policy = undeclaredDangerPolicy })
  , ("external-approved-danger-undeclared-self-forbidden", defaultScenario { reviewer = Nothing, externalVerdict = Just ExternalApproved, policy = undeclaredDangerPolicy { Policy.forbidSelfApproval = True } })
  , ("external-approved-beside-debt", defaultScenario { reviewer = Nothing, debts = [(1, Nothing)], externalVerdict = Just ExternalApproved, policy = openPolicy })
  , ("extra-contributor",          defaultScenario { extraContributor = True })
  , ("gate-dirty",                 defaultScenario { worktree = WorktreeDirty })
  , ("gate-dirty-waived",          defaultScenario { worktree = WorktreeDirtyWaived })
  , ("gate-dirty-waived-elsewhere", defaultScenario { worktree = WorktreeDirtyWaivedElsewhere })
  , ("target-behind",              defaultScenario { targetMode = TargetBehind })
  , ("target-behind-evaluated",    defaultScenario { targetMode = TargetBehindEvaluated })
  , ("target-conflicting",         defaultScenario { targetMode = TargetConflicting })
  , ("ff-only-contained",          defaultScenario { policy = fastForwardPolicy })
  , ("ff-only-behind",             defaultScenario { policy = fastForwardPolicy, targetMode = TargetBehind })
  , ("ff-only-behind-evaluated",   defaultScenario { policy = fastForwardPolicy, targetMode = TargetBehindEvaluated })
  , ("ff-only-conflicting",        defaultScenario { policy = fastForwardPolicy, targetMode = TargetConflicting })
  , ("probe-discharged",           defaultScenario { probe = ProbeDischarged })
  , ("probe-baseline-passed",      defaultScenario { probe = ProbeBaselinePassed })
  , ("probe-final-missing",        defaultScenario { probe = ProbeFinalMissing })
  , ("probe-final-failed",         defaultScenario { probe = ProbeFinalFailed })
  , ("probe-undischargeable",      defaultScenario { probe = ProbeUndischargeable })
  , ("branch-missing",             defaultScenario { branchMissing = True })
  , ("conflicting-gates",          defaultScenario { conflictingGates = True })
  , ("gate-older-pass-same-tree",  defaultScenario { patchsets = 3, revertLatest = True, gateMode = EvidenceOmitted, gateRuns = [(1, GatePass), (2, GateFail)] })
  , ("gate-older-pass-newer-other-environment", defaultScenario { patchsets = 3, revertLatest = True, gateMode = EvidenceOtherEnvironment, gateRuns = [(1, GatePass)] })
  , ("gate-older-pass-newer-unrecorded-environment", defaultScenario { patchsets = 3, revertLatest = True, gateMode = EvidenceUnrecordedEnvironment, gateRuns = [(1, GatePass)] })
  , ("waivers-per-patchset",       defaultScenario { reviewer = Nothing, patchsets = 2, debts = [(1, Nothing), (2, Nothing)] })
  , ("iterating-unreviewed",       defaultScenario { reviewer = Nothing, iterating = True })
  , ("iterating-gate-failed",      defaultScenario { reviewer = Nothing, iterating = True, gateMode = EvidenceFailing })
  , ("iterating-refusing-verdict", defaultScenario { verdict = ChangesRequested, iterating = True })
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

-- | Histories that integrate and are then audited, named for the coverage
-- channel.
namedCoverageScenarios :: [(String, Scenario)]
namedCoverageScenarios =
  [ ("cover-ineligible-open",             ineligible)
  , ("cover-ineligible-negative-audit",   ineligible { audit = Just (ChangesRequested, True), auditModel = PickDistinct, auditAssessment = AssessmentBound })
  , ("cover-ineligible-audit-unassessed", ineligible { audit = Just (Approved, True), auditModel = PickDistinct })
  , ("cover-ineligible-audit-bound",      ineligible { audit = Just (Approved, True), auditModel = PickDistinct, auditAssessment = AssessmentBound })
  , ("cover-ineligible-audit-bound-implemented", ineligible { audit = Just (Approved, True), auditModel = PickDistinct, auditAssessment = AssessmentBound, implementers = True })
  , ("cover-ineligible-audit-ineligible", ineligible { audit = Just (Approved, True), auditModel = PickDistinct, auditAssessment = AssessmentIneligible })
  , ("cover-ineligible-audit-other-model", ineligible { audit = Just (Approved, True), auditModel = PickDistinct, auditAssessment = AssessmentOtherModel })
  , ("cover-ineligible-audit-other-effort", ineligible { audit = Just (Approved, True), auditModel = PickDistinct, auditAssessment = AssessmentOtherEffort })
  , ("cover-ineligible-audit-no-identities", ineligible { audit = Just (Approved, True), auditModel = PickDistinct, auditAssessment = AssessmentNoIdentities })
  , ("cover-ineligible-audit-model-unrecorded", ineligible { audit = Just (Approved, True), auditAssessment = AssessmentBound })
  , ("cover-ineligible-audit-authors-omitted", ineligible { audit = Just (Approved, True), auditModel = PickDistinct, auditAssessment = AssessmentAuthorsOmitted, implementers = True })
  , ("cover-ineligible-audit-by-author",  ineligible { audit = Just (Approved, False), auditModel = PickDistinct, auditAssessment = AssessmentBound })
  , ("cover-ineligible-audit-implementer-model", ineligible { audit = Just (ChangesRequested, True), auditModel = PickImplementer, auditAssessment = AssessmentBound, implementers = True })
  , ("cover-ineligible-assessed",         ineligible { ineligibleMode = IneligibleAssessed, audit = Just (Approved, True), auditModel = PickDistinct, auditAssessment = AssessmentBound })
  , ("cover-ineligible-eligible-refused", ineligible { ineligibleMode = IneligibleEligibleFile, reviewer = Nothing })
  , ("cover-ineligible-no-verdict",       ineligible { reviewer = Nothing })
  , ("cover-implementer-model-approval",  defaultScenario { implementers = True, reviewerModel = PickImplementer, policy = dangerPolicy })
  , ("cover-implementer-model-approval-other-effort", defaultScenario { implementers = True, reviewerModel = PickImplementerOtherEffort })
  , ("cover-implementer-model-waived",    defaultScenario { implementers = True, reviewerModel = PickImplementer, debts = [(1, Nothing)] })
  , ("cover-implementer-model-permitted", defaultScenario { implementers = True, reviewerModel = PickImplementer, policy = dangerPermittingSelfPolicy })
  , ("cover-implementer-model-audit",     defaultScenario { reviewer = Nothing, debts = [(1, Nothing)], implementers = True, audit = Just (Approved, True), auditModel = PickImplementer })
  , ("cover-implementer-model-audit-negative", defaultScenario { reviewer = Nothing, debts = [(1, Nothing)], implementers = True, audit = Just (ChangesRequested, True), auditModel = PickImplementer })
  , ("cover-distinct-model-audit",        defaultScenario { reviewer = Nothing, debts = [(1, Nothing)], implementers = True, audit = Just (Approved, True), auditModel = PickDistinct })
  , ("cover-approved",                   defaultScenario)
  , ("cover-approved-negative-audit",    defaultScenario { audit = Just (ChangesRequested, True) })
  , ("cover-approved-approving-audit",   defaultScenario { audit = Just (Approved, True) })
  , ("cover-waived",                     defaultScenario { reviewer = Nothing, debts = [(1, Nothing)] })
  , ("cover-waived-negative-audit",      defaultScenario { reviewer = Nothing, debts = [(1, Nothing)], audit = Just (ChangesRequested, True) })
  , ("cover-waived-author-audit",        defaultScenario { reviewer = Nothing, debts = [(1, Nothing)], audit = Just (Approved, False) })
  , ("cover-self-under-waiver",          defaultScenario { reviewer = Just ActorContributor, debts = [(1, Nothing)] })
  , ("cover-external-only",              defaultScenario { reviewer = Nothing, externalVerdict = Just ExternalApproved, policy = openPolicy })
  , ("cover-external-beside-local",      defaultScenario { externalVerdict = Just ExternalApproved, policy = openPolicy })
  , ("cover-external-beside-local-danger", defaultScenario { externalVerdict = Just ExternalApproved })
  , ("cover-external-danger-undeclared", defaultScenario { reviewer = Nothing, externalVerdict = Just ExternalApproved, policy = undeclaredDangerPolicy })
  , ("cover-debt-beside-external",       defaultScenario { reviewer = Nothing, debts = [(1, Nothing)], externalVerdict = Just ExternalApproved, policy = openPolicy })
  , ("cover-undeclared-reviewer-waived", defaultScenario { reviewer = Just ActorAssumed, debts = [(1, Nothing)], policy = requireDeclaredPolicy })
  ]
  where
    -- an independent approval, and a declared debt that records the read as
    -- one routing does not count
    ineligible = defaultScenario { debts = [(1, Just IneligibleReview)], policy = openPolicy }

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
  debts             <- frequency [(4, pure []), (3, maybe [] pure <$> debtFor patchsets), (1, severalDebts patchsets)]
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
  priorVerdicts     <- frequency [(4, pure []), (1, priorsFor patchsets policy)]
  (gateRuns, revertLatest) <- frequency
    [ (6, pure ([], False))
    , (2, (, False) <$> runsFor patchsets)
    , (1, (, True) <$> runsFor patchsets)
    , (1, pure (revisited patchsets))
    ]
  iterating         <- frequency [(9, pure False), (1, pure True)]
  extend defaultScenario
    { patchsets         = patchsets
    , verdictOnFirst    = verdictOnFirst
    , reviewer          = reviewer
    , verdict           = verdict
    , provisional       = provisional
    , extraContributor  = extraContributor
    , externalVerdict   = externalVerdict
    , debts             = debts
    , priorVerdicts     = priorVerdicts
    , gateRuns          = gateRuns
    , revertLatest      = revertLatest
    , iterating         = iterating
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
  implementers     <- frequency [(2, pure False), (1, pure True)]
  reviewerModel    <- elements [minBound .. maxBound]
  auditModel       <- elements [minBound .. maxBound]
  auditAssessment  <- frequency ((2, pure AssessmentNone) : (3, pure AssessmentBound) : [ (1, pure mode) | mode <- [AssessmentIneligible ..] ])
  ineligibleMode   <- elements [minBound .. maxBound]
  ineligibleDebt   <- frequency [(3, pure False), (1, pure True)]
  pure scenario
    { worktree         = worktree
    , targetMode       = targetMode
    , probe            = probe
    , branchMissing    = branchMissing
    , conflictingGates = conflictingGates
    , implementers     = implementers
    , reviewerModel    = reviewerModel
    , auditModel       = auditModel
    , auditAssessment  = auditAssessment
    , ineligibleMode   = ineligibleMode
    , debts            = if ineligibleDebt then asIneligible scenario.debts else scenario.debts
    }

-- | The scenario's first debt declared as @ineligible-review@, where it has
-- one.
asIneligible :: [(Int, Maybe DebtKind)] -> [(Int, Maybe DebtKind)]
asIneligible = \case
  (index, _) : rest -> (index, Just IneligibleReview) : rest
  []                -> []

debtFor :: Int -> Gen (Maybe (Int, Maybe DebtKind))
debtFor count = Just <$> oneDebt count

oneDebt :: Int -> Gen (Int, Maybe DebtKind)
oneDebt count = do
  index <- choose (1, count)
  kind  <- frequency
    [ (1, pure Nothing)
    , (1, Just <$> elements [NothingRead, MergeResolutionUnread, RepairUnread, ContributorOnly, IndependentReview])
    ]
  pure (index, kind)

-- | Two or three debts, in the order their patchsets were recorded, so two
-- can bind to one patchset or to two.
severalDebts :: Int -> Gen [(Int, Maybe DebtKind)]
severalDebts count = do
  size <- choose (2, 3)
  sortOn fst <$> vectorOf size (oneDebt count)

-- | One or two verdicts before the scenario's own, in patchset order. Where
-- policy requires a declared actor, arc refuses a verdict nobody declared,
-- so none is drawn there.
priorsFor :: Int -> Policy -> Gen [(Int, ActorPick, VerdictKind)]
priorsFor count policy = do
  size <- choose (1, 2)
  sortOn (\(index, _, _) -> index) <$> vectorOf size prior
  where
    prior = (,,) <$> choose (1, count) <*> elements picks <*> elements [Approved, ChangesRequested, CommentOnly]
    picks
      | policy.requireDeclaredActor = [ActorIndependent, ActorContributor]
      | otherwise                   = [minBound .. maxBound]

-- | One or two further runs, each at a patchset of the history.
runsFor :: Int -> Gen [(Int, GateResult)]
runsFor count = do
  size <- choose (1, 2)
  sortOn fst <$> vectorOf size ((,) <$> choose (1, count) <*> frequency [(3, pure GatePass), (1, pure GateFail)])

{- | The rare shape the contract names (C14): an older pass at the tree the
latest patchset returns to, and a newer failing run at the tree between.
Drawn on purpose, since independent draws of the three fields would reach
it too rarely to count.
-}
revisited :: Int -> ([(Int, GateResult)], Bool)
revisited count
  | count >= 3 = ([(count - 2, GatePass), (count - 1, GateFail)], True)
  | otherwise  = ([], False)

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
    , debts            = maybe [] pure (if withApproval then debt else Just (count, Nothing))
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

instance Arbitrary ModelPick where
  arbitrary    = elements [minBound .. maxBound]
  shrink value = [ candidate | candidate <- [minBound .. value], candidate /= value ]

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
      , [ scenario { priorVerdicts = dropAt index scenario.priorVerdicts } | index <- [0 .. length scenario.priorVerdicts - 1] ]
      , [ scenario { provisional = False }       | scenario.provisional ]
      , [ scenario { extraContributor = False }  | scenario.extraContributor ]
      , [ scenario { externalVerdict = Nothing } | scenario.externalVerdict /= Nothing ]
      , [ scenario { debts = dropAt index scenario.debts } | index <- [0 .. length scenario.debts - 1] ]
      , [ scenario { gateMode = mode }           | mode <- [minBound .. scenario.gateMode], mode /= scenario.gateMode ]
      , [ scenario { gateRuns = dropAt index scenario.gateRuns } | index <- [0 .. length scenario.gateRuns - 1] ]
      , [ scenario { revertLatest = False }      | scenario.revertLatest ]
      , [ scenario { iterating = False }         | scenario.iterating ]
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
      , [ scenario { implementers = False }      | scenario.implementers ]
      , [ scenario { reviewerModel = pick }      | pick <- [minBound .. scenario.reviewerModel], pick /= scenario.reviewerModel ]
      , [ scenario { auditModel = pick }         | pick <- [minBound .. scenario.auditModel], pick /= scenario.auditModel ]
      , [ scenario { auditAssessment = mode }    | mode <- [minBound .. scenario.auditAssessment], mode /= scenario.auditAssessment ]
      , [ scenario { ineligibleMode = mode }     | mode <- [minBound .. scenario.ineligibleMode], mode /= scenario.ineligibleMode ]
      , [ scenario { debts = [ (index, Nothing) | (index, Just IneligibleReview) <- scenario.debts ] <> [ debt | debt@(_, kind) <- scenario.debts, kind /= Just IneligibleReview ] }
        | any ((== Just IneligibleReview) . snd) scenario.debts ]
      ]
    referencedPatchsets current = map fst current.debts <> map fst current.gateRuns <> [ index | (index, _, _) <- current.priorVerdicts ]
    dropAt index items = take index items <> drop (index + 1) items
