{- | Unit fixtures for the debt clauses: the declared-only @ineligible-review@
kind (C21), its audit-only discharge and the reviewing model as a second
identity (C4, C22), a debt's standing (C27), and planning a declaration
(C28).
-}
module DebtFixtures ( debtFixtureChecks ) where

import Arc.Model
import Arc.Model.Ledger.Patchset qualified as Patchset
import Arc.Model.State qualified as State
import Generators
import Render
import Scenario qualified

import Data.Set qualified as Set


debtFixtureChecks :: [Check]
debtFixtureChecks = concat
  [ ineligibleDeclaration
  , equivalentDeclarations
  , ineligibleDischarge
  , assessmentBindings
  , authorsFromTheRecord
  , reviewingModelOfVerdicts
  , reviewingModelOfAudits
  , debtStandings
  , plannedDeclarations
  , expectedBases
  ]

-- | A scenario that integrates under an independent approval, with an
-- @ineligible-review@ debt declared beside it.
ineligibleScenario :: Scenario
ineligibleScenario = defaultScenario
  { Scenario.debts  = [(1, Just IneligibleReview)]
  , Scenario.policy = openPolicy
  }

withAudit :: ModelPick -> AssessmentMode -> Scenario
withAudit model mode = ineligibleScenario
  { Scenario.audit           = Just (Approved, True)
  , Scenario.auditModel      = model
  , Scenario.auditAssessment = mode
  , Scenario.implementers    = True
  }

-- | Whether the read the shipped change owes is answered after its audit.
answered :: Scenario -> Bool
answered scenario = coverage.read /= Nothing
  where
    coverage = coverageAfterIntegration (build scenario).finalState

-- | A declaration as the caller of @arc debt@ makes it, on patchset 1.
asking :: Maybe DebtKind -> String -> ActorId -> Maybe EventId -> Maybe Why -> DebtRequest
asking kind reason actor named why = DebtRequest
  { patchset = Just (PatchsetId 1)
  , kind     = kind
  , reason   = reason
  , actor    = actor
  , read     = named
  , why      = why
  }

-- | An @ineligible-review@ declaration, as the qualifier flags make it unless
-- the assessment says otherwise.
whyWith :: Independence -> [Qualifier] -> AssessmentSource -> Why
whyWith independence qualifiers source = Why
  { independence = independence
  , qualifiers   = Set.fromList qualifiers
  , source       = source
  , routeVersion = Just (RouteVersion "rv1")
  }

whyDeclared :: Why
whyDeclared = whyWith Ineligible [SameModel, BelowFloor] DeclaredByHand

-- | The declaration of a kind, with the reason the scenarios' debts carry.
plainRequest :: Maybe DebtKind -> DebtRequest
plainRequest kind = asking kind "declared coverage" authorActor Nothing Nothing

-- | The declaration of an @ineligible-review@ debt with this reason.
ineligibleAsking :: Maybe EventId -> Maybe Why -> DebtRequest
ineligibleAsking = asking (Just IneligibleReview) "owed" authorActor

-- | The ledger of an approved patchset, where a debt is declared.
approvedState :: ChangeState
approvedState = (build defaultScenario).state

