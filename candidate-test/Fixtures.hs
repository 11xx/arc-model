{- | Unit fixtures. Each pins an exact answer: which grounds, which basis,
which retention, which resolution.
-}
module Fixtures ( fixtureChecks ) where

import Arc.Candidate
import Arc.Candidate.Context qualified as Context
import Arc.Model.Identifiers
import Arc.Model.Observed ( Observed(..) )
import Mutants ( Behaviour(..), Mutant(..), allMutants )
import Plan
import Render

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set


fixtureChecks :: [Check]
fixtureChecks = concat
  [ equalTreePair
  , differentTreePair
  , selectionDoesNotMutate
  , staleCoordinates
  , episodeCardinality
  , retainedAcrossExpiry
  , amendedReference
  , leadRepairKeepsLead
  , reusePolicies
  , declarationsAreClaims
  , citationChecked
  , registrationImmutable
  , permissionIsNotEffect
  , captureRisk
  , unknownNeverPasses
  , everyGround
  , demonstratedCounterexample
  ]

selection :: SelectionId
selection = SelectionId "selection-1"

readRequirement :: ReadRequirement
readRequirement = ReadRequirement { locator = briefLocator, version = briefFirst, extent = Whole }

basisOf :: Plan -> Maybe SelectionBasis
basisOf plan = either (const Nothing) Just (build plan).decision

-- | One brief, two registrations of one tree by different producers. They
-- share storage and nothing else: a review of one does not authorize the
-- other.
equalTreePair :: [Check]
equalTreePair =
  [ expectEq "fixture/equal-tree: one tree, two registrations" (Map.fromList [(sharedTree, Set.fromList [candidateA, candidateB])]) (sharedStorage (build defaultPlan).state)
  , expectPermitted "fixture/equal-tree: a review of A authorizes A" (build defaultPlan).decision
  , expectRefusedWith "fixture/equal-tree: a review of A does not authorize B"
      [RefusedNoIndependentReview [(ReviewId "review-1", ReviewOfOtherCandidate candidateA)]]
      (build defaultPlan { Plan.chosen = PickB, Plan.evaluationOn = PickB, Plan.reviewOn = PickA }).decision
  , expectRefusedWith "fixture/equal-tree: B's producer reviewing A is independent of A only"
      [RefusedNoIndependentReview [(ReviewId "review-1", ReviewerIsContributor executorB)]]
      (build defaultPlan { Plan.chosen = PickB, Plan.evaluationOn = PickB, Plan.reviewOn = PickB, Plan.reviewer = ReviewerProducerB }).decision
  , expectPermitted "fixture/equal-tree: B's producer may review A" (build defaultPlan { Plan.reviewer = ReviewerProducerB }).decision
  ]

differentTreePair :: [Check]
differentTreePair =
  [ expectEq "fixture/different-tree: storage is not shared" [1, 1] (map Set.size (Map.elems (sharedStorage (build plan).state)))
  , expectPermitted "fixture/different-tree: A is selectable" (build plan).decision
  ]
  where
    plan = defaultPlan { Plan.equalTree = False }

-- | Selecting and promoting leaves every registration exactly as recorded.
selectionDoesNotMutate :: [Check]
selectionDoesNotMutate =
  [ expectEq "fixture/selection-immutable: registrations unchanged" registered built.finalState.registrations
  , expectEq "fixture/selection-immutable: selected and promoted" (1, 1) (Map.size built.finalState.selections, length built.finalState.promotions)
  , expectEq "fixture/selection-immutable: the selection names the proposal's choice" (Just candidateA) ((.chosen) <$> basisOf defaultPlan)
  ]
  where
    built      = build defaultPlan
    registered = Map.fromList [ (r.candidateId, r) | Registered r <- built.events ]

staleCoordinates :: [Check]
staleCoordinates =
  [ expectRefusedWith "fixture/stale-target: refused" [RefusedTargetMoved (Revision "target-before") targetNow] (build defaultPlan { Plan.targetMode = TargetStale }).decision
  , expectRefusedWith "fixture/stale-evaluation: another tree"
      [RefusedGate buildGate [(EvaluationId "evaluation-1", OtherTree (TreeId "tree-elsewhere"))]]
      (build defaultPlan { Plan.evidence = EvidenceOtherTree }).decision
  , expectRefusedWith "fixture/stale-evaluation: another declaration"
      [RefusedGate buildGate [(EvaluationId "evaluation-1", OtherDeclaration (DeclarationId "build-v1"))]]
      (build defaultPlan { Plan.evidence = EvidenceOtherDeclaration }).decision
  , expectRefusedWith "fixture/stale-evaluation: another environment"
      [RefusedGate buildGate [(EvaluationId "evaluation-1", OtherEnvironment (EnvironmentId "env-elsewhere"))]]
      (build defaultPlan { Plan.evidence = EvidenceOtherEnvironment }).decision
  , expectEq "fixture/stale-target: a target moved after the decision stands down"
      (Just (Left (RefusedBasisMoved targetNow (Just (Revision "target-later")))))
      (build defaultPlan { Plan.targetAfter = True }).promotion
  ]

