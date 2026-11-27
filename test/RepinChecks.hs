-- | C6, C22, C27, C29, C31-C33, C35, C36, C43 and C45: public claims and faults that must violate them.
module RepinChecks ( repinChecks, repinProperties ) where

import Arc.Model
import Arc.Model.Budget qualified as Budget
import Arc.Model.Declaration qualified as Declaration
import Arc.Model.GatePlan qualified as GatePlan
import Arc.Model.Ledger.Assessment qualified as Assessment
import Arc.Model.Ledger.Audit qualified as Audit
import Arc.Model.Ledger.Verdict qualified as Verdict
import Arc.Model.Ledger.Verification qualified as Verification
import Arc.Model.State qualified as State
import Generators ( Built(..), build )
import Render
import Scenario

import Data.Either ( isLeft, isRight )
import Data.Set qualified as Set
import Test.QuickCheck


repinChecks :: [Check]
repinChecks =
  [ expectEq "admission/newest: no fallback to older pass"
      (Left (GateWasNotAdmitted gate (EventId 91)))
      (green [passing, notAdmitted])
  , expectTrue "admission/failure: no falsification from an unrun attempt"
      "not-admitted cannot answer a failure"
      ((readGate gate declaration tree here Nothing [notAdmitted]).falsified == Omitted)
  , expectTrue "bypass/integration: recorded bypass satisfies nothing"
      "a bypass must not supply integration success"
      (isLeft (green [bypassed]))
  , expectTrue "bypass/publication: recorded bypass satisfies nothing"
      "a bypass must not supply publication success"
      (isLeft (gateGreenFor Publication gate (Just declaration) tree here Nothing
        [bypassed { Verification.gateEvent = Just Publication }]))
  , expectTrue "bypass/falsification: no failure answered"
      "bypasses contain no execution"
      ((readGate gate declaration tree here Nothing [bypassed]).falsified == Omitted)
  , expectTrue "bypass/history: cannot hide an executed pass"
      "a historical bypass is not a newer execution"
      (isRight (green [passing, bypassed { Verification.event = EventId 91 }]))
  , expectTrue "bypass/history: cannot hide an executed failure"
      "a historical bypass cannot rescue a failure"
      (isLeft (green [passing { Verification.result = GateFail }, bypassed { Verification.event = EventId 91 }]))
  , expectEq "selector/acknowledgment: a different delta runs" RunRequired
      (select (SelectorRequest (delta { GatePlan.paths = Observed ["other"] }) request.declarations))
  , expectEq "selector/acknowledgment: a different gate inventory runs" RunRequired
      (select ((SelectorRequest delta [])))
  , expectTrue "selector/acknowledgment: exact request can reuse"
      "the valid acknowledgment retains the ordinary source proof"
      (reuses (select request))
  , expectTrue "debt/comment-only: leaves ordinary debt owed"
      "a comment judges nothing" (not (discharged commented))
  , expectTrue "debt/ineligible: leaves ordinary debt owed"
      "an ineligible assessment cannot discharge another kind"
      (not (discharged ineligible))
  , expectTrue "debt/negative: independent changes-requested discharges"
      "a negative review supplies the owed judgment" (discharged negative)
  , expectTrue "debt/helper: comment-only does not clear"
      "auditDischarges must agree with debtStanding"
      (all (not . (.clears)) [ d | a <- commented.audits, debt <- commented.debts, Right d <- [auditDischarges commented debt a] ])
  , expectTrue "mutant/admission-as-pass: wrongly authorizes"
      "the predicted fault converts no execution into green"
      (isLeft (green [passing, notAdmitted])
        && isRight (green [passing, notAdmitted { Verification.result = GatePass }]))
  , expectTrue "mutant/bypass-as-execution: wrongly authorizes"
      "the predicted fault treats the retired escape as a run"
      (isLeft (green [bypassed])
        && isRight (green [bypassed { Verification.execution = RanLocally }]))
  , expectTrue "mutant/acknowledgment-ignored: wrongly reuses"
      "the predicted fault discards the reply request and uses the current one"
      (not (reuses (select (SelectorRequest delta [])))
        && reuses (select request))
  , expectTrue "mutant/comment-as-judgment: wrongly discharges"
      "the predicted fault upgrades a comment to approval"
      (not (discharged commented)
        && discharged commented { State.audits = [ a { Audit.kind = Approved } | a <- commented.audits ] })
  , expectTrue "mutant/ineligible-ignored: wrongly discharges"
      "the predicted fault drops the assessment bar"
      (not (discharged ineligible)
        && discharged ineligible { State.audits = [ a { Audit.assessment = Nothing } | a <- ineligible.audits ] })
  , expectEq "confinement/identity: an unconfined pass does not answer a confined declaration"
      (Left (GateDeclarationChanged gate))
      (greenUnder confined [passing])
  , expectEq "confinement/identity: a pass under other roots does not answer"
      (Left (GateDeclarationChanged gate))
      (greenUnder confined [passUnder (Confinement (Set.fromList ["target", "cache"]) True)])
  , expectEq "confinement/identity: a pass under another required flag does not answer"
      (Left (GateDeclarationChanged gate))
      (greenUnder confined [passUnder targetOnly { Declaration.required = False }])
  , expectTrue "confinement/identity: a pass under the same confinement answers"
      "the declared roots and flag are the identity"
      (isRight (greenUnder confined [passUnder targetOnly]))
  , expectTrue "confinement/legacy: evidence without confinement answers an unconfined declaration"
      "an unconfined declaration keeps its default identity"
      (isRight (green [passing]))
  , expectTrue "confinement/identity: a newer unconfined pass hides nothing"
      "a run under another declaration never hides the one in force"
      (isRight (greenUnder confined [passUnder targetOnly, passing { Verification.event = EventId 91 }]))
  , expectEq "debt/ineligible-verdict: an assessed verdict on the shipped patchset clears"
      [StandingDischarged (ReadByVerdict (EventId 901))]
      (standings (assessedVerdict id))
  , expectEq "debt/ineligible-verdict: coverage names the clearing verdict"
      (Just (ReadByVerdict (EventId 901)))
      (coverageAfterIntegration (assessedVerdict id)).read
  , expectEq "debt/ineligible-verdict: unassessed leaves it owed"
      [StandingOwed]
      (standings (assessedVerdict (\v -> v { Verdict.assessment = Nothing })))
  , expectEq "debt/ineligible-verdict: an ineligible assessment leaves it owed"
      [StandingOwed]
      (standings (assessedVerdict (assessing (\a -> a { Assessment.independence = Ineligible }))))
  , expectEq "debt/ineligible-verdict: an unbound assessment leaves it owed"
      [StandingOwed]
      (standings (assessedVerdict (assessing (\a -> a { Assessment.reviewerIdentities = Set.singleton (ModelSlug "somebody-else") }))))
  , expectEq "debt/ineligible-verdict: a read before the debt leaves it owed"
      [StandingOwed]
      (standings (assessedVerdict (\v -> v { Verdict.event = EventId 0 })))
  , expectEq "debt/ineligible-verdict: a comment leaves it owed"
      [StandingOwed]
      (standings (assessedVerdict (\v -> v { Verdict.kind = CommentOnly })))
  , expectEq "debt/ineligible-verdict: changes requested clears"
      [StandingDischarged (ReadByVerdict (EventId 901))]
      (standings (assessedVerdict (\v -> v { Verdict.kind = ChangesRequested })))
  , expectEq "debt/ordinary-verdict: an ineligible assessment leaves ordinary debt owed"
      [StandingOwed]
      (standings (laterVerdict (Just Ineligible)))
  , expectEq "debt/ordinary-verdict: the same read unassessed discharges it"
      [StandingDischarged (ReadByVerdict (EventId 950))]
      (standings (laterVerdict Nothing))
  ]
  <> budgetSuspensionChecks
  <> confinementResolutionChecks
  <> earlierWaiverRetirementChecks
  <> gateTrailerChecks

