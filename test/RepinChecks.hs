-- | C22, C29, C35 and C36: public claims and faults that must violate them.
module RepinChecks ( repinChecks, repinProperties ) where

import Arc.Model
import Arc.Model.GatePlan qualified as GatePlan
import Arc.Model.Ledger.Audit qualified as Audit
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
  ]

gate :: GateName
gate = GateName "build"

declaration :: Declaration
declaration = Declaration (DeclarationId "build") "check" 60 Nothing Nothing (Just "select")

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

discharged :: ChangeState -> Bool
discharged state = any answered state.debts
  where
    answered debt = case debtStanding state debt of
      StandingDischarged _ -> True
      _owed                -> False
