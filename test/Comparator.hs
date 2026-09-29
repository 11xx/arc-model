{- | The differential's comparator, pinned. An adjudication names one known
difference between the model and arc; every other field of the answer has
to agree for it to apply, so each rule is checked against its exact answer
and against that answer with each unrelated field changed.
-}
module Comparator ( comparatorChecks ) where

import Arc.Model
import Differential.Arc ( Answer(..), DryRun(..), PostIntegration(..) )
import Differential.Compare
import Generators
import Render
import Scenario qualified

import Data.Set ( Set )
import Data.Set qualified as Set


comparatorChecks :: [Check]
comparatorChecks = concat
  [ coveragePolicyMotion
  , coverageExternalBesideLocal
  , coverageUndeclaredReviewer
  , executionPolicyMotion
  , executionAuthority
  , executionWouldIntegrate
  , decisionIterating
  , arcMovedSincePin
  , hiddenByNewerRun
  ]

-- | The answer with each field changed in turn, named by the field.
variants :: PostIntegration -> [(String, PostIntegration)]
variants (PostIntegration integrated basis audit findings owed) =
  [ ("integrated", PostIntegration (not integrated) basis audit findings owed)
  , ("basis",      PostIntegration integrated (Set.insert "nonsense" basis) audit findings owed)
  , ("basis gone", PostIntegration integrated Set.empty audit findings owed)
  , ("audit",      PostIntegration integrated basis (Just (maybe "approved" (const "nonsense") audit)) findings owed)
  , ("audit gone", PostIntegration integrated basis Nothing findings owed)
  , ("findings",   PostIntegration integrated basis audit (findings + 999) owed)
  , ("owed",       PostIntegration integrated basis audit findings (not owed))
  ]

-- | The exact answer adjudicates as the rule's class; every variant that
-- differs from it is left a disagreement unless it is the model's own
-- answer.
pinned :: String -> Scenario -> Kind -> PostIntegration -> [Check]
pinned name scenario kind exact =
  expectTrue (name <> ": the exact answer is adjudicated") (show (comparison exact)) (adjudicatedAs kind (comparison exact))
  : [ expectTrue (name <> ": " <> field <> " changed is not adjudicated") (show (comparison found)) (comparison found `elem` [Disagreed, Agreed])
    | (field, found) <- variants exact
    , found /= wanted
    , found /= exact
    ]
  where
    built      = build scenario
    wanted     = expectedCoverage (historicalAuthorization built.finalState) (coverageAfterIntegration built.finalState)
    comparison = compareCoverage scenario built wanted

adjudicatedAs :: Kind -> Comparison -> Bool
adjudicatedAs kind = \case
  Adjudicated adjudication -> adjudication.kind == kind
  _other                   -> False

-- | A policy loosened between a refused decision and the integration: arc
-- integrates under it, and the history it records is the one the model
-- decides afresh under the loosened policy, audit included.
coveragePolicyMotion :: [Check]
coveragePolicyMotion =
  pinned "comparator/coverage policy motion" scenario Unsettled
    (PostIntegration True (Set.singleton "verdict") (Just "changes-requested") 1 False)
  <> [ expectEq "comparator/coverage policy motion: an unrelated answer is not adjudicated" Disagreed
         (compareCoverage scenario built wanted (PostIntegration True (Set.singleton "nonsense") (Just "nonsense") 999 True))
     ]
  where
    scenario = defaultScenario { Scenario.reviewer = Just ActorContributor, Scenario.policyAfter = True, Scenario.audit = Just (ChangesRequested, True) }
    built    = build scenario
    wanted   = expectedCoverage (historicalAuthorization built.finalState) (coverageAfterIntegration built.finalState)

coverageExternalBesideLocal :: [Check]
coverageExternalBesideLocal =
  pinned "comparator/coverage external beside local"
    defaultScenario { Scenario.externalVerdict = Just ExternalApproved, Scenario.policy = openPolicy }
    Unsettled
    (PostIntegration True (Set.fromList ["verdict", "external"]) Nothing 0 False)