-- C31, C32, C33
budgetSuspensionChecks :: [Check]
budgetSuspensionChecks =
  [ expectEq "suspension/admit: 24h local suspension is accepted"
      (Right activeSuspension)
      (admitSuspension activeSuspension)
  , expectEq "suspension/admit: duration over 24h is refused"
      (Left SuspensionExceedsMaxDuration)
      (admitSuspension activeSuspension { Budget.endsAt = Instant (1000 + maxMs + 1) })
  , expectEq "suspension/admit: non-positive window is refused"
      (Left SuspensionNonPositiveWindow)
      (admitSuspension activeSuspension { Budget.endsAt = Instant 1000 })
  , expectEq "suspension/admit: empty reason is refused"
      (Left SuspensionEmptyReason)
      (admitSuspension activeSuspension { Budget.reason = "   " })
  , expectEq "suspension/admit: imported suspension is refused"
      (Left SuspensionNotLocal)
      (admitSuspension activeSuspension { Budget.origin = ImportedLedger })
  , expectEq "suspension/integration: active local suspension accepts over-budget pass"
      (BudgetSuspended (SuspensionId 1))
      (judgeGateBudget Integration gate GatePass BudgetDeclarationValid RunOverBudget (Instant 2000) [activeSuspension])
  , expectEq "suspension/integration: ended suspension refuses the same over-budget pass"
      (BudgetRefused BudgetRefusedOverBudget)
      (judgeGateBudget Integration gate GatePass BudgetDeclarationValid RunOverBudget (Instant (1000 + maxMs)) [activeSuspension])
  , expectEq "suspension/resume: resume ends active suspension early"
      (BudgetRefused BudgetRefusedOverBudget)
      (judgeGateBudget Integration gate GatePass BudgetDeclarationValid RunOverBudget (Instant 5000) (resumeSuspensions (Instant 4000) [activeSuspension]))
  , expectEq "suspension/scope: gate-scoped suspension covers only named gates"
      (BudgetRefused BudgetRefusedOverBudget)
      (judgeGateBudget Integration (GateName "lint") GatePass BudgetDeclarationValid RunOverBudget (Instant 2000) [scopedSuspension])
  , expectEq "suspension/scope: empty gate set covers every gate"
      (BudgetSuspended (SuspensionId 1))
      (judgeGateBudget Integration (GateName "lint") GatePass BudgetDeclarationValid RunOverBudget (Instant 2000) [activeSuspension])
  , expectEq "suspension/locality: imported suspension accepts nothing"
      (BudgetRefused BudgetRefusedOverBudget)
      (judgeGateBudget Integration gate GatePass BudgetDeclarationValid RunOverBudget (Instant 2000) [activeSuspension { Budget.origin = ImportedLedger }])
  , expectEq "suspension/strict: failing gate still fails under active suspension"
      (BudgetRefused (BudgetRefusedGateOutcome GateFail))
      (judgeGateBudget Integration gate GateFail BudgetDeclarationValid RunOverBudget (Instant 2000) [activeSuspension])
  , expectEq "suspension/strict: not-admitted gate still refuses under active suspension"
      (BudgetRefused (BudgetRefusedGateOutcome GateNotAdmitted))
      (judgeGateBudget Integration gate GateNotAdmitted BudgetDeclarationValid RunOverBudget (Instant 2000) [activeSuspension])
  , expectEq "suspension/strict: unmeasured pass stays refused under active suspension"
      (BudgetRefused BudgetRefusedUnmeasured)
      (judgeGateBudget Integration gate GatePass BudgetDeclarationValid RunUnmeasured (Instant 2000) [activeSuspension])
  , expectEq "suspension/strict: missing gate budget still blocks under active suspension"
      (BudgetRefused (BudgetRefusedDeclaration (BudgetMissingRequiredGate gate)))
      (judgeGateBudget Integration gate GatePass (BudgetMissingRequiredGate gate) RunOverBudget (Instant 2000) [activeSuspension])
  , expectEq "suspension/strict: excessive total still blocks under active suspension"
      (BudgetRefused (BudgetRefusedDeclaration BudgetExcessiveTotal))
      (judgeGateBudget Integration gate GatePass BudgetExcessiveTotal RunOverBudget (Instant 2000) [activeSuspension])
  , expectEq "suspension/strict: over operator ceiling still blocks under active suspension"
      (BudgetRefused (BudgetRefusedDeclaration BudgetOverOperatorCeiling))
      (judgeGateBudget Integration gate GatePass BudgetOverOperatorCeiling RunOverBudget (Instant 2000) [activeSuspension])
  , expectEq "suspension/publication: publication judges strictly despite active suspension"
      (BudgetRefused BudgetRefusedOverBudget)
      (judgeGateBudget Publication gate GatePass BudgetDeclarationValid RunOverBudget (Instant 2000) [activeSuspension])
  , expectTrue "suspension/seed: run recorded under suspension never becomes a work reference"
      "a suspended pass must not seed a busy-host reference"
      (not (eligibleAsWorkReference GatePass RunWithinBudget True)
        && eligibleAsWorkReference GatePass RunWithinBudget False)
  , expectTrue "suspension/seed: run recorded under suspension never becomes raise evidence"
      "a suspended pass must not justify a budget raise"
      (not (eligibleAsRaiseEvidence GatePass RunOverBudget True)
        && eligibleAsRaiseEvidence GatePass RunOverBudget False)
  , expectTrue "suspension/seed: run recorded under suspension never becomes a base-pass seed"
      "a suspended pass must not establish a cross-change baseline"
      (not (eligibleAsBasePassSeed GatePass RunWithinBudget True)
        && eligibleAsBasePassSeed GatePass RunWithinBudget False)
  , expectEq "budget-table/E1: empty [budget] table enforces"
      True
      (budgetTableEnforces (BudgetTable False False False False False))
  , expectEq "budget-table/E1: landing-only table does not enforce"
      False
      (budgetTableEnforces (BudgetTable True False False False False))
  , expectEq "budget-table/E1: landing with non-default raise enforces"
      True
      (budgetTableEnforces (BudgetTable True False True False False))
  , expectEq "budget-table/E1: landing with non-empty exclude enforces"
      True
      (budgetTableEnforces (BudgetTable True False False False True))
  ]
  where
    DurationMs maxMs = maxSuspensionDurationMs
    activeSuspension = BudgetSuspension
      { suspensionId = SuspensionId 1
      , origin       = LocalLedger
      , actor        = ActorId "lead"
      , reason       = "loaded host during release build"
      , startedAt    = Instant 1000
      , endsAt       = Instant (1000 + maxMs)
      , gates        = Set.empty
      , resumedAt    = Nothing
      }
    scopedSuspension = activeSuspension { Budget.gates = Set.singleton gate }

