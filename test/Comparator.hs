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
  , committedOnTarget
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
  pinned "comparator/coverage policy motion" scenario ModelDefect
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
  [ expectTrue "comparator/execution policy motion: the exact answer is adjudicated" "" (adjudicatedAs ModelDefect (compared 0 True Set.empty))
  , expectEq "comparator/execution policy motion: a refusing check is not adjudicated" Disagreed (compared 0 False (Set.singleton "no-valid-approval"))
  , expectEq "comparator/execution policy motion: a refusal under the unmoved policy is not adjudicated" Disagreed (compared 3 False (Set.singleton "no-valid-approval"))
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
  [ expectEq "comparator/decision iterating: the exact answer agrees" Agreed (compared False (Set.singleton "iterating"))
  , expectEq "comparator/decision iterating: an approval blocker is a disagreement" Disagreed (compared False (Set.fromList ["iterating", "no-valid-approval"]))
  , expectEq "comparator/decision iterating: a ready check is not adjudicated" Disagreed (compared True Set.empty)
  , expectEq "comparator/decision iterating: other blockers are not adjudicated" Disagreed (compared False (Set.fromList ["iterating", "gates-not-green"]))
  , expectEq "comparator/decision iterating: with a moved head, only the approval is left out" Agreed (compareAnswer moved (wantedFor moved) (Answer False (Set.fromList ["iterating", "gates-not-green"])))
  , expectEq "comparator/decision iterating: with a moved head, the gates are not left out" Disagreed (compareAnswer moved (wantedFor moved) (Answer False (Set.singleton "iterating")))
  , expectEq "comparator/execution iterating: a refusal without the approval agrees" Agreed (executionComparison scenario 13 False (Set.singleton "iterating"))
  , expectTrue "comparator/execution iterating: without authority, exit 17 is an authority adjudication" "" (adjudicatedAs Unsettled (executionComparison scenario { Scenario.authorityWithheld = True } 17 False (Set.singleton "iterating")))
  , expectEq "comparator/execution iterating: a dry run that would integrate is not adjudicated" Disagreed (executionComparison scenario 0 True Set.empty)
  ]
  where
    scenario  = defaultScenario { Scenario.reviewer = Nothing, Scenario.iterating = True }
    moved     = scenario { Scenario.headMoved = True }
    wantedFor s = let built = build s in expected (refusals built.observation built.state)
    compared isReady blockers = compareAnswer scenario (wantedFor scenario) (Answer isReady blockers)

{- | A declaration or policy the plan commits on the target moves the target
too: arc's answer is the model's for the scenario with the target moved as
well, and any other answer stays a disagreement. Each expected answer is
checked to differ from the unmoved scenario's, so the rule is what makes it
agree.
-}
committedOnTarget :: [Check]
committedOnTarget =
  [ expectTrue "comparator/committed on target: decision, the merge nobody evaluated" (show behind) (Set.member "merged-tree-unevaluated" behind && behind /= wantedFor shapeMoved)
  , expectTrue "comparator/committed on target: decision, a declaration moved with the target" "" (adjudicatedAs Encoding (compareAnswer shapeMoved (wantedFor shapeMoved) (Answer False behind)))
  , expectEq "comparator/committed on target: decision, another answer is not adjudicated" Disagreed (compareAnswer shapeMoved (wantedFor shapeMoved) (Answer False (Set.singleton "closed")))
  , expectTrue "comparator/committed on target: execution, the merge nobody evaluated" (show moved) (Set.member "merged-tree-unevaluated" moved && StoodDown moved /= expectedExecution tightenedBuilt tightenedBuilt.execution)
  , expectTrue "comparator/committed on target: execution, a policy moved with the target" "" (adjudicatedAs Encoding (executionComparison tightened 1 False moved))
  , expectEq "comparator/committed on target: execution, a dry run that would integrate is not adjudicated" Disagreed (executionComparison tightened 0 True Set.empty)
  , expectEq "comparator/committed on target: a history that moves nothing is not adjudicated" Disagreed (compareAnswer defaultScenario (wantedFor defaultScenario) (Answer False (Set.singleton "merged-tree-unevaluated")))
  ]
  where
    shapeMoved     = defaultScenario { Scenario.gateMode = EvidenceShapeMoved }
    behind         = wantedFor shapeMoved { Scenario.targetMode = TargetBehind }
    tightened      = defaultScenario { Scenario.reviewer = Just ActorContributor, Scenario.policy = openPolicy, Scenario.policyAfter = True }
    tightenedBuilt = build tightened
    moved          = let built = build tightened { Scenario.targetAfter = True } in case expectedExecution built built.execution of
      StoodDown refused -> refused
      _other            -> Set.empty
    wantedFor s    = let built = build s in expected (refusals built.observation built.state)

-- | A newer run at the evaluated tree from another environment, or from
-- none, hides nothing (C14), so an answer where it hides the older pass is
-- a disagreement.
hiddenByNewerRun :: [Check]
hiddenByNewerRun =
  [ expectEq "comparator/hidden: another environment hiding the pass is a disagreement" Disagreed (decided otherEnvironment (Answer False (Set.singleton "gates-not-green")))
  , expectEq "comparator/hidden: no environment hiding the pass is a disagreement" Disagreed (decided unrecorded (Answer False (Set.singleton "gates-not-green")))
  , expectEq "comparator/hidden: the older pass answering agrees" Agreed (decided otherEnvironment (Answer True Set.empty))
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