coverageUndeclaredReviewer :: [Check]
coverageUndeclaredReviewer =
  pinned "comparator/coverage undeclared reviewer"
    defaultScenario { Scenario.reviewer = Just ActorAssumed, Scenario.debts = [(1, Nothing)], Scenario.policy = requireDeclaredPolicy }
    Encoding
    (PostIntegration True (Set.singleton "debt") Nothing 0 True)

-- | A dry run under a loosened policy would integrate a history the decision
-- refused, and the check beside it is ready; a refusing check beside exit 0
-- is no such history.
executionPolicyMotion :: [Check]
executionPolicyMotion =
  [ expectTrue "comparator/execution policy motion: the exact answer is adjudicated" "" (adjudicatedAs Unsettled (compared 0 True Set.empty))
  , expectEq "comparator/execution policy motion: a refusing check is not adjudicated" Disagreed (compared 0 False (Set.singleton "no-valid-approval"))
  , expectTrue "comparator/execution policy motion: a refusal under the unmoved policy is arc's movement, not policy motion" "" (adjudicatedAs ArcMoved (compared 3 False (Set.singleton "no-valid-approval")))
  , expectEq "comparator/execution policy motion: a ready check naming a blocker is not adjudicated" Disagreed (compared 0 True (Set.singleton "no-valid-approval"))
  ]
  where
    compared = executionComparison defaultScenario { Scenario.reviewer = Just ActorContributor, Scenario.policyAfter = True }

-- | A refused decision in a store without authority: exit 17, with the
-- check beside it refusing on exactly the model's grounds.
executionAuthority :: [Check]
executionAuthority =
  [ expectTrue "comparator/execution authority: the exact answer is adjudicated" "" (adjudicatedAs Unsettled (compared 17 False refusedOn))
  , expectEq "comparator/execution authority: a ready check is not adjudicated" Disagreed (compared 17 True Set.empty)
  , expectEq "comparator/execution authority: other blockers are not adjudicated" Disagreed (compared 17 False (Set.singleton "closed"))
  ]
  where
    scenario  = defaultScenario { Scenario.verdict = ChangesRequested, Scenario.authorityWithheld = True }
    compared  = executionComparison scenario
    refusedOn = Set.singleton "no-valid-approval"

-- | A plan agrees with a dry run that would integrate only where the check
-- beside it is ready and names no blocker.
executionWouldIntegrate :: [Check]
executionWouldIntegrate =
  [ expectEq "comparator/execution would integrate: exit 0 beside a ready check agrees" Agreed (compared 0 True Set.empty)
  , expectEq "comparator/execution would integrate: a refusing check is not agreement" Disagreed (compared 0 False (Set.singleton "no-valid-approval"))
  , expectEq "comparator/execution would integrate: a ready check naming a blocker is not agreement" Disagreed (compared 0 True (Set.singleton "gates-not-green"))
  ]
  where
    compared = executionComparison defaultScenario

-- | An iterating change with no approval: arc's check names iterating and
-- nothing for the approval; any other difference stays a disagreement.
decisionIterating :: [Check]
decisionIterating =
  [ expectTrue "comparator/decision iterating: the exact answer is adjudicated" "" (adjudicatedAs Unsettled (compared False (Set.singleton "iterating")))
  , expectEq "comparator/decision iterating: a ready check is not adjudicated" Disagreed (compared True Set.empty)
  , expectEq "comparator/decision iterating: other blockers are not adjudicated" Disagreed (compared False (Set.fromList ["iterating", "gates-not-green"]))
  , expectTrue "comparator/decision iterating: with a moved head, only the approval is left out" "" (adjudicatedAs Unsettled (compareAnswer moved (wantedFor moved) (Answer False (Set.fromList ["iterating", "gates-not-green"]))))
  , expectEq "comparator/decision iterating: with a moved head, the gates are not left out" Disagreed (compareAnswer moved (wantedFor moved) (Answer False (Set.singleton "iterating")))
  , expectTrue "comparator/execution iterating: a refusal without the approval" "" (adjudicatedAs Unsettled (executionComparison scenario 13 False (Set.singleton "iterating")))
  , expectTrue "comparator/execution iterating: without authority, exit 17 beside that refusal" "" (adjudicatedAs Unsettled (executionComparison scenario { Scenario.authorityWithheld = True } 17 False (Set.singleton "iterating")))
  , expectEq "comparator/execution iterating: a dry run that would integrate is not adjudicated" Disagreed (executionComparison scenario 0 True Set.empty)
  ]
  where
    scenario  = defaultScenario { Scenario.reviewer = Nothing, Scenario.iterating = True }
    moved     = scenario { Scenario.headMoved = True }
    wantedFor s = let built = build s in expected (refusals built.observation built.state)
    compared isReady blockers = compareAnswer scenario (wantedFor scenario) (Answer isReady blockers)