-- C43 (E2)
confinementResolutionChecks :: [Check]
confinementResolutionChecks =
  [ expectEq "confinement/E2: head adopts confinement when neither destination nor operator declares one"
      (Just headConfine)
      (resolveOpenConfinement Nothing Nothing (Just headConfine))
  , expectEq "confinement/E2: operator roots supplement destination roots"
      (Just (Confinement (Set.fromList ["target", "cache"]) True))
      (resolveOpenConfinement (Just destOptional) (Just opRequired) Nothing)
  , expectEq "confinement/E2: head widening roots are ignored while head required=true enforces"
      (Just (Confinement (Set.singleton "target") True))
      (resolveOpenConfinement (Just destOptional) Nothing (Just headWideningRequired))
  , expectEq "confinement/E2: head narrowing roots are ignored and required=false cannot lift enforcement"
      (Just (Confinement (Set.singleton "target") True))
      (resolveOpenConfinement (Just targetOnly) Nothing (Just headNarrowingOptional))
  ]
  where
    destOptional          = Confinement (Set.singleton "target") False
    opRequired            = Confinement (Set.singleton "cache") True
    headConfine           = Confinement (Set.singleton "build") False
    headWideningRequired  = Confinement (Set.fromList ["target", "outside"]) True
    headNarrowingOptional = Confinement (Set.singleton "sub") False

