-- | The candidate spec driver: fixtures, properties, mutant kills, and
-- generator coverage, deterministic from one seed.
module Main ( main ) where

import Arc.Candidate
import Arc.Model.Observed ( Observed(..) )
import Fixtures ( fixtureChecks )
import Mutants
import Plan
import Render

import Data.Either ( isRight )
import Data.List ( intercalate )
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import System.Environment ( getArgs )
import System.Exit ( exitFailure, exitSuccess )
import Test.QuickCheck hiding ( replay )
import Test.QuickCheck qualified as QC
import Test.QuickCheck.Gen ( unGen )
import Test.QuickCheck.Random ( mkQCGen )


defaultSeed :: Int
defaultSeed = 20260907

defaultTests :: Int
defaultTests = 300

main :: IO ()
main = do
  args <- getArgs
  let seed  = maybe defaultSeed read (optionValue "--seed" args)
      tests = maybe defaultTests read (optionValue "--tests" args)
  putStrLn "arc-model candidate spec: the proposed candidate protocol"
  putStrLn ("seed " <> show seed <> ", " <> show tests <> " cases per property")
  putStrLn ""

  propertyResults <- propertyChecks seed tests
  mutantResults   <- mutantChecks
  let coverage = coverageCheck seed tests
      checks   = fixtureChecks <> propertyResults <> mutantResults <> [coverage]
      failures = filter (not . (.passed)) checks
  mapM_ printCheck checks
  putStrLn ""
  putStrLn (show (length checks - length failures) <> "/" <> show (length checks) <> " checks passed")

  if null failures
    then do
      putStrLn "replay: cabal v2-test candidate-spec --test-options=\"--seed <seed> --tests <n>\""
      exitSuccess
    else do
      putStrLn "failed:"
      mapM_ (\check -> putStrLn ("  " <> check.name <> ": " <> check.detail)) failures
      exitFailure

printCheck :: Check -> IO ()
printCheck check = putStrLn
  ( "[" <> (if check.passed then "ok" else "FAIL") <> "] "
  <> check.name
  <> (if null check.detail then "" else "  " <> check.detail)
  )

optionValue :: String -> [String] -> Maybe String
optionValue flag arguments = case dropWhile (/= flag) arguments of
  _ : value : _ -> Just value
  _absent       -> Nothing

-- | One QuickCheck run, deterministic from the seed.
runQC :: Int -> Int -> Property -> IO Result
runQC seed tests = quickCheckWithResult QC.stdArgs
  { QC.replay          = Just (mkQCGen seed, 0)
  , QC.maxSuccess      = tests
  , QC.chatty          = False
  , QC.maxDiscardRatio = 50
  }

runProperty :: String -> Int -> Int -> Property -> IO Check
runProperty name seed tests prop = do
  result <- runQC seed tests prop
  pure $ if isSuccess result
    then passCheck name ""
    else failCheck name (counterexampleText result.output)

-- property suite

propertyChecks :: Int -> Int -> IO [Check]
propertyChecks seed tests = sequence
  [ runProperty name (seed + index * 13) tests (forAllShrink genPlan shrinkPlan (\plan -> prop plan (build plan)))
  | (index, (name, prop)) <- zip [1 :: Int ..] properties
  ]

properties :: [(String, Plan -> Built -> Property)]
properties =
  [ ("proposition: no event after registration alters a registration",        prop_registrations_immutable)
  , ("proposition: the basis names the proposal's choice and nothing else",   prop_selection_is_named)
  , ("proposition: review authority belongs to the reviewed registration",    prop_review_authority)
  , ("proposition: every relied-on evaluation answers under the policy",      prop_evidence_grounded)
  , ("proposition: repair authors stay among the contributors",               prop_repairers_contribute)
  , ("proposition: an unknown observation never permits",                     prop_unknown_never_permits)
  , ("proposition: only a tool's read meets a read requirement",              prop_reads_are_observed)
  , ("proposition: a moved target stands the promotion down",                 prop_target_moved_stands_down)
  , ("proposition: a root retains what the selection rests on",               prop_roots_retain)
  , ("proposition: episode expiry changes no collection answer",              prop_expiry_deletes_nothing)
  , ("proposition: never reusing is no looser than reusing on coordinates",   prop_reuse_never_is_stricter)
  , ("proposition: a retained reference is at risk unless pinned",            prop_unpinned_at_risk)
  , ("proposition: a reference resolves to the version it observed",          prop_reference_resolves_observed)
  , ("proposition: an observed-read relation comes from a tool record",       prop_read_relation_is_recorded)
  ]

basisOf :: Built -> Maybe SelectionBasis
basisOf built = either (const Nothing) Just built.decision

prop_registrations_immutable :: Plan -> Built -> Property
prop_registrations_immutable _plan built =
  counterexample "registrations moved" (built.finalState.registrations == Map.fromList [ (r.candidateId, r) | Registered r <- built.events ])

