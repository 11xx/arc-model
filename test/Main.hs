-- | The spec driver: unit fixtures, properties, mutant kills, and generator
-- coverage. Everything is deterministic from one seed.
module Main ( main ) where

import Arc.Model
import Fixtures ( fixtureChecks )
import Generators
import Mutants
import Render

import Data.List ( intercalate )
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
  putStrLn ("arc-model spec: comparison revision " <> comparisonRevision)
  putStrLn ("seed " <> show seed <> ", " <> show tests <> " cases per property")
  putStrLn ""

  propertyResults <- propertyChecks seed tests
  mutantResults   <- mutantChecks
  coverage        <- coverageCheck seed tests
  let checks   = fixtureChecks <> propertyResults <> mutantResults <> [coverage]
      failures = filter (not . (.passed)) checks
  mapM_ printCheck checks
  putStrLn ""
  putStrLn (show (length checks - length failures) <> "/" <> show (length checks) <> " checks passed")

  if null failures
    then do
      putStrLn "replay: cabal v2-test --test-options=\"--seed <seed> --tests <n>\""
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
  [ runProperty name (seed + index * 13) tests (forAllShrink generator shrinkScenario prop)
  | (index, (name, generator, prop)) <- zip [1 :: Int ..] properties
  ]

properties :: [(String, Gen Scenario, Scenario -> Property)]
properties =
  [ ("proposition: every integratable history permits",                    genIntegratable, prop_integratable_permitted)
  , ("proposition: one invalid transition flips the decision",             genIntegratable, prop_mutation_flips)
  , ("proposition: every basis fact is grounded in the ledger",            genAnyScenario,  prop_basis_grounded)
  , ("proposition: an unknown observation never permits",                  genAnyScenario,  prop_unknown_never_permits)
  , ("proposition: a moved basis stands down",                             genAnyScenario,  prop_basis_moved_stands_down)
  , ("proposition: a waiver binds to exactly its patchset",                genAnyScenario,  prop_waiver_exact)
  , ("proposition: a refusing verdict is not waivable",                    genAnyScenario,  prop_refusal_stands)
  , ("proposition: a fulfilled read needs an independent reader",          genAnyScenario,  prop_read_requires_independence)
  , ("proposition: a debt beside an approval authorized nothing",          genAnyScenario,  prop_debt_unused)
  , ("proposition: a negative audit that fulfils a read does not approve", genAnyScenario,  prop_negative_audit_is_not_approval)
  ]

prop_integratable_permitted :: Scenario -> Property
prop_integratable_permitted scenario =
  isIntegratable scenario ==> counterexample (show scenario) (isPermitted (build scenario).decision)

prop_mutation_flips :: Scenario -> Property
prop_mutation_flips scenario =
  isIntegratable scenario ==> conjoin
    [ counterexample ("mutation " <> mutation.name) (mutationInvalidated mutation.scenario)
    | mutation <- mutations scenario
    ]

-- | Either the mutated history refuses, or its execution stands down on a
-- moved basis.
mutationInvalidated :: Scenario -> Bool
mutationInvalidated scenario = case built.decision of
  Refused _   -> True
  Permitted _ -> case built.execution of
    Left (RefusedBasisMoved _) -> True
    _stood                     -> False
  where
    built = build scenario

prop_basis_grounded :: Scenario -> Property
prop_basis_grounded scenario = case built.decision of
  Refused _       -> property True
  Permitted basis -> conjoin
    [ counterexample "the basis patchset is the latest patchset" (Just basis.patchset == ((.patchsetId) <$> latestPatchset built.state))
    , counterexample "the basis tree is the evaluated tree"      (basis.tree == built.observation.evaluatedTree)
    , counterexample "the authorization is recorded"             (authorizationGrounded built.state basis)
    , counterexample "every gate evaluation is recorded"         (all (gateGrounded built.state basis.tree) basis.gates)
    , counterexample "the consumed finding vector was empty"     (null basis.consumedFindings)
    , counterexample "the consumed hold vector was empty"        (null basis.consumedHolds)
    ]
  where
    built = build scenario