-- C6, C27
earlierWaiverRetirementChecks :: [Check]
earlierWaiverRetirementChecks =
  [ expectEq "debt/retire: independent approval of shipped ps-02 retires ps-01 ineligible-review waiver"
      [StandingRetired (EventId 5)]
      (standings retiredState)
  , expectEq "debt/retire: coverage selects no earlier-patchset waiver after independent approval"
      Nothing
      (coverageAfterIntegration retiredState).debt
  , expectEq "debt/retire: approval with ineligible assessment does not retire earlier waiver"
      [StandingOwed]
      (standings deniedRetirementState)
  , expectEq "debt/retire: waiver-authorized ps-02 leaves ps-01 waiver unretired"
      [StandingOwed, StandingOwed]
      (standings waivedShippedState)
  , expectEq "debt/retire: external approval of ps-02 does not retire ps-01 waiver"
      [StandingOwed]
      (standings externalShippedState)
  ]
  where
    -- ps-01 has an ineligible-review debt; ps-02 ships under an independent approval
    retiredBase = (build defaultScenario
      { Scenario.patchsets     = 2
      , Scenario.priorVerdicts = [(1, ActorContributor, Approved)]
      , Scenario.debts         = [(1, Just IneligibleReview)]
      , Scenario.reviewer      = Just ActorIndependent
      , Scenario.verdict       = Approved
      }).finalState
    retiredState = retiredBase
    deniedRetirementState = retiredBase
      { State.verdicts =
          [ if v.patchset == PatchsetId 2
              then v { Verdict.assessment = Just (Assessment Ineligible Set.empty Nothing [] Nothing) }
              else v
          | v <- retiredBase.verdicts
          ]
      }
    waivedShippedState = (build defaultScenario
      { Scenario.patchsets     = 2
      , Scenario.priorVerdicts = [(1, ActorContributor, Approved)]
      , Scenario.debts         = [(1, Just IneligibleReview), (2, Just IndependentReview)]
      , Scenario.reviewer      = Nothing
      }).finalState
    externalShippedState = (build defaultScenario
      { Scenario.patchsets       = 2
      , Scenario.priorVerdicts   = [(1, ActorContributor, Approved)]
      , Scenario.debts           = [(1, Just IneligibleReview)]
      , Scenario.reviewer        = Nothing
      , Scenario.externalVerdict = Just ExternalApproved
      , Scenario.policy          = openPolicy
      }).finalState