prop_selection_is_named :: Plan -> Built -> Property
prop_selection_is_named _plan built = case basisOf built of
  Nothing    -> property True
  Just basis -> conjoin
    [ counterexample "chosen"      (basis.chosen == built.proposal.chosen)
    , counterexample "target"      (basis.target == built.proposal.target)
    , counterexample "selector"    (basis.selector == built.proposal.selector)
    , counterexample "destination" (basis.destination == built.proposal.destination)
    , counterexample "evaluations" (all ((`elem` built.proposal.evaluations) . snd) basis.gates)
    , counterexample "review"      (all (`elem` built.proposal.reviews) basis.review)
    ]

prop_review_authority :: Plan -> Built -> Property
prop_review_authority plan built = case basisOf built of
  Just basis | plan.reviewRequired -> case basis.review >>= (`Map.lookup` built.state.reviews) of
    Nothing     -> counterexample "an independent review is required and none is named" False
    Just review -> conjoin
      [ counterexample "the review names the chosen registration" (review.candidate == basis.chosen)
      , counterexample "the review is of the shipped tree"        (review.tree == basis.tree)
      , counterexample "the reviewer is no contributor"           (review.reviewer `Set.notMember` basis.contributors)
      , counterexample "the review approves"                      (review.kind == Approves)
      ]
  _unreviewed -> property True

prop_evidence_grounded :: Plan -> Built -> Property
prop_evidence_grounded _plan built = case basisOf built of
  Nothing    -> property True
  Just basis -> conjoin
    [ counterexample (show evaluation) $ case Map.lookup evaluation built.state.evaluations of
        Nothing     -> False
        Just recorded ->
          (recorded.candidate == basis.chosen || basis.reuse == ReuseOnMatchingCoordinates)
          && recorded.gate == gate
          && recorded.tree == basis.tree
          && Just recorded.declaration == lookup gate built.requirements.gates
          && recorded.environment == built.observations.environment
          && recorded.environment /= Omitted
          && recorded.outcome == Observed Passed
    | (gate, evaluation) <- basis.gates
    ]

prop_repairers_contribute :: Plan -> Built -> Property
prop_repairers_contribute _plan built = case (basisOf built, registration built.state built.proposal.chosen) of
  (Just basis, Just chosen) -> counterexample (show basis.contributors) $
    basis.contributors == chosen.producers <> Set.fromList (map (.author) built.proposal.repairs)
  _refused -> property True

prop_unknown_never_permits :: Plan -> Built -> Property
prop_unknown_never_permits plan built
  | unknown   = counterexample "permitted on an unknown observation" (not (isRight built.decision))
  | otherwise = property True
  where
    unknown = or
      [ plan.targetMode == TargetUnobserved
      , not plan.environmentObserved
      , plan.evidence `elem` [EvidenceOutcomeOmitted, EvidenceEnvironmentOmitted, EvidenceNone]
      , plan.readRequired && plan.readMode == BriefCoverageOmitted
      ]

prop_reads_are_observed :: Plan -> Built -> Property
prop_reads_are_observed _plan built = case (basisOf built, registration built.state built.proposal.chosen) of
  (Just basis, Just chosen) -> conjoin
    [ counterexample (show toolRecord) $ or
        [ r.episode `elem` chosen.episodes
          && r.reference.locator == requirement.locator
          && r.reference.version == Observed requirement.version
          && maybe False (`covers` requirement.extent) (observedExtent r.reference.coverage)
        | r <- toolReads built.state, r.record == toolRecord
        ]
    | (requirement, toolRecord) <- basis.reads
    ]
  _refused -> property True
  where
    observedExtent = \case
      Observed extent -> Just extent
      Omitted         -> Nothing

prop_target_moved_stands_down :: Plan -> Built -> Property
prop_target_moved_stands_down plan built
  | plan.targetAfter = case built.promotion of
      Nothing                             -> property True
      Just (Left (RefusedBasisMoved _ _)) -> property True
      Just other                          -> counterexample (show other) False
  | otherwise = property True

prop_roots_retain :: Plan -> Built -> Property
prop_roots_retain _plan built = conjoin
  [ counterexample (show object) (collection built.finalState object /= NoRootReaches)
  | basis  <- Map.elems built.finalState.selections
  , object <- concat
      [ [SelectionObject basis.selectionId, CandidateObject basis.chosen, TreeObject basis.tree]
      , [ EvaluationObject evaluation | (_gate, evaluation) <- basis.gates ]
      , [ ContextObject r.brief.locator r.brief.version | Just r <- [registration built.finalState basis.chosen] ]
      , [ EpisodeObject episode | Just r <- [registration built.finalState basis.chosen], episode <- r.episodes ]
      ]
  ]

prop_expiry_deletes_nothing :: Plan -> Built -> Property
prop_expiry_deletes_nothing _plan built = case replay (filter (not . isExpiry) built.events) of
  Left refusal   -> counterexample (show refusal) False
  Right unexpired ->
    let withSelections = foldl (\s basis -> either (const s) id (record s (SelectionRecorded basis))) unexpired (Map.elems built.finalState.selections)
        withPromotions = foldl (\s p -> either (const s) id (record s (PromotionRecorded p))) withSelections built.finalState.promotions
    in counterexample "a collection answer moved with expiry"
         ([ collection built.finalState object | object <- objects built.finalState ] == [ collection withPromotions object | object <- objects built.finalState ])
  where
    isExpiry = \case
      EpisodeExpired _ -> True
      _other           -> False