{- | An arc that reads declarations from the target's commits answers a
history whose declaration or policy the plan moved in the worktree as the
model answers it with nothing moved; any other answer stays a disagreement.
-}
arcMovedSincePin :: [Check]
arcMovedSincePin =
  [ expectTrue "comparator/arc moved: decision, a declaration edit read as nothing" "" (adjudicatedAs ArcMoved (compareAnswer shapeMoved (wantedFor shapeMoved) (Answer True Set.empty)))
  , expectEq "comparator/arc moved: decision, another answer is not adjudicated" Disagreed (compareAnswer shapeMoved (wantedFor shapeMoved) (Answer False (Set.singleton "closed")))
  , expectTrue "comparator/arc moved: execution, a tightened policy read as nothing" "" (adjudicatedAs ArcMoved (executionComparison tightened 0 True Set.empty))
  , expectEq "comparator/arc moved: execution, a refusing check is not adjudicated" Disagreed (executionComparison tightened 0 False (Set.singleton "no-valid-approval"))
  , expectTrue "comparator/arc moved: coverage, a declaration edit read as nothing" "" (adjudicatedAs ArcMoved (coverageOf shapeMoved (PostIntegration True (Set.singleton "verdict") Nothing 0 False)))
  , expectEq "comparator/arc moved: coverage, another basis is not adjudicated" Disagreed (coverageOf shapeMoved (PostIntegration True (Set.singleton "debt") Nothing 0 False))
  , expectEq "comparator/arc moved: a history that moves nothing is not adjudicated" Disagreed (compareAnswer defaultScenario (wantedFor defaultScenario) (Answer False (Set.singleton "closed")))
  ]
  where
    shapeMoved  = defaultScenario { Scenario.gateMode = EvidenceShapeMoved }
    tightened   = defaultScenario { Scenario.reviewer = Just ActorContributor, Scenario.policy = openPolicy, Scenario.policyAfter = True }
    wantedFor s = let built = build s in expected (refusals built.observation built.state)
    coverageOf s found = let built = build s in compareCoverage s built (expectedCoverage (historicalAuthorization built.finalState) (coverageAfterIntegration built.finalState)) found

-- | A newer run at the evaluated tree that hides an older pass there: from
-- another environment a Rust defect, from none an open reading; any other
-- answer stays a disagreement.
hiddenByNewerRun :: [Check]
hiddenByNewerRun =
  [ expectTrue "comparator/hidden: another environment hides the pass" "" (adjudicatedAs RustDefect (decided otherEnvironment (Answer False (Set.singleton "gates-not-green"))))
  , expectTrue "comparator/hidden: no environment hides the pass" "" (adjudicatedAs Unsettled (decided unrecorded (Answer False (Set.singleton "gates-not-green"))))
  , expectEq "comparator/hidden: another answer is not adjudicated" Disagreed (decided otherEnvironment (Answer False (Set.singleton "closed")))
  , expectEq "comparator/hidden: with no older pass, nothing is hidden" Disagreed (decided otherEnvironment { Scenario.gateRuns = [] } (Answer True Set.empty))
  ]
  where
    otherEnvironment = defaultScenario { Scenario.patchsets = 3, Scenario.revertLatest = True, Scenario.gateMode = EvidenceOtherEnvironment, Scenario.gateRuns = [(1, GatePass)] }
    unrecorded       = otherEnvironment { Scenario.gateMode = EvidenceUnrecordedEnvironment }
    decided s answer = let built = build s in compareAnswer s (expected (refusals built.observation built.state)) answer

executionComparison :: Scenario -> Int -> Bool -> Set String -> Comparison
executionComparison scenario code isReady blockers =
  compareExecution scenario built (expectedExecution built built.execution) (DryRun code Answer { ready = isReady, blockers = blockers })
  where
    built = build scenario