-- C45
gateTrailerChecks :: [Check]
gateTrailerChecks =
  [ expectEq "gate-trailers/valid: deduplicates up to three single-token witnesses in order"
      (Right (GateTrailers (Just (WitnessNamed ["alpha", "beta", "gamma"])) (Just ChangeSizeInterface)))
      (validateGateTrailers ["alpha", "beta", "alpha", "gamma"] ["interface"])
  , expectEq "gate-trailers/valid: explicit none exemption with reason"
      (Right (GateTrailers (Just (WitnessExempt "docs only")) Nothing))
      (validateGateTrailers ["none (docs only)"] [])
  , expectEq "gate-trailers/refuse: empty witness value"
      (Left WitnessEmpty)
      (validateGateTrailers ["   "] [])
  , expectEq "gate-trailers/refuse: multiline witness value"
      (Left WitnessMultiline)
      (validateGateTrailers ["alpha\nbeta"] [])
  , expectEq "gate-trailers/refuse: multi-token witness name"
      (Left (WitnessNotSingleToken "two words"))
      (validateGateTrailers ["two words"] [])
  , expectEq "gate-trailers/refuse: empty exemption reason"
      (Left WitnessExemptEmptyReason)
      (validateGateTrailers ["none (   )"] [])
  , expectEq "gate-trailers/refuse: bare none without reason"
      (Left WitnessExemptEmptyReason)
      (validateGateTrailers ["none"] [])
  , expectEq "gate-trailers/refuse: mixed exempt and named witnesses"
      (Left WitnessMixedWithExempt)
      (validateGateTrailers ["alpha", "none (skip)"] [])
  , expectEq "gate-trailers/refuse: more than three distinct witnesses"
      (Left (WitnessTooMany ["w1", "w2", "w3", "w4"]))
      (validateGateTrailers ["w1", "w2", "w3", "w4"] [])
  , expectEq "gate-trailers/refuse: invalid Change-size value"
      (Left (ChangeSizeInvalid "large"))
      (validateGateTrailers [] ["large"])
  , expectEq "gate-trailers/identity: changing invariants path invalidates pass at same tree"
      (Left (GateDeclarationChanged gate))
      (gateGreen gate (Just (declWith (Just ".arc/invariants.tsv") Nothing)) tree here Nothing [passing])
  , expectEq "gate-trailers/identity: changing Witness or Change-size trailer invalidates pass at same tree"
      (Left (GateDeclarationChanged gate))
      (gateGreen gate (Just (declWith Nothing (Just interfaceTrailers))) tree here Nothing [passing])
  , expectTrue "gate-trailers/identity: matching invariants and trailers answers"
      "matching gate trailers and invariants must stay green"
      (isRight (gateGreen gate (Just withTrailersDecl) tree here Nothing
        [passing { Verification.shape = declarationShape withTrailersDecl }]))
  ]
  where
    interfaceTrailers = GateTrailers (Just (WitnessNamed ["witness_a"])) (Just ChangeSizeInterface)
    declWith inv tr   = Declaration (DeclarationId "build") "check" 60 Nothing Nothing (Just "select") Nothing inv tr
    withTrailersDecl  = declWith (Just ".arc/invariants.tsv") (Just interfaceTrailers)

