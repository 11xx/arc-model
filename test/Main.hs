-- | The spec driver: unit fixtures, properties, mutant kills, and generator
-- coverage. Everything is deterministic from one seed.
module Main ( main ) where

import Arc.Model
import Comparator ( comparatorChecks )
import Fixtures ( fixtureChecks )
import Generators
import Mutants
import Render
import SandboxChecks ( sandboxChecks )

import Data.List ( intercalate )
import Data.Maybe ( listToMaybe )
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
  sandbox         <- sandboxChecks
  let checks   = fixtureChecks <> comparatorChecks <> sandbox <> propertyResults <> mutantResults <> [coverage]
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
  , ("proposition: the decision is the first standing ground",             genAnyScenario,  prop_decide_is_first_ground)
  , ("proposition: every ground is a fact of the history",                 genAnyScenario,  prop_grounds_are_facts)
  , ("proposition: a check-time fact against the change never permits",    genAnyScenario,  prop_check_time_refuses)
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

-- | Either the mutated history refuses, or its execution stands down: on a
-- moved basis, or on authority the store does not hold.
mutationInvalidated :: Scenario -> Bool
mutationInvalidated scenario = case built.decision of
  Refused _   -> True
  Permitted _ -> either (const True) (const False) built.execution
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
    , counterexample "every consumed declaration is observed" (map (\(gate, d) -> (gate, d.declarationId)) basis.declarations == [ (gate, identifier) | (gate, _, identifier) <- basis.gates ] && all (\(_, d) -> d `elem` built.observation.declarations) basis.declarations)
    , counterexample "every prerequisite closure is observed"   (basis.prerequisites == [ (change, closure) | (change, Just closure) <- built.observation.prerequisites ])
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
  AuthorizedByExternalVerdict event         -> externalGrounded state event basis.head

verdictGrounded :: ChangeState -> EventId -> PatchsetId -> Bool
verdictGrounded state event patchset = any grounded state.verdicts
  where
    grounded verdict = verdict.event == event && verdict.kind == Approved && verdict.patchset == patchset

-- | An external approval grounds a basis only for exactly the head it named.
externalGrounded :: ChangeState -> EventId -> Revision -> Bool
externalGrounded state event revision = any grounded state.externalVerdicts
  where
    grounded external = external.event == event && external.kind == ExternalApproved && external.revision == revision

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

-- | Where the scenario's own run is unknown or answers elsewhere, and no
-- further run could answer instead, nothing permits.
prop_unknown_never_permits :: Scenario -> Property
prop_unknown_never_permits scenario
  | scenario.gateMode `elem` [EvidenceOmitted, EvidenceRecordUnreadable, EvidenceOtherTree, EvidenceShapeMoved, EvidenceOtherEnvironment, EvidenceUnrecordedEnvironment, EvidenceProbeFailed]
  , null scenario.gateRuns
      = counterexample (show scenario) (not (isPermitted (build scenario).decision))
  | otherwise = property True

-- | A permitted decision whose target or policy moved before execution
-- stands down on the moved basis, unless the store cannot act at all, which
-- is refused before the basis is even compared.
prop_basis_moved_stands_down :: Scenario -> Property
prop_basis_moved_stands_down scenario
  | scenario.targetAfter || scenario.policyAfter = case built.decision of
      Permitted _ -> counterexample (show scenario) (stoodDown built.execution)
      Refused _   -> property True
  | otherwise = property True
  where
    built = build scenario
    stoodDown = \case
      Left (RefusedBasisMoved _)    -> not scenario.authorityWithheld
      Left RefusedAuthorityWithheld -> scenario.authorityWithheld
      _acted                        -> False

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

-- | 'decide' is a projection of the grounds: permitted exactly when none
-- stands, and otherwise the first in presentation order.
prop_decide_is_first_ground :: Scenario -> Property
prop_decide_is_first_ground scenario = counterexample (show scenario) $
  case refusals built.observation built.state of
    []         -> isPermitted built.decision
    ground : _ -> built.decision == Refused ground
  where
    built = build scenario

{- | Unwaived dirty evidence, a merge nobody evaluated, a head that does not
merge, a probe left undischarged, a missing branch, and gate declarations
two layers disagree on each refuse whatever else the history holds.
-}
prop_check_time_refuses :: Scenario -> Property
prop_check_time_refuses scenario
  | against   = counterexample (show scenario) (not (isPermitted (build scenario).decision))
  | otherwise = property True
  where
    against = or
      [ scenario.worktree `elem` [WorktreeDirty, WorktreeDirtyWaivedElsewhere]
      , scenario.targetMode `elem` [TargetBehind, TargetConflicting]
      , scenario.probe `notElem` [ProbeNone, ProbeDischarged]
      , scenario.branchMissing
      , scenario.conflictingGates
      ]