-- | Episodes and candidates are many-to-many: zero, one, or three.
episodeCardinality :: [Check]
episodeCardinality =
  [ expectEq "fixture/episode: an episode with no candidate" [] (candidatesOf state episodeIdle)
  , expectEq "fixture/episode: an episode with three" [candidateA, candidateB, candidateC] (candidatesOf state episodeA)
  , expectEq "fixture/episode: a candidate citing two episodes"
      (Right [candidateA])
      (flip candidatesOf episodeB <$> replay (map EpisodeOpened [episodeA, episodeB] <> [Registered twoEpisodes]))
  ]
  where
    state = (build defaultPlan { Plan.idleEpisode = True, Plan.sharedEpisode = True, Plan.thirdCandidate = True }).state
    twoEpisodes = Registration
      { candidateId = candidateA
      , tree        = sharedTree
      , brief       = briefRef
      , producers   = Set.singleton executorA
      , parents     = []
      , episodes    = [episodeA, episodeB]
      }

-- | An expired episode ends liveness and deletes nothing a root reaches.
retainedAcrossExpiry :: [Check]
retainedAcrossExpiry =
  [ expectEq "fixture/expiry: the episode is not live" False (episodeLive expired.finalState episodeA)
  , expectPermitted "fixture/expiry: the selection stands" expired.decision
  , expectEq "fixture/expiry: the selected candidate is retained" (CollectionRefused (SelectionRoot selection)) (collection expired.finalState (CandidateObject candidateA))
  , expectEq "fixture/expiry: its episode record is retained" (CollectionRefused (SelectionRoot selection)) (collection expired.finalState (EpisodeObject episodeA))
  , expectEq "fixture/expiry: an unrooted alternative is reached by no root" NoRootReaches (collection expired.finalState (CandidateObject candidateB))
  , expectEq "fixture/expiry: a declared root retains a losing alternative"
      (CollectionRefused (DeclaredRoot lead (RootCandidate candidateB)))
      (collection (build defaultPlan { Plan.episodeExpired = True, Plan.declaredRoot = Just PickB }).finalState (CandidateObject candidateB))
  ]
  where
    expired = build defaultPlan { Plan.episodeExpired = True }

-- | A reference resolves to the version it observed, whatever the artifact
-- became afterwards.
amendedReference :: [Check]
amendedReference =
  [ expectEq "fixture/amended: resolves to the observed version" (ResolvedAt briefFirst [briefAmendment]) (resolve built.observations.held briefRef)
  , expectEq "fixture/amended: the read still answers the requirement" (Just [(readRequirement, ToolRecordId "tool-read-1")]) ((.reads) <$> basisOf plan)
  , expectEq "fixture/amended: an unversioned reference resolves to nothing" VersionUnobserved (resolve built.observations.held briefRef { Context.version = Omitted })
  , expectEq "fixture/amended: a version the provider lost is unavailable" (VersionUnavailable briefFirst) (resolve [(briefLocator, [briefAmendment])] briefRef)
  ]
  where
    plan  = defaultPlan { Plan.briefAmended = True }
    built = build plan

-- | A selection with a lead's repair keeps the lead among the contributors,
-- so the lead is not the independent reviewer of what ships.
leadRepairKeepsLead :: [Check]
leadRepairKeepsLead =
  [ expectEq "fixture/lead-repair: the lead is a contributor" (Just (Set.fromList [executorA, lead])) ((.contributors) <$> basisOf plan)
  , expectEq "fixture/lead-repair: the repaired tree ships" (Just repairTree) ((.tree) <$> basisOf plan)
  , expectRefusedWith "fixture/lead-repair: the lead cannot review it"
      [RefusedNoIndependentReview [(ReviewId "review-1", ReviewerIsContributor lead)]]
      (build plan { Plan.reviewer = ReviewerLead }).decision
  , expectRefusedWith "fixture/lead-repair: a review of the unrepaired tree is stale"
      [RefusedNoIndependentReview [(ReviewId "review-1", ReviewOfOtherTree sharedTree)]]
      (evaluate ReuseNever unreviewed.requirements unreviewed.observations reviewedBefore unreviewed.proposal)
  ]
  where
    plan       = defaultPlan { Plan.leadRepair = True }
    unreviewed = build plan
    -- the same ledger with the review recorded at the registered tree
    reviewedBefore = either (const emptyState) id $ replay $ filter (not . isReview) unreviewed.events <> [ReviewRecorded ReviewRecord
      { reviewId  = ReviewId "review-1"
      , candidate = candidateA
      , tree      = sharedTree
      , reviewer  = independent
      , kind      = Approves
      }]
    isReview = \case
      ReviewRecorded _ -> True
      _other           -> False