repinProperties :: [(String, Property)]
repinProperties =
  [ ("admission: every later matching unrun attempt supersedes a pass",
      forAll (chooseInt (92, 1000000)) $ \event ->
        isLeft (green [passing, notAdmitted { Verification.event = EventId event }]))
  , ("bypass: no raw result supplies a passing gate",
      forAll (elements [GatePass, GateFail, GateNotAdmitted]) $ \result ->
        isLeft (green [bypassed { Verification.result = result }]))
  , ("selector: every different acknowledged path delta requires execution",
      forAll (listOf1 (elements ['a'..'z'])) $ \path ->
        select (SelectorRequest (delta { GatePlan.paths = Observed [path] }) request.declarations) == RunRequired)
  , ("debt: comment-only never discharges ordinary local debt",
      forAll (elements [NothingRead, IndependentReview, ContributorOnly, RepairUnread, MergeResolutionUnread]) $ \kind ->
        not (discharged (auditState CommentOnly AssessmentNone kind)))
  , ("debt: ineligible assessment never discharges ordinary local debt",
      forAll (elements [Approved, ChangesRequested, CommentOnly]) $ \kind ->
        not (discharged (auditState kind AssessmentIneligible IndependentReview)))
  , ("confinement: every different declared confinement leaves the gate unanswered",
      forAll ((,) <$> confinementGen <*> confinementGen) $ \(recorded, declared) ->
        recorded /= declared ==>
          greenUnder declared [passing { Verification.shape = shapeUnder recorded }]
            == Left (GateDeclarationChanged gate))
  , ("debt: a verdict clears ineligible-review only under an eligible, bound assessment",
      forAll ((,,) <$> elements [Eligible, Ineligible] <*> arbitrary <*> elements [Approved, ChangesRequested, CommentOnly]) $ \(independence, describes, kind) ->
        let state = assessedVerdict (assessing (\a -> a
              { Assessment.independence       = independence
              , Assessment.reviewerIdentities = if describes then a.reviewerIdentities else Set.singleton (ModelSlug "somebody-else")
              }) . (\v -> v { Verdict.kind = kind }))
        in discharged state == (independence == Eligible && describes && kind /= CommentOnly))
  , ("suspension: over-24h durations and imported suspensions are always refused",
      forAll ((,) <$> chooseInt (1, 1000000) <*> elements [LocalLedger, ImportedLedger]) $ \(extra, origin) ->
        let DurationMs maxMs = maxSuspensionDurationMs
            overLimit = BudgetSuspension (SuspensionId 1) origin (ActorId "lead") "busy" (Instant 0) (Instant (maxMs + extra)) Set.empty Nothing
        in isLeft (admitSuspension overLimit))
  , ("suspension: never accepts publication, failures, unmeasured runs, or declaration errors",
      forAll ((,,,) <$> elements [Integration, Publication] <*> elements [GatePass, GateFail, GateNotAdmitted] <*> elements [BudgetDeclarationValid, BudgetMissingRequiredGate gate, BudgetExcessiveTotal, BudgetOverOperatorCeiling] <*> elements [RunOverBudget, RunUnmeasured]) $ \(op, result, health, timing) ->
        let suspension = BudgetSuspension (SuspensionId 1) LocalLedger (ActorId "lead") "busy" (Instant 0) (Instant 60000) Set.empty Nothing
            judgment   = judgeGateBudget op gate result health timing (Instant 1000) [suspension]
            maySuspend = op == Integration && result == GatePass && health == BudgetDeclarationValid && timing == RunOverBudget
        in case judgment of
             BudgetSuspended _ -> maySuspend
             _refused          -> not maySuspend)
  , ("confinement: open-change resolution never admits head roots when destination or operator declares a table",
      forAll ((,,) <$> confinementGen <*> confinementGen <*> confinementGen) $ \(dest, oper, hd) ->
        (dest /= Nothing || oper /= Nothing) ==>
          case resolveOpenConfinement dest oper hd of
            Nothing -> False
            Just resolved ->
              resolved.writes == Set.union (maybe Set.empty (.writes) dest) (maybe Set.empty (.writes) oper)
                && resolved.required == any (.required) [ c | Just c <- [dest, oper, hd] ])
  , ("gate-trailers: more than three distinct witnesses always refuse",
      forAll (chooseInt (4, 10)) $ \count ->
        let names = [ "w" <> show n | n <- [1 .. count] ]
        in validateGateTrailers names [] == Left (WitnessTooMany names))
  ]