authorizationGrounded :: ChangeState -> DecisionBasis -> Bool
authorizationGrounded state basis = case basis.authorization of
  AuthorizedByVerdict event                 -> verdictGrounded state event basis.patchset
  AuthorizedByWaiver debt                   -> debtGrounded state debt basis.patchset
  AuthorizedByVerdictUnderWaiver event debt -> verdictGrounded state event basis.patchset && debtGrounded state debt basis.patchset

verdictGrounded :: ChangeState -> EventId -> PatchsetId -> Bool
verdictGrounded state event patchset = any grounded state.verdicts
  where
    grounded verdict = verdict.event == event && verdict.kind == Approved && verdict.patchset == patchset

debtGrounded :: ChangeState -> DebtId -> PatchsetId -> Bool
debtGrounded state debt patchset = any (\record -> record.debtId == debt && record.patchset == Just patchset) state.debts

gateGrounded :: ChangeState -> TreeId -> (GateName, EventId, DeclarationId) -> Bool
gateGrounded state tree (gate, event, declaration) = any grounded state.verifications
  where
    grounded verification
      = verification.event == event
      && verification.gate == gate
      && verification.declaration == declaration
      && verification.tree == tree
      && verification.result == GatePass
      && verification.readable

prop_unknown_never_permits :: Scenario -> Property
prop_unknown_never_permits scenario
  | scenario.gateMode `elem` [GateOmitted, GateUnreadable, GateOtherTree, GateShapeMoved]
      = counterexample (show scenario) (not (isPermitted (build scenario).decision))
  | otherwise = property True

prop_basis_moved_stands_down :: Scenario -> Property
prop_basis_moved_stands_down scenario
  | scenario.targetAfter || scenario.policyAfter = case built.decision of
      Permitted _ -> counterexample (show scenario) (isBasisMoved built.execution)
      Refused _   -> property True
  | otherwise = property True
  where
    built = build scenario
    isBasisMoved = \case
      Left (RefusedBasisMoved _) -> True
      _stood                     -> False

prop_waiver_exact :: Scenario -> Property
prop_waiver_exact scenario = case built.decision of
  Refused _       -> property True
  Permitted basis -> case authorizationDebts basis.authorization of
    []       -> property True
    debt : _ -> counterexample (show scenario)
      $  debtGrounded built.state debt basis.patchset
      && ((.debtId) <$> newestWaiver built.state basis.patchset) == Just debt
  where
    built = build scenario

prop_refusal_stands :: Scenario -> Property
prop_refusal_stands scenario = case (governingVerdict built.state, latestPatchset built.state) of
  (Just verdict, Just patchset)
    | verdict.kind `elem` [ChangesRequested, CommentOnly]
    , verdict.patchset == patchset.patchsetId
      -> counterexample (show scenario) (not (isPermitted built.decision))
  _unreviewed -> property True
  where
    built = build scenario

-- | A read is recorded only when somebody independent supplied one. The
-- projection never invents a reader, and a self-approval is not one.
prop_read_requires_independence :: Scenario -> Property
prop_read_requires_independence scenario =
  counterexample (show scenario) (coverage.read == Nothing || independentReadExists)
  where
    state    = (build scenario).finalState
    coverage = coverageAfterIntegration state
    independentReadExists = case latestIntegration state of
      Nothing     -> False
      Just record
        -> independentVerdictExists record
        || any (\audit -> audit.revision == record.head && auditIsIndependent state audit) state.audits
    independentVerdictExists record = case record.authorization of
      AuthorizedByVerdict event -> case [ v | v <- state.verdicts, v.event == event ] of
        verdict : _ -> case patchsetById state record.patchset of
          Just patchset -> not verdict.assumed && effectiveActor verdict `Set.notMember` effectiveContributors patchset
          Nothing       -> False
        [] -> False
      _waived -> False

