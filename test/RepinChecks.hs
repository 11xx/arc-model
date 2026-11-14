-- | C22, C29, C35, C36 and C43: public claims and faults that must violate them.
module RepinChecks ( repinChecks, repinProperties ) where

import Arc.Model
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
  ]

gate :: GateName
gate = GateName "build"

declaration :: Declaration
declaration = Declaration (DeclarationId "build") "check" 60 Nothing Nothing (Just "select") Nothing

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
shapeUnder = DeclarationShape "check" 60

greenUnder :: Maybe Confinement -> [Verification] -> Either GateRefusal GateReading
greenUnder confinement = gateGreen gate (Just (Declaration (DeclarationId "build") "check" 60 Nothing Nothing (Just "select") confinement)) tree here Nothing

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