gate :: GateName
gate = GateName "build"

declaration :: Declaration
declaration = Declaration (DeclarationId "build") "check" 60 Nothing Nothing (Just "select") Nothing Nothing Nothing

tree :: TreeId
tree = TreeId "source"

here :: Observed EnvironmentId
here = Omitted

passing, notAdmitted, bypassed :: Verification
passing = Verification (EventId 90) gate declaration.declarationId (declarationShape declaration)
  (Revision "head") tree GatePass RanLocally Nothing True Nothing (Observed CleanWorktree) Nothing
notAdmitted = passing
  { Verification.event   = EventId 91
  , Verification.result  = GateNotAdmitted
  , Verification.answers = Just (FailureLabel "unobserved")
  }
bypassed = passing
  { Verification.execution = Bypassed
  , Verification.answers   = Just (FailureLabel "unobserved")
  }

green :: [Verification] -> Either GateRefusal GateReading
green = gateGreen gate (Just declaration) tree here Nothing

targetOnly :: Confinement
targetOnly = Confinement (Set.singleton "target") True

confined :: Maybe Confinement
confined = Just targetOnly

confinementGen :: Gen (Maybe Confinement)
confinementGen = oneof
  [ pure Nothing
  , Just <$> (Confinement <$> (Set.fromList <$> sublistOf ["target", "cache", "/dev/shm"]) <*> arbitrary)
  ]

passUnder :: Confinement -> Verification
passUnder confinement = passing { Verification.shape = shapeUnder (Just confinement) }

-- | The test declaration's shape, run under the given confinement.
shapeUnder :: Maybe Confinement -> DeclarationShape
shapeUnder confinement = DeclarationShape "check" 60 confinement Nothing Nothing

greenUnder :: Maybe Confinement -> [Verification] -> Either GateRefusal GateReading
greenUnder confinement = gateGreen gate (Just (Declaration (DeclarationId "build") "check" 60 Nothing Nothing (Just "select") confinement Nothing Nothing)) tree here Nothing

