{-# LANGUAGE RecordWildCards #-}
{- | A compact plan for one candidate history, and what building it yields.

A plan is not a ledger. 'build' interprets it into events with coherent
references — two registrations under one brief, their episodes, the context
the chosen one read or only claimed, an evaluation, a review — and decides
a named selection under the plan's reuse policy. Shrinking edits the plan,
so every counterexample keeps the references its events need.
-}
module Plan
    ( Pick(..)
    , EvidenceMode(..)
    , ReviewerPick(..)
    , ReadMode(..)
    , TargetMode(..)
    , Plan(..)
    , defaultPlan
    , genPlan
    , genSelectable
    , shrinkPlan
    , Built(..)
    , build
    , buildEvents
    , otherPolicy
    , Feature(..)
    , allFeatures
    , featureOf
      -- * fixed coordinates
    , executorA
    , executorB
    , lead
    , independent
    , candidateA
    , candidateB
    , candidateC
    , episodeA
    , episodeB
    , episodeIdle
    , sharedTree
    , repairTree
    , briefLocator
    , briefFirst
    , briefAmendment
    , briefRef
    , buildGate
    , buildDeclaration
    , here
    , targetNow
    ) where

import Arc.Candidate
import Arc.Candidate.Observations qualified as Observations
import Arc.Model.Identifiers
import Arc.Model.Observed ( Observed(..) )

import Data.Either ( isRight )
import Data.List.NonEmpty ( NonEmpty )
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Test.QuickCheck hiding ( replay )


data Pick = PickA
          | PickB
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | How the one gate evaluation relates to the coordinates in force.
data EvidenceMode = EvidenceCovered
                  | EvidenceFailing
                  | EvidenceOutcomeOmitted
                  | EvidenceOtherTree
                  | EvidenceOtherDeclaration
                  | EvidenceOtherEnvironment
                  | EvidenceEnvironmentOmitted
                  | EvidenceNone
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data ReviewerPick = ReviewerIndependent
                  | ReviewerProducerA
                  | ReviewerProducerB
                  | ReviewerLead
                  | ReviewerNone
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | What the chosen candidate's record says about the brief.
data ReadMode = BriefReadWhole
              | BriefReadPartial
              | BriefCoverageOmitted
              | BriefDeclaredOnly
              | BriefInferredOnly
              | BriefSuppliedOnly
              | BriefUnread
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data TargetMode = TargetCurrent
                | TargetStale
                | TargetUnobserved
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data Plan = Plan
  { equalTree           :: !Bool                 -- ^ A and B register one tree.
  , chosen              :: !Pick
  , evaluationOn        :: !Pick
  , evidence            :: !EvidenceMode
  , reviewOn            :: !Pick
  , reviewer            :: !ReviewerPick
  , reviewKind          :: !ReviewKind
  , reviewRequired      :: !Bool
  , leadRepair          :: !Bool
  , readRequired        :: !Bool
  , readMode            :: !ReadMode
  , briefAmended        :: !Bool                 -- ^ The brief gains a newer version after it was read.
  , targetMode          :: !TargetMode
  , targetAfter         :: !Bool                 -- ^ The target moves between decision and promotion.
  , environmentObserved :: !Bool
  , policy              :: !ReusePolicy
  , idleEpisode         :: !Bool                 -- ^ An episode that produces no candidate.
  , sharedEpisode       :: !Bool                 -- ^ B cites A's episode.
  , thirdCandidate      :: !Bool                 -- ^ A's episode also produces C.
  , episodeExpired      :: !Bool                 -- ^ The chosen candidate's episode expires before selection.
  , declaredRoot        :: !(Maybe Pick)
  , capture             :: !(Maybe Capture)      -- ^ The provider's guarantee for the brief version read.
  , promotionObserved   :: !Bool
  }
  deriving stock (Eq, Ord, Show)

defaultPlan :: Plan
defaultPlan = Plan
  { equalTree           = True
  , chosen              = PickA
  , evaluationOn        = PickA
  , evidence            = EvidenceCovered
  , reviewOn            = PickA
  , reviewer            = ReviewerIndependent
  , reviewKind          = Approves
  , reviewRequired      = True
  , leadRepair          = False
  , readRequired        = True
  , readMode            = BriefReadWhole
  , briefAmended        = False
  , targetMode          = TargetCurrent
  , targetAfter         = False
  , environmentObserved = True
  , policy              = ReuseNever
  , idleEpisode         = False
  , sharedEpisode       = False
  , thirdCandidate      = False
  , episodeExpired      = False
  , declaredRoot        = Nothing
  , capture             = Just Pinned
  , promotionObserved   = True
  }

-- coordinates

executorA, executorB, lead, independent, ci :: ActorId
executorA   = ActorId "executor-a"
executorB   = ActorId "executor-b"
lead        = ActorId "lead"
independent = ActorId "reviewer"
ci          = ActorId "ci"

candidateA, candidateB, candidateC :: CandidateId
candidateA = CandidateId "candidate-a"
candidateB = CandidateId "candidate-b"
candidateC = CandidateId "candidate-c"

episodeA, episodeB, episodeIdle :: EpisodeId
episodeA    = EpisodeId "episode-a"
episodeB    = EpisodeId "episode-b"
episodeIdle = EpisodeId "episode-idle"

sharedTree, treeA, treeB, treeC, repairTree, elsewhereTree :: TreeId
sharedTree    = TreeId "tree-shared"
treeA         = TreeId "tree-a"
treeB         = TreeId "tree-b"
treeC         = TreeId "tree-c"
repairTree    = TreeId "tree-repaired"
elsewhereTree = TreeId "tree-elsewhere"

briefLocator :: Locator
briefLocator = LocatesArtifact ArtifactLocator
  { journal  = JournalId "project"
  , filename = ArtifactName "20260101T000000Z-candidate-brief-plan.md"
  }

briefFirst, briefAmendment :: VersionId
briefFirst     = VersionId "sha256:brief-first"
briefAmendment = VersionId "sha256:brief-amended"

-- | The brief as registered: its first version, whole.
briefRef :: ContextRef
briefRef = ContextRef { locator = briefLocator, version = Observed briefFirst, coverage = Observed Whole }

buildGate :: GateName
buildGate = GateName "build"

buildDeclaration, otherDeclaration :: DeclarationId
buildDeclaration = DeclarationId "build-v2"
otherDeclaration = DeclarationId "build-v1"

here, elsewhere :: EnvironmentId
here      = EnvironmentId "env-here"
elsewhere = EnvironmentId "env-elsewhere"

targetNow, targetBefore, targetLater, mergedRevision :: Revision
targetNow      = Revision "target-now"
targetBefore   = Revision "target-before"
targetLater    = Revision "target-later"
mergedRevision = Revision "merged"

evaluationId :: EvaluationId
evaluationId = EvaluationId "evaluation-1"

reviewId :: ReviewId
reviewId = ReviewId "review-1"

readRecord :: ToolRecordId
readRecord = ToolRecordId "tool-read-1"

-- building

-- | What one plan yields.
data Built = Built
  { events                :: ![Event]
  , state                 :: !State
  , observations          :: !Observations
  , executionObservations :: !Observations
  , requirements          :: !Requirements
  , proposal              :: !Proposal
  , decision              :: !(Either (NonEmpty Refusal) SelectionBasis)
  , decisionOtherPolicy   :: !(Either (NonEmpty Refusal) SelectionBasis)
  , promotion             :: !(Maybe (Either Refusal PromotionPlan))
  , finalState            :: !State
  }

otherPolicy :: ReusePolicy -> ReusePolicy
otherPolicy ReuseNever                 = ReuseOnMatchingCoordinates
otherPolicy ReuseOnMatchingCoordinates = ReuseNever

pickCandidate :: Pick -> CandidateId
pickCandidate PickA = candidateA
pickCandidate PickB = candidateB

treeOf :: Plan -> Pick -> TreeId
treeOf plan pick
  | plan.equalTree = sharedTree
  | otherwise      = case pick of
      PickA -> treeA
      PickB -> treeB

episodeOf :: Plan -> Pick -> EpisodeId
episodeOf plan = \case
  PickA -> episodeA
  PickB
    | plan.sharedEpisode -> episodeA
    | otherwise          -> episodeB

producerOf :: Pick -> ActorId
producerOf PickA = executorA
producerOf PickB = executorB

shipped :: Plan -> TreeId
shipped plan
  | plan.leadRepair = repairTree
  | otherwise       = treeOf plan plan.chosen

-- | A tree an evaluation or review of a pick is recorded at: the shipped
-- tree for the chosen candidate, the registered tree for the other.
recordedTree :: Plan -> Pick -> TreeId
recordedTree plan pick
  | pick == plan.chosen = shipped plan
  | otherwise           = treeOf plan pick

-- | The ledger a plan records, in order.
buildEvents :: Plan -> [Event]
buildEvents plan = concat
  [ map EpisodeOpened ([episodeA] <> [ episodeB | not plan.sharedEpisode ] <> [ episodeIdle | plan.idleEpisode ])
  , [ Registered (registered PickA), Registered (registered PickB) ]
  , [ Registered Registration
        { candidateId = candidateC
        , tree        = treeC
        , brief       = briefRef
        , producers   = Set.singleton executorA
        , parents     = [candidateA]
        , episodes    = [episodeA]
        }
    | plan.thirdCandidate
    ]
  , map ContextRecorded contextEvents
  , [ EvaluationRecorded evaluation | Just evaluation <- [evaluationRecord] ]
  , [ ReviewRecorded review | Just review <- [reviewRecord] ]
  , [ EpisodeExpired (episodeOf plan plan.chosen) | plan.episodeExpired ]
  , [ RootDeclared lead (RootCandidate (pickCandidate pick)) | Just pick <- [plan.declaredRoot] ]
  ]
  where
    registered pick = Registration
      { candidateId = pickCandidate pick
      , tree        = treeOf plan pick
      , brief       = briefRef
      , producers   = Set.singleton (producerOf pick)
      , parents     = []
      , episodes    = [episodeOf plan pick]
      }
    chosenEpisode = episodeOf plan plan.chosen
    chosenId      = pickCandidate plan.chosen
    readAt extent = ContextRef { locator = briefLocator, version = Observed briefFirst, coverage = extent }
    contextEvents = case plan.readMode of
      BriefReadWhole        -> [ Read ToolRead { episode = chosenEpisode, record = readRecord, reference = readAt (Observed Whole) } ]
      BriefReadPartial      -> [ Read ToolRead { episode = chosenEpisode, record = readRecord, reference = readAt (Observed (Lines 1 20)) } ]
      BriefCoverageOmitted  -> [ Read ToolRead { episode = chosenEpisode, record = readRecord, reference = readAt Omitted } ]
      BriefDeclaredOnly     ->
        [ Declared Declaration
            { candidate = chosenId
            , kind      = ReliesOn
            , reference = readAt (Observed Whole)
            , declarant = producerOf plan.chosen
            , citation  = Nothing
            }
        ]
      BriefInferredOnly     ->
        [ Inferred Inference
            { candidate = chosenId
            , kind      = ObservedRead
            , reference = readAt (Observed Whole)
            , source    = InferenceSource "brief-in-prompt"
            }
        ]
      BriefSuppliedOnly     -> [ Supplied Supply { episode = chosenEpisode, reference = readAt (Observed Whole) } ]
      BriefUnread           -> []
    evaluationRecord = case plan.evidence of
      EvidenceNone -> Nothing
      mode         -> Just EvaluationRecord
        { evaluationId = evaluationId
        , candidate    = pickCandidate plan.evaluationOn
        , tree         = if mode == EvidenceOtherTree then elsewhereTree else recordedTree plan plan.evaluationOn
        , gate         = buildGate
        , declaration  = if mode == EvidenceOtherDeclaration then otherDeclaration else buildDeclaration
        , environment  = case mode of
            EvidenceOtherEnvironment   -> Observed elsewhere
            EvidenceEnvironmentOmitted -> Omitted
            _recorded                  -> Observed here
        , outcome      = case mode of
            EvidenceFailing        -> Observed Failed
            EvidenceOutcomeOmitted -> Omitted
            _observed              -> Observed Passed
        , evaluator    = ci
        }
    reviewRecord = case plan.reviewer of
      ReviewerNone -> Nothing
      pick         -> Just ReviewRecord
        { reviewId  = reviewId
        , candidate = pickCandidate plan.reviewOn
        , tree      = recordedTree plan plan.reviewOn
        , reviewer  = case pick of
            ReviewerProducerA -> executorA
            ReviewerProducerB -> executorB
            ReviewerLead      -> lead
            _independent      -> independent
        , kind      = plan.reviewKind
        }

build :: Plan -> Built
build plan = Built
  { events                = events
  , state                 = state
  , observations          = observations
  , executionObservations = executionObservations
  , requirements          = requirements
  , proposal              = proposal
  , decision              = decision
  , decisionOtherPolicy   = evaluate (otherPolicy plan.policy) requirements observations state proposal
  , promotion             = promotion
  , finalState            = finalState
  }
  where
    events = buildEvents plan
    state  = either (\refusal -> error ("plan records an unrecordable ledger: " <> show refusal)) id (replay events)
    observations = Observations
      { target      = case plan.targetMode of
          TargetUnobserved -> Omitted
          _observed        -> Observed targetNow
      , environment = if plan.environmentObserved then Observed here else Omitted
      , held        = [(briefLocator, [briefFirst] <> [ briefAmendment | plan.briefAmended ])]
      , captures    = [ ((briefLocator, briefFirst), guarantee) | Just guarantee <- [plan.capture] ]
      }
    executionObservations
      | plan.targetAfter = observations { Observations.target = Observed targetLater }
      | otherwise        = observations
    requirements = Requirements
      { gates             = [(buildGate, buildDeclaration)]
      , independentReview = plan.reviewRequired
      , reads             = [ ReadRequirement { locator = briefLocator, version = briefFirst, extent = Whole } | plan.readRequired ]
      }
    proposal = Proposal
      { selectionId = SelectionId "selection-1"
      , chosen      = pickCandidate plan.chosen
      , destination = Destination { change = ChangeId "change", patchset = PatchsetId 1 }
      , target      = if plan.targetMode == TargetStale then targetBefore else targetNow
      , evaluations = [ evaluationId | plan.evidence /= EvidenceNone ]
      , reviews     = [ reviewId | plan.reviewer /= ReviewerNone ]
      , selector    = lead
      , repairs     = [ Repair { author = lead, tree = repairTree } | plan.leadRepair ]
      }
    decision  = evaluate plan.policy requirements observations state proposal
    promotion = either (const Nothing) (Just . promote executionObservations) decision
    finalState = case decision of
      Left _      -> state
      Right basis -> case record state (SelectionRecorded basis) of
        Left refusal   -> error ("a permitted selection was not recordable: " <> show refusal)
        Right selected -> case promotion of
          Just (Right plan')
            | plan.promotionObserved -> either (error . show) id (recordPromotion plan' (Observed mergedRevision) selected)
          _unpromoted -> selected

-- generation

genPlan :: Gen Plan
genPlan = do
  equalTree           <- frequency [(3, pure True), (2, pure False)]
  chosen              <- elements [PickA, PickB]
  evaluationOn        <- frequency [(3, pure chosen), (2, elements [PickA, PickB])]
  evidence            <- frequency ((8, pure EvidenceCovered) : [ (1, pure mode) | mode <- [minBound .. maxBound], mode /= EvidenceCovered ])
  reviewOn            <- frequency [(3, pure chosen), (2, elements [PickA, PickB])]
  reviewer            <- frequency [(4, pure ReviewerIndependent), (1, elements [minBound .. maxBound])]
  reviewKind          <- frequency [(5, pure Approves), (1, pure RequestsChanges)]
  reviewRequired      <- frequency [(4, pure True), (1, pure False)]
  leadRepair          <- frequency [(4, pure False), (1, pure True)]
  readRequired        <- frequency [(3, pure True), (1, pure False)]
  readMode            <- frequency ((6, pure BriefReadWhole) : [ (1, pure mode) | mode <- [minBound .. maxBound], mode /= BriefReadWhole ])
  briefAmended        <- arbitrary
  targetMode          <- frequency [(6, pure TargetCurrent), (1, pure TargetStale), (1, pure TargetUnobserved)]
  targetAfter         <- frequency [(4, pure False), (1, pure True)]
  environmentObserved <- frequency [(8, pure True), (1, pure False)]
  policy              <- elements [minBound .. maxBound]
  idleEpisode         <- arbitrary
  sharedEpisode       <- arbitrary
  thirdCandidate      <- arbitrary
  episodeExpired      <- arbitrary
  declaredRoot        <- frequency [(2, pure Nothing), (1, Just <$> elements [PickA, PickB])]
  capture             <- elements [Just Pinned, Just Pinned, Just Unpinned, Nothing]
  promotionObserved   <- frequency [(4, pure True), (1, pure False)]
  pure Plan {..}

-- | Plans whose selection the model permits: the histories a promotion or
-- retention fault is tried against.
genSelectable :: Gen Plan
genSelectable = do
  plan <- genPlan
  pure plan
    { Plan.evidence            = EvidenceCovered
    , Plan.evaluationOn        = plan.chosen
    , Plan.reviewOn            = plan.chosen
    , Plan.reviewer            = ReviewerIndependent
    , Plan.reviewKind          = Approves
    , Plan.readMode            = BriefReadWhole
    , Plan.targetMode          = TargetCurrent
    , Plan.environmentObserved = True
    }

{- | Structural shrinking toward the default plan, one field at a time. A
plan's references are fixed coordinates, so no shrink can leave one
dangling.
-}
shrinkPlan :: Plan -> [Plan]
shrinkPlan plan = concat
  [ [ plan { Plan.equalTree = True }                      | not plan.equalTree ]
  , [ plan { Plan.chosen = PickA }                        | plan.chosen /= PickA ]
  , [ plan { Plan.evaluationOn = plan.chosen }            | plan.evaluationOn /= plan.chosen ]
  , [ plan { Plan.evidence = mode }                       | mode <- [minBound .. plan.evidence], mode /= plan.evidence ]
  , [ plan { Plan.reviewOn = plan.chosen }                | plan.reviewOn /= plan.chosen ]
  , [ plan { Plan.reviewer = ReviewerIndependent }        | plan.reviewer /= ReviewerIndependent ]
  , [ plan { Plan.reviewKind = Approves }                 | plan.reviewKind /= Approves ]
  , [ plan { Plan.reviewRequired = False }                | plan.reviewRequired ]
  , [ plan { Plan.leadRepair = False }                    | plan.leadRepair ]
  , [ plan { Plan.readRequired = False }                  | plan.readRequired ]
  , [ plan { Plan.readMode = mode }                       | mode <- [minBound .. plan.readMode], mode /= plan.readMode ]
  , [ plan { Plan.briefAmended = False }                  | plan.briefAmended ]
  , [ plan { Plan.targetMode = TargetCurrent }            | plan.targetMode /= TargetCurrent ]
  , [ plan { Plan.targetAfter = False }                   | plan.targetAfter ]
  , [ plan { Plan.environmentObserved = True }            | not plan.environmentObserved ]
  , [ plan { Plan.policy = ReuseNever }                   | plan.policy /= ReuseNever ]
  , [ plan { Plan.idleEpisode = False }                   | plan.idleEpisode ]
  , [ plan { Plan.sharedEpisode = False }                 | plan.sharedEpisode ]
  , [ plan { Plan.thirdCandidate = False }                | plan.thirdCandidate ]
  , [ plan { Plan.episodeExpired = False }                | plan.episodeExpired ]
  , [ plan { Plan.declaredRoot = Nothing }                | plan.declaredRoot /= Nothing ]
  , [ plan { Plan.capture = Just Pinned }                 | plan.capture /= Just Pinned ]
  , [ plan { Plan.promotionObserved = True }              | not plan.promotionObserved ]
  ]

-- coverage

-- | A class of history the suite must reach before it may claim to have
-- exercised it.
data Feature = FeaturePermitted
             | FeatureEqualTreePair
             | FeatureZeroCandidateEpisode
             | FeatureEpisodeOfThree
             | FeatureExpiredEpisodeUnderRoot
             | FeatureAmendedReference
             | FeatureLeadRepair
             | FeatureDivergentReusePolicies
             | FeatureStaleTarget
             | FeatureStaleEvaluation
             | FeatureDeclaredOnlyRead
             | FeatureCoverageUnknown
             | FeatureRetainedAtRisk
             | FeaturePromotionStoodDown
  deriving stock (Eq, Ord, Show, Enum, Bounded)

allFeatures :: [Feature]
allFeatures = [minBound .. maxBound]

featureOf :: Plan -> Built -> Feature -> Bool
featureOf plan built = \case
  FeaturePermitted               -> isRight built.decision
  FeatureEqualTreePair           -> any ((>= 2) . Set.size) (Map.elems (sharedStorage built.state))
  FeatureZeroCandidateEpisode    -> any (null . candidatesOf built.state) (Map.keys built.state.episodes)
  FeatureEpisodeOfThree          -> any ((>= 3) . length . candidatesOf built.state) (Map.keys built.state.episodes)
  FeatureExpiredEpisodeUnderRoot -> or
    [ collection built.finalState (CandidateObject candidate) /= NoRootReaches
    | (episode, False) <- Map.toList built.finalState.episodes
    , candidate        <- candidatesOf built.finalState episode
    ]
  FeatureAmendedReference        -> case resolve built.observations.held briefRef of
    ResolvedAt _ (_newer : _) -> True
    _unamended                -> False
  FeatureLeadRepair              -> plan.leadRepair && isRight built.decision
  FeatureDivergentReusePolicies  -> isRight built.decision /= isRight built.decisionOtherPolicy
  FeatureStaleTarget             -> any isTargetMoved (grounds built)
  FeatureStaleEvaluation         -> any isStaleCoordinate (grounds built)
  FeatureDeclaredOnlyRead        -> any isDeclaredOnly (grounds built)
  FeatureCoverageUnknown         -> any isCoverageUnknown (grounds built)
  FeatureRetainedAtRisk          -> or [ isAtRisk (retention built.observations built.finalState object) | object <- objects built.finalState ]
  FeaturePromotionStoodDown      -> case built.promotion of
    Just (Left (RefusedBasisMoved _ _)) -> True
    _stood                              -> False
  where
    grounds current = either (foldr (:) []) (const []) current.decision
    isTargetMoved = \case
      RefusedTargetMoved _ _ -> True
      _other                 -> False
    isStaleCoordinate = \case
      RefusedGate _ shortfalls -> any (stale . snd) shortfalls
      _other                   -> False
    stale = \case
      OtherTree _        -> True
      OtherDeclaration _ -> True
      _other             -> False
    isDeclaredOnly = \case
      RefusedReadUnsatisfied _ (OnlyDeclared _) -> True
      _other                                    -> False
    isCoverageUnknown = \case
      RefusedReadUnsatisfied _ (ReadCoverageUnknown _) -> True
      _other                                           -> False
    isAtRisk = \case
      RetainedAtRisk _ _ -> True
      _other             -> False