-- | Every ground names a fact the history and observations hold, so a
-- reader can check each one against the ledger rather than trust the list.
prop_grounds_are_facts :: Scenario -> Property
prop_grounds_are_facts scenario = conjoin
  [ counterexample (show scenario <> " ground " <> show ground) (grounded ground)
  | ground <- refusals observation state
  ]
  where
    built       = build scenario
    state       = built.state
    observation = built.observation
    latest      = latestPatchset state
    latestId    = (.patchsetId) <$> latest
    grounded = \case
      RefusedClosed closure          -> state.closed == Just closure
      RefusedIterating               -> state.iterating
      RefusedNoPatchset              -> latest == Nothing
      RefusedBlockedBy blockers      -> not (null blockers) && blockers == [ change | (change, Nothing) <- observation.prerequisites ]
      RefusedConflictingDeclarations gates -> not (null gates) && gates == observation.conflictingGates
      RefusedBranchMissing           -> observation.head == Omitted
      RefusedHeadMoved seen recorded -> Observed seen == observation.head && Just recorded == ((.revision) <$> latest) && seen /= recorded
      RefusedNeedsRebase             -> observation.targetRelation == HeadConflictsWithTarget
      RefusedMergedTreeUnevaluated tree
        -> observation.targetRelation == HeadBehindTarget
        && tree == observation.evaluatedTree
        && not (any (\v -> v.tree == tree && v.gate `elem` map fst observation.requiredGates) state.verifications)
      RefusedAcceptanceProbes refused -> not (null refused) && all probeGrounded refused
      RefusedBlockingFindings open   -> not (null open) && open == openBlockingFindings state
      RefusedContestedVerdict events -> verdictContested state && events == map (.event) (activeVerdicts state)
      RefusedVerdictStands kind event
        -> kind /= Approved
        && any (\v -> v.event == event && v.kind == kind && Just v.patchset == latestId) (activeVerdicts state)
      RefusedExternalVerdictStands kind event
        -> kind /= ExternalApproved
        && any (\e -> e.event == event && e.kind == kind && Just e.revision == ((.revision) <$> latest)) state.externalVerdicts
      RefusedStaleApproval event patchset
        -> Just patchset /= latestId
        && any (\v -> v.event == event && v.kind == Approved && v.patchset == patchset) state.verdicts
      RefusedSelfApproval event actor contributors
        -> independenceOwed observation.policy
        && Just contributors == (effectiveContributors <$> latest)
        && any (\v -> v.event == event && effectiveActor v == actor) state.verdicts
      RefusedNoApproval
        -> maybe True (null . debtsForPatchset state) latestId
        && (verdictContested state || not (any (\v -> v.kind == Approved && Just v.patchset == latestId) (activeVerdicts state)))
      RefusedGates refused           -> not (null refused) && all ((`elem` map fst observation.requiredGates) . gateOf) refused
      RefusedHoldActive hold         -> hold `Set.member` state.holds
      RefusedAuthorityWithheld       -> False
      RefusedUndeclaredActor         -> False
      RefusedBasisMoved _            -> False
    brief = do
      patchset <- latest
      wanted   <- patchset.brief
      listToMaybe [ b | b <- state.briefs, b.event == wanted ]
    declared name = maybe False (elem name . (.probes)) brief
    -- the newest run recorded for this probe, phase, and revision, read
    -- straight from the ledger
    ran name phase revision = case reverse [ run.result | run <- state.probeRuns, Just run.brief == ((.event) <$> brief), run.probe == name, run.phase == phase, Just run.revision == revision ] of
      result : _ -> Observed result
      []         -> Omitted
    headRevision = (.revision) <$> latest
    probeGrounded = \case
      ProbeCannotDischarge name
        -> declared name && maybe False (\b -> b.base == Nothing || b.base == headRevision) brief
      ProbeNotDiscriminating name baseline final
        -> declared name
        && baseline == ran name Baseline (brief >>= (.base))
        && final == ran name Final headRevision
        && (baseline, final) /= (Observed GateFail, Observed GatePass)
    gateOf = \case
      GateNotDeclared gate                  -> gate
      GateNeverEvaluated gate               -> gate
      GateEvaluatedOtherTree gate _         -> gate
      GateDeclarationChanged gate           -> gate
      GateFailed gate _                     -> gate
      GateEvidenceUnreadable gate           -> gate
      GateEvaluatedOtherEnvironment gate _ _ -> gate
      GateEnvironmentUnrecorded gate        -> gate
      GateEnvironmentUnobserved gate        -> gate
      GateEvaluatedDirtyTree gate           -> gate
      GateWorktreeUnrecorded gate           -> gate

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