delta :: GateDelta
delta = GateDelta (Observed tree) (TreeId "target") (Observed ["README.md"])

request :: SelectorRequest
request = SelectorRequest delta [(gate, declaration)]

select :: SelectorRequest -> GatePlan
select acknowledged = planGate Integration [(gate, declaration)] gate declaration delta here [passing]
  (SelectionComplete acknowledged Set.empty)

reuses :: GatePlan -> Bool
reuses (ReusePassing _) = True
reuses RunRequired      = False

auditState :: VerdictKind -> AssessmentMode -> DebtKind -> ChangeState
auditState verdict assessment kind = (build defaultScenario
  { Scenario.reviewer        = Nothing
  , Scenario.debts           = [(1, Just kind)]
  , Scenario.audit           = Just (verdict, True)
  , Scenario.auditModel      = PickDistinct
  , Scenario.auditAssessment = assessment
  }).finalState

commented, negative, ineligible :: ChangeState
commented  = auditState CommentOnly AssessmentNone       IndependentReview
negative   = auditState ChangesRequested AssessmentNone  IndependentReview
ineligible = auditState Approved AssessmentIneligible     IndependentReview

-- | The ineligible-review history whose clearing audit is replaced by a
-- verdict on the shipped patchset from the same reader, under the same
-- assessment, altered before it is recorded.
assessedVerdict :: (Verdict -> Verdict) -> ChangeState
assessedVerdict alter = case (audited.audits, latestIntegration audited) of
  (audit : _, Just record) -> audited
    { State.audits   = []
    , State.verdicts = audited.verdicts <> [alter (readerVerdict audit record.patchset)]
    }
  _unbuilt -> audited
  where
    audited = (build defaultScenario
      { Scenario.debts           = [(1, Just IneligibleReview)]
      , Scenario.policy          = openPolicy
      , Scenario.audit           = Just (Approved, True)
      , Scenario.auditModel      = PickDistinct
      , Scenario.auditAssessment = AssessmentBound
      , Scenario.implementers    = True
      , Scenario.ledgerModel     = True
      }).finalState

-- | An integrated change waived for independent review, then read by an
-- independent verdict on the shipped patchset under the given assessment.
laterVerdict :: Maybe Independence -> ChangeState
laterVerdict independence = case (waived.patchsets, latestIntegration waived) of
  (_ : _, Just record) -> waived
    { State.verdicts = waived.verdicts <> [verdict record.patchset] }
  _unbuilt -> waived
  where
    waived = (build defaultScenario { Scenario.reviewer = Nothing, Scenario.debts = [(1, Just IndependentReview)] }).finalState
    verdict patchset = Verdict
      { event       = EventId 950
      , patchset    = patchset
      , kind        = Approved
      , actor       = ActorId "reviewer"
      , onBehalfOf  = Nothing
      , assumed     = False
      , provisional = Nothing
      , relation    = Corroborates
      , supersedes  = Nothing
      , model       = Nothing
      , assessment  = (\i -> Assessment i Set.empty Nothing [] Nothing) <$> independence
      }

readerVerdict :: Audit -> PatchsetId -> Verdict
readerVerdict audit patchset = Verdict
  { event       = audit.event
  , patchset    = patchset
  , kind        = audit.kind
  , actor       = audit.actor
  , onBehalfOf  = Nothing
  , assumed     = audit.assumed
  , provisional = Nothing
  , relation    = Corroborates
  , supersedes  = Nothing
  , model       = audit.model
  , assessment  = audit.assessment
  }

assessing :: (Assessment -> Assessment) -> Verdict -> Verdict
assessing alter verdict = verdict { Verdict.assessment = alter <$> verdict.assessment }

standings :: ChangeState -> [DebtStanding]
standings state = map (debtStanding state) state.debts

discharged :: ChangeState -> Bool
discharged state = any answered state.debts
  where
    answered debt = case debtStanding state debt of
      StandingDischarged _ -> True
      _owed                -> False
