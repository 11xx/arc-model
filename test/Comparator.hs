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
  , decisionIterating
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

-- | A policy loosened between the decision and the integration: arc
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
    scenario = defaultScenario { Scenario.policyAfter = True, Scenario.audit = Just (ChangesRequested, True) }
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

-- | A dry run under a loosened policy would integrate, and the check beside
-- it is ready; a refusing check beside exit 0 is no such history.
executionPolicyMotion :: [Check]
executionPolicyMotion =
  [ expectTrue "comparator/execution policy motion: the exact answer is adjudicated" "" (adjudicatedAs Unsettled (compared 0 True Set.empty))
  , expectEq "comparator/execution policy motion: a refusing check is not adjudicated" Disagreed (compared 0 False (Set.singleton "no-valid-approval"))
  , expectEq "comparator/execution policy motion: a refusing exit is not adjudicated" Disagreed (compared 3 False (Set.singleton "no-valid-approval"))
  ]
  where
    compared = executionComparison defaultScenario { Scenario.policyAfter = True }

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

-- | An iterating change with no approval: arc's check names iterating and
-- nothing for the approval; any other difference stays a disagreement.
decisionIterating :: [Check]
decisionIterating =
  [ expectTrue "comparator/decision iterating: the exact answer is adjudicated" "" (adjudicatedAs Unsettled (compared False (Set.singleton "iterating")))
  , expectEq "comparator/decision iterating: a ready check is not adjudicated" Disagreed (compared True Set.empty)
  , expectEq "comparator/decision iterating: other blockers are not adjudicated" Disagreed (compared False (Set.fromList ["iterating", "gates-not-green"]))
  , expectEq "comparator/decision iterating: a moved head is not adjudicated" Disagreed (compareAnswer moved (wantedFor moved) (Answer False (Set.singleton "iterating")))
  ]
  where
    scenario  = defaultScenario { Scenario.reviewer = Nothing, Scenario.iterating = True }
    moved     = scenario { Scenario.headMoved = True }
    wantedFor s = let built = build s in expected (refusals built.observation built.state)
    compared isReady blockers = compareAnswer scenario (wantedFor scenario) (Answer isReady blockers)

executionComparison :: Scenario -> Int -> Bool -> Set String -> Comparison
executionComparison scenario code isReady blockers =
  compareExecution scenario built (expectedExecution built built.execution) (DryRun code Answer { ready = isReady, blockers = blockers })
  where
    built = build scenario