-- | The same selection decided under both reuse policies.
reusePolicies :: [Check]
reusePolicies =
  [ expectRefusedWith "fixture/reuse: never reuses another registration's evaluation"
      [RefusedGate buildGate [(EvaluationId "evaluation-1", OtherRegistration candidateB)]]
      (build borrowed).decision
  , expectPermitted "fixture/reuse: matching coordinates reuse it" (build borrowed { Plan.policy = ReuseOnMatchingCoordinates }).decision
  , expectRefusedWith "fixture/reuse: matching coordinates need the tree"
      [RefusedGate buildGate [(EvaluationId "evaluation-1", OtherTree (TreeId "tree-b"))]]
      (build borrowed { Plan.policy = ReuseOnMatchingCoordinates, Plan.equalTree = False }).decision
  , expectRefusedWith "fixture/reuse: an unrecorded environment matches nothing"
      [RefusedGate buildGate [(EvaluationId "evaluation-1", EnvironmentUnrecorded)]]
      (build borrowed { Plan.policy = ReuseOnMatchingCoordinates, Plan.evidence = EvidenceEnvironmentOmitted }).decision
  , expectEq "fixture/reuse: the basis names its policy" (Just ReuseOnMatchingCoordinates) ((.reuse) <$> basisOf borrowed { Plan.policy = ReuseOnMatchingCoordinates })
  , expectRefusedWith "fixture/reuse: review authority is never reused"
      [RefusedNoIndependentReview [(ReviewId "review-1", ReviewOfOtherCandidate candidateB)]]
      (build borrowed { Plan.policy = ReuseOnMatchingCoordinates, Plan.reviewOn = PickB }).decision
  ]
  where
    borrowed = defaultPlan { Plan.evaluationOn = PickB }

-- | A declaration, an inference, and a supply are shown for what they are
-- and none meets a read requirement.
declarationsAreClaims :: [Check]
declarationsAreClaims =
  [ refusedOn BriefDeclaredOnly         (OnlyDeclared [executorA])
  , refusedOn BriefInferredOnly         (OnlyInferred [InferenceSource "brief-in-prompt"])
  , refusedOn BriefSuppliedOnly         OnlySupplied
  , refusedOn BriefCoverageOmitted      (ReadCoverageUnknown [ToolRecordId "tool-read-1"])
  , refusedOn BriefReadPartial          (ReadPartial [ToolRecordId "tool-read-1"])
  , refusedOn BriefUnread               NotRead
  , expectEq "fixture/claims: a reliance stands as a claim" [StandsAsClaim] (standings BriefDeclaredOnly ReliedOn)
  , expectEq "fixture/claims: an inference stands as an inference" [StandsAsInference] (standings BriefInferredOnly ObservedRead)
  , expectEq "fixture/claims: a tool read stands as a record" [StandsAsRecord] (standings BriefReadWhole ObservedRead)
  ]
  where
    refusedOn mode shortfall = expectRefusedWith ("fixture/claims: " <> show mode) [RefusedReadUnsatisfied readRequirement shortfall] (build defaultPlan { Plan.readMode = mode }).decision
    standings mode kind = [ standing r.establishment | r <- relations (build defaultPlan { Plan.readMode = mode }).state, r.kind == kind ]

-- | A citation is checked on the way in; one that resolves to nothing is
-- refused, and one that resolves does not make the claim a read.
citationChecked :: [Check]
citationChecked =
  [ expectEq "fixture/citation: unresolved is refused" (Left (CitationUnresolved (ToolRecordId "tool-read-missing"))) (record state (cite "tool-read-missing"))
  , expectTrue "fixture/citation: resolved is recorded" "a citation of a recorded read must be accepted" (either (const False) (const True) (record state (cite "tool-read-1")))
  ]
  where
    state = (build defaultPlan).state
    cite toolRecord = ContextRecorded $ Declared Declaration
      { candidate = candidateA
      , kind      = ReliesOn
      , reference = briefRef
      , declarant = executorA
      , citation  = Just (ToolRecordId toolRecord)
      }