-- C21
ineligibleDeclaration :: [Check]
ineligibleDeclaration =
  [ expectEq "fixture/ineligible: records the latest verdict, why and the route version"
      (Right (Just IneligibleRead { read = EventId 2, qualifiers = Set.fromList [SameModel, BelowFloor], source = DeclaredByHand, routeVersion = Just (RouteVersion "rv1") }))
      ((\debt -> debt.ineligible) . written <$> declareDebt approvedState declaredWhy)
  , expectEq "fixture/ineligible: names the kind the caller declared"
      (Right (Just IneligibleReview))
      ((\debt -> debt.declaredKind) . written <$> declareDebt approvedState declaredWhy)
  , expectEq "fixture/ineligible: a named verdict is the read"
      (Right (Just (EventId 2)))
      (fmap (fmap (.read) . (.ineligible) . written) (declareDebt approvedState (ineligibleAsking (Just (EventId 2)) (Just whyDeclared))))
  , expectEq "fixture/ineligible: an assessment file reads as assessed"
      (Right (Just Assessed))
      (fmap (fmap (.source) . (.ineligible) . written) (declareDebt approvedState (ineligibleAsking Nothing (Just (whyWith Ineligible [SameModel, BelowFloor] Assessed)))))
  , expectEq "fixture/ineligible: no verdict on the patchset is refused"
      (Left NoVerdictToRead)
      (declareDebt (build defaultScenario { Scenario.reviewer = Nothing }).state declaredWhy)
  , expectEq "fixture/ineligible: a verdict of another patchset is no read"
      (Left NoVerdictToRead)
      (declareDebt (build defaultScenario { Scenario.patchsets = 2, Scenario.verdictOnFirst = True }).state (secondPatchset declaredWhy))
  , expectEq "fixture/ineligible: a named event that is no verdict is refused"
      (Left (ReadNotAVerdict (EventId 1)))
      (declareDebt approvedState (ineligibleAsking (Just (EventId 1)) (Just whyDeclared)))
  , expectEq "fixture/ineligible: a read is named only for this kind"
      (Left ReadOnOtherKind)
      (declareDebt approvedState (asking (Just IndependentReview) "owed" authorActor (Just (EventId 2)) Nothing))
  , expectEq "fixture/ineligible: a read is named only for this kind, even with no kind declared"
      (Left ReadOnOtherKind)
      (declareDebt approvedState (asking Nothing "owed" authorActor (Just (EventId 2)) Nothing))
  , expectEq "fixture/ineligible: an eligible assessment records no debt"
      (Left EligibleAssessment)
      (declareDebt approvedState (ineligibleAsking Nothing (Just (whyWith Eligible [SameModel] DeclaredByHand))))
  , expectEq "fixture/ineligible: neither an assessment nor a qualifier is refused"
      (Left NoReasonForIneligible)
      (declareDebt approvedState (ineligibleAsking Nothing Nothing))
  , expectEq "fixture/ineligible: no qualifier is refused"
      (Left NoReasonForIneligible)
      (declareDebt approvedState (ineligibleAsking Nothing (Just (whyWith Ineligible [] DeclaredByHand))))
  , expectEq "fixture/ineligible: the production record keeps the range's implementers"
      (Right (Just (Set.singleton (ModelSlug "impl-model"))))
      ((\debt -> debt.trailerImplementers) . written <$> declareDebt (build defaultScenario { Scenario.implementers = True }).state declaredWhy)
  , expectEq "fixture/ineligible: a range with none records an empty list"
      (Right (Just Set.empty))
      ((\debt -> debt.trailerImplementers) . written <$> declareDebt approvedState declaredWhy)
  , expectEq "fixture/ineligible: a range that did not read records no list"
      (Right Nothing)
      ((\debt -> debt.trailerImplementers) . written <$> declareDebt unreadRange declaredWhy)
  , expectTrue "fixture/ineligible: the ledger never derives the kind" "a derived kind must never be ineligible-review" derivedNever
  ]
  where
    declaredWhy = ineligibleAsking Nothing (Just whyDeclared)
    secondPatchset (DebtRequest _ kind reason actor named why) = DebtRequest (Just (PatchsetId 2)) kind reason actor named why
    derivedNever = and
      [ debtKindFor state (Debt (DebtId 1) (EventId 90) (Just (PatchsetId 1)) Nothing "owed" authorActor Nothing Nothing) /= IneligibleReview
      | scenario <- [ defaultScenario, defaultScenario { Scenario.reviewer = Nothing }, defaultScenario { Scenario.reviewer = Just ActorContributor }, defaultScenario { Scenario.patchsets = 2, Scenario.verdictOnFirst = True } ]
      , let state = (build scenario).state
      ]
    unreadRange = unread approvedState

-- | The state with no patchset's range readable.
unread :: ChangeState -> ChangeState
unread state = state { State.patchsets = [ patchset { Patchset.implementers = Nothing } | patchset <- state.patchsets ] }