{- | The coverage obligation, the verdict outcome, and the historical
authorization are separate projections. A negative audit that fulfils the
read leaves the read fulfilled, the findings open, and the approval flag
false; the approval flag may only be true because some independent
approving answer exists.
-}
prop_negative_audit_is_not_approval :: Scenario -> Property
prop_negative_audit_is_not_approval scenario = counterexample (show scenario) $
  case (coverage.read, coverage.verdict, coverage.authorization) of
    (Just (ReadByAudit _), Just ChangesRequested, Just authorization)
      | AuthorizedByVerdict _ <- authorization -> property True
      | otherwise -> counterexample "a negative audit must not approve" (not coverage.approved)
    _noNegativeAudit -> property True
  where
    coverage = coverageAfterIntegration (build scenario).finalState

prop_debt_unused :: Scenario -> Property
prop_debt_unused scenario = case built.decision of
  Refused _       -> property True
  Permitted basis -> case basis.authorization of
    AuthorizedByVerdict _ -> counterexample (show scenario) (all (`elem` unused) bound)
      where
        bound  = [ record.debtId | record <- built.state.debts, record.patchset == Just basis.patchset ]
        unused = debtsNotUsed built.state basis.authorization
    _waived -> property True
  where
    built = build scenario

-- mutants

-- | Coverage and historical mutants need a history that actually shipped,
-- so they draw from the integratable generator; the decision and execution
-- mutants need refusal scenarios, so they draw from the open one.
mutantGenerator :: Mutant -> Gen Scenario
mutantGenerator mutant = case mutant.channel of
  ChannelCoverage   -> genIntegratable
  ChannelHistorical -> genIntegratable
  _open             -> genAnyScenario

-- | Every mutant must be killed, and killed for its predicted reason.
mutantChecks :: IO [Check]
mutantChecks = sequence [ runMutantCheck index mutant | (index, mutant) <- zip [1 :: Int ..] allMutants ]

runMutantCheck :: Int -> Mutant -> IO Check
runMutantCheck index mutant = do
  agreement <- runQC (1000 + index * 31) 500 (forAllShrink (mutantGenerator mutant) shrinkScenario (prop_mutant_agrees mutant))
  if isSuccess agreement
    then pure (failCheck name "SURVIVED: no generated scenario diverged")
    else do
      predicted <- runQC (2000 + index * 31) 500 (forAllShrink (mutantGenerator mutant) shrinkScenario (prop_mutant_predicted mutant))
      pure $ if isSuccess predicted
        then passCheck name ("killed as " <> show mutant.predicted <> ": " <> counterexampleText agreement.output)
        else failCheck name ("killed, but diverged for an unexpected reason: " <> counterexampleText predicted.output)
  where
    name = "mutant/" <> mutant.name

prop_mutant_agrees :: Mutant -> Scenario -> Property
prop_mutant_agrees mutant scenario =
  counterexample (show (divergenceOf actual expected) <> " on " <> counterexampleText (show scenario)) (actual == expected)
  where
    built    = build scenario
    expected = specBehaviour mutant.channel built
    actual   = mutant.run built

prop_mutant_predicted :: Mutant -> Scenario -> Property
prop_mutant_predicted mutant scenario =
  counterexample (show divergence <> " on " <> counterexampleText (show scenario)) (predictedHolds mutant.predicted divergence)
  where
    built      = build scenario
    divergence = divergenceOf (mutant.run built) (specBehaviour mutant.channel built)

-- generator coverage

-- | Generate many scenarios and report which required classes were reached.
-- A run that never reaches one cannot claim the suite exercised it.
coverageCheck :: Int -> Int -> IO Check
coverageCheck seed tests = pure $ if null missing
  then passCheck "generator-coverage" (intercalate ", " [ show feature <> "=" <> show count | (feature, count) <- counts ])
  else failCheck "generator-coverage" ("features never reached: " <> intercalate ", " (map show missing))
  where
    sampleCount = max 4000 tests
    samples =
      [ unGen genAnyScenario (mkQCGen (seed + index)) (index `mod` 40 + 1)
      | index <- [0 .. sampleCount - 1]
      ]
    built   = [ (scenario, build scenario) | scenario <- samples ]
    counts  = [ (feature, length [ () | (scenario, value) <- built, featureOf scenario value feature ]) | feature <- allFeatures ]
    missing = [ feature | (feature, count) <- counts, count == 0 ]