registrationImmutable :: [Check]
registrationImmutable =
  [ expectEq "fixture/registration: a second registration of one identity is refused" (Left (DuplicateCandidate candidateA)) (record state (Registered again))
  , expectEq "fixture/registration: an unversioned brief is refused" (Left (BriefUnversioned (CandidateId "candidate-d")))
      (record state (Registered unversioned))
  ]
  where
    state = (build defaultPlan).state
    again = Registration
      { candidateId = candidateA
      , tree        = TreeId "tree-other"
      , brief       = briefRef
      , producers   = Set.singleton lead
      , parents     = []
      , episodes    = []
      }
    unversioned = Registration
      { candidateId = CandidateId "candidate-d"
      , tree        = sharedTree
      , brief       = briefRef { Context.version = Omitted }
      , producers   = Set.singleton lead
      , parents     = []
      , episodes    = []
      }

-- | A promotion plan is permission; only an observed effect is recorded.
permissionIsNotEffect :: [Check]
permissionIsNotEffect = case (built.decision, built.promotion) of
  (Right basis, Just (Right plan)) ->
    [ expectEq "fixture/effect: nothing is recorded without an observed effect" (Left (PromotionUnobserved selection)) (recordPromotion plan Omitted selected)
    , expectEq "fixture/effect: an observed effect is recorded" (Right [Promotion { selection = selection, merged = Revision "merged" }])
        ((.promotions) <$> recordPromotion plan (Observed (Revision "merged")) selected)
    ]
    where
      selected = either (const built.state) id (record built.state (SelectionRecorded basis))
  _refused -> [failCheck "fixture/effect" "the default plan must permit and promote"]
  where
    built = build defaultPlan { Plan.promotionObserved = False }

-- | A referenced version a root reaches is at risk unless pinned.
captureRisk :: [Check]
captureRisk =
  [ expectEq "fixture/capture: pinned is retained" (Retained (SelectionRoot selection)) (briefRetention (Just Pinned))
  , expectEq "fixture/capture: unpinned is at risk" (RetainedAtRisk (SelectionRoot selection) CaptureUnpinned) (briefRetention (Just Unpinned))
  , expectEq "fixture/capture: unobserved is at risk" (RetainedAtRisk (SelectionRoot selection) CaptureUnobserved) (briefRetention Nothing)
  ]
  where
    briefRetention guarantee = retention built.observations built.finalState (ContextObject briefLocator (Observed briefFirst))
      where
        built = build defaultPlan { Plan.capture = guarantee }

unknownNeverPasses :: [Check]
unknownNeverPasses =
  [ expectRefusedWith "fixture/unknown: an unobserved outcome" [RefusedGate buildGate [(EvaluationId "evaluation-1", OutcomeUnknown)]] (build defaultPlan { Plan.evidence = EvidenceOutcomeOmitted }).decision
  , expectRefusedWith "fixture/unknown: an unobserved target" [RefusedTargetUnobserved] (build defaultPlan { Plan.targetMode = TargetUnobserved }).decision
  , expectRefusedWith "fixture/unknown: an unobserved environment" [RefusedEnvironmentUnobserved] (build defaultPlan { Plan.environmentObserved = False }).decision
  , expectRefusedWith "fixture/unknown: no evaluation named" [RefusedGate buildGate []] (build defaultPlan { Plan.evidence = EvidenceNone }).decision
  ]

everyGround :: [Check]
everyGround =
  [ expectRefusedWith "fixture/every-ground: target, gate, review, and read"
      [ RefusedTargetMoved (Revision "target-before") targetNow
      , RefusedGate buildGate [(EvaluationId "evaluation-1", OutcomeFailed)]
      , RefusedNoIndependentReview [(ReviewId "review-1", ReviewRequestsChanges)]
      , RefusedReadUnsatisfied readRequirement (OnlyDeclared [executorA])
      ]
      (build defaultPlan { Plan.targetMode = TargetStale, Plan.evidence = EvidenceFailing, Plan.reviewKind = RequestsChanges, Plan.readMode = BriefDeclaredOnly }).decision
  ]

-- | The smallest demonstration: A's producer reviews A. The model refuses;
-- the contributor-identity fault permits.
demonstratedCounterexample :: [Check]
demonstratedCounterexample = case filter ((== "contributor-identity-ignored-in-selection-authority") . (.name)) allMutants of
  mutant : _ ->
    [ expectRefusedWith "fixture/demonstration: the model refuses a producer's review of its own candidate"
        [RefusedNoIndependentReview [(ReviewId "review-1", ReviewerIsContributor executorA)]]
        built.decision
    , case mutant.run plan built of
        BehaviourDecision decision -> expectPermitted "fixture/demonstration: the fault permits" decision
        other                      -> failCheck "fixture/demonstration: the fault permits" ("unexpected channel: " <> show other)
    ]
  [] -> [failCheck "fixture/demonstration" "the contributor-identity mutant is missing"]
  where
    plan  = defaultPlan { Plan.reviewer = ReviewerProducerA }
    built = build plan