written :: DebtOutcome -> Debt
written = \case
  DebtWritten debt -> debt
  DebtReused debt  -> debt

-- C28
equivalentDeclarations :: [Check]
equivalentDeclarations =
  [ expectTrue "fixture/reuse: an equivalent declaration records nothing" "the same reason, kind and declarer must find the debt in force" (case declareDebt withDebt same of Right (DebtReused held) -> held.debtId == DebtId 1; _ -> False)
  , expectTrue "fixture/reuse: another reason is a new debt" "a different reason must be written" (case declareDebt withDebt (asking (Just IndependentReview) "another" authorActor Nothing Nothing) of Right (DebtWritten _) -> True; _ -> False)
  , expectTrue "fixture/reuse: another declarer is a new debt" "a different declarer must be written" (case declareDebt withDebt (asking (Just IndependentReview) "declared coverage" otherActor Nothing Nothing) of Right (DebtWritten _) -> True; _ -> False)
  , expectTrue "fixture/reuse: another kind is a new debt" "a different kind must be written" (case declareDebt withDebt (asking (Just ContributorOnly) "declared coverage" authorActor Nothing Nothing) of Right (DebtWritten _) -> True; _ -> False)
  ]
  where
    built    = build defaultScenario { Scenario.debts = [(1, Just IndependentReview)] }
    withDebt = built.state
    same     = plainRequest (Just IndependentReview)

-- C22
ineligibleDischarge :: [Check]
ineligibleDischarge =
  [ expectTrue "fixture/ineligible-discharge: an independent approval beside the debt does not clear it" "a verdict never clears an ineligible-review debt" (not (answered ineligibleScenario))
  , expectTrue "fixture/ineligible-discharge: the debt stays the one the review is owed on" "the debt must remain the selected obligation" (fmap (const ()) (coverageAfterIntegration (build ineligibleScenario).finalState).debt == Just ())
  , expectTrue "fixture/ineligible-discharge: an audit without an assessment leaves it open" "an unassessed audit must not clear" (not (answered (withAudit PickDistinct AssessmentNone)))
  , expectTrue "fixture/ineligible-discharge: an eligible, bound audit clears it" "a bound, eligible audit must clear" (answered (withAudit PickDistinct AssessmentBound))
  , expectTrue "fixture/ineligible-discharge: a negative audit clears it too" "fulfilment is not approval" (answered (withAudit PickDistinct AssessmentBound) { Scenario.audit = Just (ChangesRequested, True) })
  , expectTrue "fixture/ineligible-discharge: an ineligible assessment leaves it open" "an ineligible assessment must not clear" (not (answered (withAudit PickDistinct AssessmentIneligible)))
  , expectTrue "fixture/ineligible-discharge: an assessment of another model leaves it open" "a mismatched model must not clear" (not (answered (withAudit PickDistinct AssessmentOtherModel)))
  , expectTrue "fixture/ineligible-discharge: an assessment of another effort leaves it open" "a mismatched effort must not clear" (not (answered (withAudit PickDistinct AssessmentOtherEffort)))
  , expectTrue "fixture/ineligible-discharge: an assessment listing no identity leaves it open" "unstated identities must not clear" (not (answered (withAudit PickDistinct AssessmentNoIdentities)))
  , expectTrue "fixture/ineligible-discharge: an audit that recorded no model leaves it open" "an unrecorded model must not clear" (not (answered (withAudit PickUnrecorded AssessmentBound)))
  , expectTrue "fixture/ineligible-discharge: authors that omit an implementer leave it open" "uncovered authors must not clear" (not (answered (withAudit PickDistinct AssessmentAuthorsOmitted)))
  , expectTrue "fixture/ineligible-discharge: authors with no implementer to cover clear it" "an empty range asks nothing of the authors" (answered (withAudit PickDistinct AssessmentAuthorsOmitted) { Scenario.implementers = False })
  , expectTrue "fixture/ineligible-discharge: a contributor's audit leaves it open" "the auditor must be independent" (not (answered (withAudit PickDistinct AssessmentBound) { Scenario.audit = Just (Approved, False) }))
  , expectTrue "fixture/ineligible-discharge: an audit under the implementer's model leaves it open" "the auditor's model must not be an implementer's" (not (answered (withAudit PickImplementer AssessmentBound)))
  , expectTrue "fixture/ineligible-discharge: another kind ignores the assessment" "an independent-review debt is answered without one" (answered (withAudit PickDistinct AssessmentNone) { Scenario.debts = [(1, Just IndependentReview)] })
  ]