prop_reuse_never_is_stricter :: Plan -> Built -> Property
prop_reuse_never_is_stricter plan built = counterexample "reuse-never permitted what matching coordinates refused" $
  case plan.policy of
    ReuseNever                 -> not (isRight built.decision) || isRight built.decisionOtherPolicy
    ReuseOnMatchingCoordinates -> not (isRight built.decisionOtherPolicy) || isRight built.decision

prop_unpinned_at_risk :: Plan -> Built -> Property
prop_unpinned_at_risk _plan built = conjoin
  [ counterexample (show object <> " " <> show answer) (acceptable object answer)
  | object@(ContextObject _ _) <- objects built.finalState
  , let answer = retention built.observations built.finalState object
  ]
  where
    acceptable object answer = case (object, answer) of
      (_, Unrooted)                                    -> True
      (ContextObject locator (Observed v), Retained _) -> captureOf built.observations (locator, v) == Observed Pinned
      (_, RetainedAtRisk _ _)                          -> True
      (_, Retained _)                                  -> False

prop_reference_resolves_observed :: Plan -> Built -> Property
prop_reference_resolves_observed _plan built = conjoin
  [ counterexample (show r.reference) $ case (r.reference.version, resolve built.observations.held r.reference) of
      (Observed v, ResolvedAt seen _)       -> seen == v
      (Observed v, VersionUnavailable lost) -> lost == v
      (Omitted, VersionUnobserved)          -> True
      _mismatch                             -> False
  | r <- toolReads built.state
  ]

prop_read_relation_is_recorded :: Plan -> Built -> Property
prop_read_relation_is_recorded _plan built = conjoin
  [ counterexample (show relation) (standing relation.establishment == expected relation.establishment)
  | relation <- relations built.state
  ]
  where
    -- a tool record stands as a record, a declaration as a claim, an
    -- inference as an inference, whatever kind of relation it claims
    expected = \case
      ByToolRecord _  -> StandsAsRecord
      BySupplyRecord  -> StandsAsRecord
      ByLedger        -> StandsAsRecord
      ByDeclaration _ -> StandsAsClaim
      ByInference _   -> StandsAsInference

-- mutants

mutantGenerator :: Mutant -> Gen Plan
mutantGenerator mutant = case mutant.channel of
  ChannelDecision -> genPlan
  _selected       -> genSelectable

mutantChecks :: IO [Check]
mutantChecks = sequence [ runMutantCheck index mutant | (index, mutant) <- zip [1 :: Int ..] allMutants ]

runMutantCheck :: Int -> Mutant -> IO Check
runMutantCheck index mutant = do
  agreement <- runQC (1000 + index * 31) 500 (forAllShrink (mutantGenerator mutant) shrinkPlan (prop_mutant_agrees mutant))
  if isSuccess agreement
    then pure (failCheck name "SURVIVED: no generated plan diverged")
    else do
      predicted <- runQC (2000 + index * 31) 500 (forAllShrink (mutantGenerator mutant) shrinkPlan (prop_mutant_predicted mutant))
      pure $ if isSuccess predicted
        then passCheck name ("killed as " <> show mutant.predicted <> ": " <> counterexampleText agreement.output)
        else failCheck name ("killed, but diverged for an unexpected reason: " <> counterexampleText predicted.output)
  where
    name = "mutant/" <> mutant.name

prop_mutant_agrees :: Mutant -> Plan -> Property
prop_mutant_agrees mutant plan =
  counterexample (show (divergenceOf actual expected) <> " on " <> counterexampleText (show plan)) (actual == expected)
  where
    built    = build plan
    expected = specBehaviour mutant.channel built
    actual   = mutant.run plan built

prop_mutant_predicted :: Mutant -> Plan -> Property
prop_mutant_predicted mutant plan =
  counterexample (show divergence <> " on " <> counterexampleText (show plan)) (predictedHolds mutant.predicted divergence)
  where
    built      = build plan
    divergence = divergenceOf (mutant.run plan built) (specBehaviour mutant.channel built)

-- generator coverage

-- | Generate many plans and report which required classes were reached.
coverageCheck :: Int -> Int -> Check
coverageCheck seed tests
  | null missing = passCheck "generator-coverage" (intercalate ", " [ show feature <> "=" <> show count | (feature, count) <- counts ])
  | otherwise    = failCheck "generator-coverage" ("features never reached: " <> intercalate ", " (map show missing))
  where
    sampleCount = max 4000 tests
    samples = [ unGen genPlan (mkQCGen (seed + index)) 30 | index <- [0 .. sampleCount - 1] ]
    built   = [ (plan, build plan) | plan <- samples ]
    counts  = [ (feature, length [ () | (plan, value) <- built, featureOf plan value feature ]) | feature <- allFeatures ]
    missing = [ feature | (feature, count) <- counts, count == 0 ]