-- C22
assessmentBindings :: [Check]
assessmentBindings =
  [ expectEq "fixture/binding: bound"                 (Just Bound)                                         (bindingOf PickDistinct AssessmentBound)
  , expectEq "fixture/binding: model-unrecorded"      (Just ModelUnrecorded)                               (bindingOf PickUnrecorded AssessmentBound)
  , expectEq "fixture/binding: identities-unstated"   (Just IdentitiesUnstated)                            (bindingOf PickDistinct AssessmentNoIdentities)
  , expectEq "fixture/binding: model-mismatch"        (Just ModelMismatch)                                 (bindingOf PickDistinct AssessmentOtherModel)
  , expectEq "fixture/binding: effort-mismatch"       (Just EffortMismatch)                                (bindingOf PickDistinct AssessmentOtherEffort)
  , expectEq "fixture/binding: authors-uncovered names the omitted models" (Just (AuthorsUncovered (Set.singleton (ModelSlug "impl-model")))) (bindingOf' PickDistinct AssessmentAuthorsOmitted)
  , expectEq "fixture/binding: authors-unread"        (Just AuthorsUnread)                                 (unreadBinding PickDistinct AssessmentBound)
  , expectEq "fixture/binding: the auditor is judged before the work" (Just ModelMismatch)                 (bindingOf' PickDistinct AssessmentOtherModel)
  , expectEq "fixture/binding: no assessment has no binding" Nothing                                       (bindingOf PickDistinct AssessmentNone)
  ]
  where
    bindingOf model mode = bindingFor (withAudit model mode) { Scenario.implementers = False } id
    bindingOf' model mode = bindingFor (withAudit model mode) id
    unreadBinding model mode = bindingFor (withAudit model mode) unreadRange
    unreadRange state = (unread state) { State.debts = [ debt { trailerImplementers = Nothing } | debt <- state.debts ] }

-- | The binding an audit of the scenario records against its ineligible
-- debt, with the history optionally altered before the audit is read.
bindingFor :: Scenario -> (ChangeState -> ChangeState) -> Maybe AssessmentBinding
bindingFor scenario alter = do
  let state = alter (build scenario).finalState
  debt  <- firstOf state.debts
  audit <- firstOf state.audits
  assessment <- audit.assessment
  pure (assessmentBinding state debt audit assessment)

firstOf :: [a] -> Maybe a
firstOf = \case
  item : _ -> Just item
  []       -> Nothing

-- C22
-- | An audit's authors are read from the debt's production record before the
-- range is read again.
authorsFromTheRecord :: [Check]
authorsFromTheRecord =
  [ expectEq "fixture/authors: the production record answers when the range does not read" (Just Bound)
      (bindingFor (withAudit PickDistinct AssessmentBound) (\state -> (unread state)))
  , expectEq "fixture/authors: the range answers when the record kept none" (Just (AuthorsUncovered (Set.singleton (ModelSlug "impl-model"))))
      (bindingFor (withAudit PickDistinct AssessmentAuthorsOmitted) (\state -> state { State.debts = [ debt { trailerImplementers = Nothing } | debt <- state.debts ] }))
  , expectEq "fixture/authors: an empty record asks nothing even where the range is unread" (Just Bound)
      (bindingFor (withAudit PickDistinct AssessmentAuthorsOmitted) (\state -> (unread state) { State.debts = [ debt { trailerImplementers = Just Set.empty } | debt <- state.debts ] }))
  ]

-- C4
reviewingModelOfVerdicts :: [Check]
reviewingModelOfVerdicts =
  [ expectRefusedWith "fixture/model: an approval under an implementer's model is a self-approval" "self-approval" (decisionOf dangerScenario)
  , expectRefusedWith "fixture/model: the effort is dropped" "self-approval" (decisionOf dangerScenario { Scenario.reviewerModel = PickImplementerOtherEffort })
  , expectPermittedWith "fixture/model: another model is independent" (AuthorizedByVerdict (EventId 2)) (decisionOf dangerScenario { Scenario.reviewerModel = PickDistinct })
  , expectPermittedWith "fixture/model: no recorded model names nobody" (AuthorizedByVerdict (EventId 2)) (decisionOf dangerScenario { Scenario.reviewerModel = PickUnrecorded })
  , expectPermittedWith "fixture/model: no implementer names nobody" (AuthorizedByVerdict (EventId 2)) (decisionOf dangerScenario { Scenario.implementers = False })
  , expectPermittedWith "fixture/model: where self-approval is not forbidden it counts" (AuthorizedByVerdict (EventId 2)) (decisionOf dangerScenario { Scenario.policy = dangerPermittingSelfPolicy })
  , expectPermittedWith "fixture/model: a waiver rescues the rejected approval" (AuthorizedByVerdictUnderWaiver (EventId 3) (DebtId 1)) (decisionOf dangerScenario { Scenario.debts = [(1, Nothing)] })
  , expectPermittedWith "fixture/model: a range that cannot be read names nobody" (AuthorizedByVerdict (EventId 2)) unreadDecision
  , expectTrue "fixture/model: a refusal is never refused for its model" "a changes-requested verdict stands as a refusal" (case decisionOf dangerScenario { Scenario.verdict = ChangesRequested } of Refused refusal -> refusalTag refusal == "verdict-stands"; _ -> False)
  ]
  where
    dangerScenario = defaultScenario { Scenario.implementers = True, Scenario.reviewerModel = PickImplementer }
    decisionOf scenario = (build scenario).decision
    unreadDecision = let built = build dangerScenario in decide built.observation (unread built.state)

-- C4, C22
reviewingModelOfAudits :: [Check]
reviewingModelOfAudits =
  [ expectEq "fixture/audit-model: an approving audit under an implementer's model is refused where self-approval is forbidden" (Left AuditAuditorNotIndependent) (admitAudit dangerPolicy closed (auditBy (Just implementerCoordinate) Approved))
  , expectEq "fixture/audit-model: the effort is dropped" (Left AuditAuditorNotIndependent) (admitAudit dangerPolicy closed (auditBy (Just (modelCoordinate "impl-model#low")) Approved))
  , expectEq "fixture/audit-model: elsewhere it is recorded" (Right ()) (admitAudit openPolicy closed (auditBy (Just implementerCoordinate) Approved))
  , expectEq "fixture/audit-model: a changes-requested audit is open to anyone" (Right ()) (admitAudit dangerPolicy closed (auditBy (Just implementerCoordinate) ChangesRequested))
  , expectEq "fixture/audit-model: another model is recorded" (Right ()) (admitAudit dangerPolicy closed (auditBy (Just (modelCoordinate "other-model#high")) Approved))
  , expectEq "fixture/audit-model: an audit that recorded no model is recorded" (Right ()) (admitAudit dangerPolicy closed (auditBy Nothing Approved))
  , expectTrue "fixture/audit-model: it is no independent read" "an audit under an implementer's model must not count as a read" (not (auditIsIndependent closed (auditBy (Just implementerCoordinate) Approved)))
  , expectTrue "fixture/audit-model: another model is an independent read" "an audit under another model counts" (auditIsIndependent closed (auditBy (Just (modelCoordinate "other-model#high")) Approved))
  , expectTrue "fixture/audit-model: a range that cannot be read names nobody" "an unreadable range must not match" (auditIsIndependent (unread closed) (auditBy (Just implementerCoordinate) Approved))
  ]
  where
    closed = (build defaultScenario { Scenario.implementers = True, Scenario.audit = Just (Approved, True), Scenario.auditModel = PickDistinct }).finalState
    implementerCoordinate = modelCoordinate "impl-model#high"
    auditBy model kind = Audit
      { event      = EventId 950
      , revision   = Revision "rev1"
      , kind       = kind
      , actor      = otherActor
      , assumed    = False
      , findings   = []
      , model      = model
      , assessment = Nothing
      }

-- C27
debtStandings :: [Check]
debtStandings =
  [ expectEq "fixture/standing: declared before the change integrates" (Just StandingDeclared) (standingOf (build waivedOpen).state)
  , expectEq "fixture/standing: owed after it integrates" (Just StandingOwed) (standingOf (build waived).finalState)
  , expectEq "fixture/standing: discharged by an independent audit" (Just (StandingDischarged (ReadByAudit (EventId 901)))) (standingOf (build audited).finalState)
  , expectEq "fixture/standing: an audit by a contributor leaves it owed" (Just StandingOwed) (standingOf (build audited { Scenario.audit = Just (Approved, False) }).finalState)
  , expectEq "fixture/standing: an ineligible-review debt is owed beside an approval" (Just StandingOwed) (standingOf (build ineligibleScenario).finalState)
  , expectEq "fixture/standing: an ineligible-review debt is declared before integration" (Just StandingDeclared) (standingOf (build ineligibleScenario { Scenario.gateMode = EvidenceFailing }).state)
  , expectEq "fixture/standing: an eligible, bound audit discharges it" (Just (StandingDischarged (ReadByAudit (EventId 901)))) (standingOf (build (withAudit PickDistinct AssessmentBound)).finalState)
  , expectEq "fixture/standing: an unbound audit leaves it owed" (Just StandingOwed) (standingOf (build (withAudit PickDistinct AssessmentOtherModel)).finalState)
  ]
  where
    waivedOpen = defaultScenario { Scenario.reviewer = Nothing, Scenario.debts = [(1, Nothing)], Scenario.gateMode = EvidenceFailing }
    waived     = defaultScenario { Scenario.reviewer = Nothing, Scenario.debts = [(1, Nothing)] }
    audited    = waived { Scenario.audit = Just (Approved, True) }
    standingOf state = debtStanding state <$> firstOf state.debts

-- C28
plannedDeclarations :: [Check]
plannedDeclarations =
  [ expectTrue "fixture/plan: an unreviewed change would integrate on its declared debt" "the plan must read the change as declared" (case planOf unreviewed (Just IndependentReview) of Right plan -> isPermitted (decisionOfPlanned plan); Left _ -> False)
  , expectEq "fixture/plan: it says it would declare" (Right WouldDeclare) (dispositionOf <$> planOf unreviewed (Just IndependentReview))
  , expectTrue "fixture/plan: and writes nothing" "the plan must not change the ledger" (unreviewedBuilt.state.debts == [])
  , expectEq "fixture/plan: a debt the change carries reads as already declared" (Right (AlreadyDeclared (DebtId 1))) (dispositionOf <$> planIn waivedBuilt.observation waivedBuilt.state (plainRequest (Just IndependentReview)))
  , expectEq "fixture/plan: a declaration the execution would refuse is refused" (Left NoVerdictToRead) (dispositionOf <$> planOf unreviewed (Just IneligibleReview))
  , expectEq "fixture/plan: an eligible assessment is refused" (Left EligibleAssessment) (dispositionOf <$> planOf approvedBuilt (Just IneligibleReview))
  , expectRefusedWith "fixture/plan: it invents no approval beside a refusal" "verdict-stands" (decisionOfPlan refusingBuilt)
  , expectRefusedWith "fixture/plan: a debt beside an approval rejected for its author is a waiver" "gates" (decisionOfPlan gatesFailing)
  , expectEq "fixture/plan: an ineligible-review debt is planned on the verdict it names" (Right (Just (EventId 2))) (fmap (fmap (.read) . (.ineligible) . debtOf) (planIn approvedBuilt.observation approvedBuilt.state ineligibleRequest))
  ]
  where
    unreviewedBuilt = build defaultScenario { Scenario.reviewer = Nothing }
    unreviewed      = unreviewedBuilt
    waivedBuilt     = build defaultScenario { Scenario.reviewer = Nothing, Scenario.debts = [(1, Just IndependentReview)] }
    approvedBuilt   = build defaultScenario
    refusingBuilt   = build defaultScenario { Scenario.verdict = ChangesRequested }
    gatesFailing    = build defaultScenario { Scenario.reviewer = Nothing, Scenario.gateMode = EvidenceFailing }
    ineligibleRequest = declaredWhyRequest
    declaredWhyRequest = ineligibleAsking Nothing (Just whyDeclared)
    dispositionOf (DebtPlan disposition _ _) = disposition
    debtOf (DebtPlan _ debt _) = debt
    planOf built kind = planIn built.observation built.state (case kind of
      Just IneligibleReview -> ineligibleAsking Nothing (Just (whyWith Eligible [SameModel] DeclaredByHand))
      _other                -> plainRequest kind)
    planIn observations state = planDeclaring observations state
    decisionOfPlan built = case planDeclaring built.observation built.state (plainRequest (Just IndependentReview)) of
      Right plan -> decisionOfPlanned plan
      Left _     -> Refused RefusedNoApproval

decisionOfPlanned :: DebtPlan -> Decision
decisionOfPlanned (DebtPlan _ _ decision) = decision

-- C20, C28
expectedBases :: [Check]
expectedBases =
  [ expectTrue "fixture/expect-basis: the event the execution writes is not a move" "executing the plan's own declaration must proceed" (either (const False) (const True) (executeDeclaring built.observation built.state declaration planned))
  , expectEq "fixture/expect-basis: a debt another actor declared meanwhile is a move"
      (Left (RefusedBasisMoved [MovedDebts [DebtId 2] [DebtId 1, DebtId 2]]))
      (executeDeclaring built.observation (withDebtBy otherActor) declaration planned)
  , expectEq "fixture/expect-basis: an existing declaration the execution reuses is a move"
      (Left (RefusedBasisMoved [movedAuthorization 0 1, MovedDebts [DebtId 0] [DebtId 1]]))
      (executeDeclaring built.observation (withDebtBy authorActor) declaration planned)
  , expectTrue "fixture/expect-basis: a debt the plan never saw is a move beside an approval" "a debt declared after a plan without one must be reported" (case execute approved.observation withUnusedDebt approvedPlan of Left (RefusedBasisMoved moved) -> any isDebtMove moved; _ -> False)
  , expectTrue "fixture/expect-basis: no new debt, no move" "an unchanged history must execute" (either (const False) (const True) (execute approved.observation approved.state approvedPlan))
  ]
  where
    built       = build defaultScenario { Scenario.reviewer = Nothing }
    declaration = plainRequest (Just IndependentReview)
    planned     = case planDeclaring built.observation built.state declaration of
      Right plan -> decisionOfPlanned plan
      Left _     -> Refused RefusedNoApproval
    movedAuthorization before after = MovedAuthorization (AuthorizedByWaiver (DebtId before)) (AuthorizedByWaiver (DebtId after))
    -- the debt as the ledger holds it, declared with the same reason
    withDebtBy actor = built.state { State.debts = built.state.debts <> [ Debt (DebtId 1) (EventId 70) (Just (PatchsetId 1)) (Just IndependentReview) "declared coverage" actor Nothing (Just Set.empty) ] }
    approved     = build defaultScenario
    approvedPlan = approved.decision
    withUnusedDebt = approved.state { State.debts = [ Debt (DebtId 4) (EventId 71) (Just (PatchsetId 1)) Nothing "later" otherActor Nothing Nothing ] }
    isDebtMove = \case
      MovedDebts _ _ -> True
      _other         -> False
