{- | Unit fixtures. Each one anchors a piece of intended meaning with an
exact expected answer, including the answer's shape: which refusal, which
authorization, which gate reading.
-}
module Fixtures ( fixtureChecks ) where

import Arc.Model
import Arc.Model.Ledger.Audit qualified as Audit
import Generators
import Mutants ( Behaviour(..), Mutant(..), allMutants )
import Render
import Scenario qualified

import Data.Maybe ( listToMaybe )


fixtureChecks :: [Check]
fixtureChecks = concat
  [ waiverExpiry
  , debtBesideRefusal
  , underDebtThenNegativeAudit
  , repairFollowedByDeeperReview
  , unknownCoverage
  , equalTreeDifferentContributors
  , retainedAcrossEpisodeExpiry
  , debtAuthorizedNothing
  , staleAndMovedBases
  , permissionIsNotEffect
  , auditRefusals
  , provisionalGates
  , demonstratedCounterexample
  ]

-- | A debt declared on ps-01 waives ps-01 only. A second patchset is a new
-- obligation, not a re-use.
waiverExpiry :: [Check]
waiverExpiry =
  [ expectPermittedWith "fixture/waiver-expiry: ps-01 is waived" (AuthorizedByWaiver (DebtId 1)) (build scenario).decision
  , expectRefusedWith "fixture/waiver-expiry: ps-02 is not waived" "no-approval" (build scenario { Scenario.patchsets = 2 }).decision
  ]
  where
    scenario = defaultScenario { Scenario.reviewer = Nothing, Scenario.debt = Just (1, Nothing) }

{- | A changes-requested verdict beside debt and an open blocking finding is
not waived. The debt declares a missing review; it does not clear an
answer, and the finding is checked first.
-}
debtBesideRefusal :: [Check]
debtBesideRefusal =
  [ expectTrue "fixture/debt-beside-refusal: refused" "a changes-requested verdict with an open finding must not be permitted" (not (isPermitted decision))
  , expectRefusedWith "fixture/debt-beside-refusal: finding blocks first" "blocking-findings" decision
  , expectTrue "fixture/debt-beside-refusal: debt authorized nothing" "the declared debt must not appear in any basis" noBasisNamesDebt
  , expectRefusedWith "fixture/debt-beside-refusal: refusal stands without the finding" "verdict-stands" decisionWithoutFinding
  ]
  where
    scenario = defaultScenario
      { Scenario.reviewer        = Just ActorIndependent
      , Scenario.verdict         = ChangesRequested
      , Scenario.debt            = Just (1, Nothing)
      , Scenario.blockingFinding = True
      }
    decision               = (build scenario).decision
    decisionWithoutFinding = (build scenario { Scenario.blockingFinding = False }).decision
    noBasisNamesDebt = case decision of
      Permitted basis -> null (authorizationDebts basis.authorization)
      Refused _       -> True

{- | Integration under debt, then a negative audit. The read is fulfilled,
the findings stay open, the merge basis is untouched, and fulfilled does
not become approved.
-}
underDebtThenNegativeAudit :: [Check]
underDebtThenNegativeAudit =
  [ expectPermittedWith "fixture/under-debt: permitted on the waiver" (AuthorizedByWaiver (DebtId 1)) built.decision
  , expectEq "fixture/under-debt: basis survives the audit" (Just (AuthorizedByWaiver (DebtId 1))) (historicalAuthorization built.finalState)
  , expectEq "fixture/under-debt: read fulfilled by audit" (Just (ReadByAudit (EventId 901))) coverage.read
  , expectEq "fixture/under-debt: verdict is the audit's" (Just ChangesRequested) coverage.verdict
  , expectTrue "fixture/under-debt: fulfilled is not approved" "an audit must not approve by discharging a read" (not coverage.approved)
  , expectEq "fixture/under-debt: findings stay open" [FindingId 2] coverage.openFindings
  , expectEq "fixture/under-debt: authorization untouched" (Just (AuthorizedByWaiver (DebtId 1))) coverage.authorization
  ]
  where
    built    = build defaultScenario { Scenario.reviewer = Nothing, Scenario.debt = Just (1, Nothing), Scenario.audit = Just (ChangesRequested, True) }
    coverage = coverageAfterIntegration built.finalState

-- | An approved first patchset and a repair nobody read: the approval is
-- stale, and the owed review is a repair-unread, not nothing-read.
repairFollowedByDeeperReview :: [Check]
repairFollowedByDeeperReview =
  [ expectRefusedWith "fixture/repair-review: stale approval refused" "stale-approval" built.decision
  , expectEq "fixture/repair-review: deeper review owed" (OwedReview RepairUnread) (reviewObligation built.state)
  ]
  where
    built = build defaultScenario { Scenario.patchsets = 2, Scenario.verdictOnFirst = True, Scenario.reviewer = Just ActorIndependent }

-- | Omitted evidence is unknown: not false, not successful. Each way a gate
-- can fail to answer is its own reading and its own refusal.
unknownCoverage :: [Check]
unknownCoverage =
  [ expectEq "fixture/unknown: result omitted" Omitted omitted.result
  , expectEq "fixture/unknown: coverage never evaluated" NeverEvaluated omitted.coverage
  , expectEq "fixture/unknown: availability not produced" NotProduced omitted.availability
  , expectEq "fixture/unknown: falsification omitted" Omitted omitted.falsified
  , expectTrue "fixture/unknown: omitted never permits" "omitted evidence must not be permitted" (not (isPermitted (decisionIn GateOmitted)))
  , expectEq "fixture/unknown: gate refusal" (Left (GateNeverEvaluated gateName)) (gateGreen gateName (Just declaration) tree [])
  , expectEq "fixture/elsewhere: result observed" (Observed GatePass) elsewhere.result
  , expectEq "fixture/elsewhere: coverage elsewhere" (EvaluatedOtherTree (TreeId "tree-elsewhere")) elsewhere.coverage
  , expectRefusedWith "fixture/elsewhere: refused" "gates" (decisionIn GateOtherTree)
  , expectEq "fixture/changed: declaration moved" (DeclarationMoved (DeclarationId "build")) changed.coverage
  , expectRefusedWith "fixture/changed: refused" "gates" (decisionIn GateShapeMoved)
  , expectEq "fixture/unreadable: availability unreadable" EvidenceUnreadable unreadable.availability
  , expectEq "fixture/unreadable: result omitted" Omitted unreadable.result
  , expectRefusedWith "fixture/unreadable: refused" "gates" (decisionIn GateUnreadable)
  ]
  where
    gateName    = GateName "build"
    declaration = Declaration (DeclarationId "build") "cargo build" 60
    tree        = TreeId "tree1"
    builtIn mode    = build defaultScenario { Scenario.gateMode = mode }
    readingIn mode  = readGate gateName declaration tree (builtIn mode).state.verifications
    decisionIn mode = (builtIn mode).decision
    omitted    = readingIn GateOmitted
    elsewhere  = readingIn GateOtherTree
    changed    = readingIn GateShapeMoved
    unreadable = readingIn GateUnreadable

-- | Equal trees with different contributor and obligation scopes decide
-- differently. The tree alone says nothing.
equalTreeDifferentContributors :: [Check]
equalTreeDifferentContributors =
  [ expectRefusedWith "fixture/equal-tree: contributor reviewer refuses" "self-approval" contributorBuilt.decision
  , expectPermittedWith "fixture/equal-tree: independent reviewer permits" (AuthorizedByVerdict (EventId 2)) independentBuilt.decision
  , expectPermittedWith "fixture/equal-tree: waiver rescues the contributor" (AuthorizedByVerdictUnderWaiver (EventId 2) (DebtId 1)) waivedContributorBuilt.decision
  , expectTrue "fixture/equal-tree: same tree" "the two histories must share a tree" (patchsetTreeOf contributorBuilt == patchsetTreeOf independentBuilt)
  , expectTrue "fixture/equal-tree: debt unused beside approval" "an approval that needed no waiver must not name one" (debtsNotUsed independentState (AuthorizedByVerdict (EventId 2)) == [DebtId 1])
  ]
  where
    contributorBuilt       = build defaultScenario { Scenario.reviewer = Just ActorContributor }
    independentBuilt       = build defaultScenario { Scenario.reviewer = Just ActorIndependent }
    waivedContributorBuilt = build defaultScenario { Scenario.reviewer = Just ActorContributor, Scenario.debt = Just (1, Nothing) }
    independentState       = (build defaultScenario { Scenario.reviewer = Just ActorIndependent, Scenario.debt = Just (1, Nothing) }).state
    patchsetTreeOf built   = (.tree) <$> latestPatchset built.state

-- | An expired liveness episode ends the claim, never the facts recorded
-- while it ran.
retainedAcrossEpisodeExpiry :: [Check]
retainedAcrossEpisodeExpiry =
  [ expectTrue "fixture/episode: claim expired" "the claim must be marked expired" (all (.expired) state.claims)
  , expectTrue "fixture/episode: debt retained" "the debt must survive the expiry" (any ((== DebtId 1) . (.debtId)) state.debts)
  , expectTrue "fixture/episode: evidence retained" "the verification must survive the expiry" (not (null state.verifications))
  , expectPermittedWith "fixture/episode: waiver still applies" (AuthorizedByWaiver (DebtId 1)) built.decision
  ]
  where
    built = build defaultScenario { Scenario.reviewer = Nothing, Scenario.debt = Just (1, Nothing), Scenario.episodeExpired = True }
    state = built.state

-- | A debt declared beside an approval that stood anyway authorized
-- nothing. It is recorded debt, not an authorization input.
debtAuthorizedNothing :: [Check]
debtAuthorizedNothing =
  [ expectPermittedWith "fixture/debt-unused: approval authorizes" (AuthorizedByVerdict (EventId 2)) built.decision
  , expectTrue "fixture/debt-unused: waiver not used" "the unused debt must not be named" (not (waiverUsed authorization (DebtId 1)))
  , expectEq "fixture/debt-unused: recorded as unused" [DebtId 1] (debtsNotUsed built.state authorization)
  ]
  where
    built = build defaultScenario { Scenario.reviewer = Just ActorIndependent, Scenario.debt = Just (1, Nothing) }
    authorization = case built.decision of
      Permitted basis -> basis.authorization
      Refused _       -> AuthorizedByVerdict (EventId 0)

{- | A stale patchset is refused; a target or policy that moves between the
decision and the execution stands the action down rather than reusing the
basis.
-}
staleAndMovedBases :: [Check]
staleAndMovedBases =
  [ expectRefusedWith "fixture/stale: head moved" "head-moved" (build defaultScenario { Scenario.headMoved = True }).decision
  , expectTrue "fixture/target-moved: decision permits" "the decision is made against target-1" (isPermitted targetBuilt.decision)
  , expectEq "fixture/target-moved: execution stands down" (Left (RefusedBasisMoved [MovedTarget (Revision "target-1") (Revision "target-2")])) targetBuilt.execution
  , expectTrue "fixture/policy-moved: decision permits" "the decision is made under the danger policy" (isPermitted policyBuilt.decision)
  , expectEq "fixture/policy-moved: execution stands down" (Left (RefusedBasisMoved [MovedPolicy dangerPolicy openPolicy])) policyBuilt.execution
  ]
  where
    targetBuilt = build defaultScenario { Scenario.targetAfter = True }
    policyBuilt = build defaultScenario { Scenario.policyAfter = True }

-- | A permitted action is not an effect. The basis becomes history only when
-- the effect is recorded.
permissionIsNotEffect :: [Check]
permissionIsNotEffect =
  [ expectTrue "fixture/permission-not-effect: no integration without an effect" "permission alone must not record an integration" (historicalAuthorization built.state == Nothing)
  , case built.execution of
      Right plan   -> expectEq "fixture/permission-not-effect: recording lands the basis" (Just (AuthorizedByVerdict (EventId 2))) (historicalAuthorization (recordIntegration (EventId 77) plan built.state))
      Left refusal -> failCheck "fixture/permission-not-effect: recording lands the basis" ("unexpected refusal: " <> refusalText refusal)
  ]
  where
    built = build defaultScenario

-- | Audit gating: open changes refuse one; an approving audit needs a
-- declared independent identity; a negative audit is open to anyone.
auditRefusals :: [Check]
auditRefusals =
  [ expectAuditRefusal "fixture/audit: open change refuses" AuditWhileOpen (auditDischarges openState debt openAudit)
  , expectAuditRefusal "fixture/audit: assumed approver refuses" AuditAssumedAuditor (auditDischarges closedState debt approving { Audit.assumed = True })
  , expectAuditRefusal "fixture/audit: contributor approver refuses" AuditAuditorNotIndependent (auditDischarges closedState debt approving { Audit.actor = authorActor })
  , expectTrue "fixture/audit: independent approver discharges" "an independent approving audit must discharge the read" independentDischarges
  , expectTrue "fixture/audit: negative audit is open to anyone" "a negative audit needs no independence" negativeDischarges
  ]
  where
    debt        = Debt (DebtId 9) (EventId 900) (Just (PatchsetId 1)) Nothing "owed review" authorActor
    openState   = (build defaultScenario { Scenario.verdict = ChangesRequested }).state
    closedState = (build defaultScenario { Scenario.audit = Just (Approved, True) }).finalState
    openAudit   = Audit (EventId 950) (Revision "rev1") ChangesRequested otherActor False []
    approving   = Audit (EventId 951) (Revision "rev1") Approved otherActor False []
    independentDischarges = case auditDischarges closedState debt approving of
      Right discharge -> discharge.approves && discharge.read == ReadByAudit approving.event
      Left _          -> False
    negativeDischarges = case auditDischarges closedState debt approving { Audit.kind = ChangesRequested, Audit.actor = authorActor } of
      Right discharge -> not discharge.approves
      Left _          -> False
    expectAuditRefusal name expected = \case
      Left refusal
        | refusal == expected -> passCheck name (auditRefusalText refusal)
        | otherwise           -> failCheck name ("refused as " <> show refusal <> ", expected " <> show expected)
      Right discharge -> failCheck name ("discharged as " <> show discharge)

-- | A provisional approval gates like any other; corroboration is owed, not
-- required.
provisionalGates :: [Check]
provisionalGates =
  [ expectPermittedWith "fixture/provisional: gates" (AuthorizedByVerdict (EventId 2)) (build defaultScenario { Scenario.provisional = True }).decision
  ]

-- | The demonstrated counterexample the report cites: one deliberate fault,
-- one minimal history, one exact divergence.
demonstratedCounterexample :: [Check]
demonstratedCounterexample =
  [ expectRefusedWith "fixture/demonstration: model refuses the contributor reviewer" "self-approval" built.decision
  , expectTrue "fixture/demonstration: fault ignored contributor identity" "the contributor-identity-ignored mutant must permit where the model refuses" (isPermitted mutantDecision)
  ]
  where
    built  = build defaultScenario { Scenario.reviewer = Just ActorContributor }
    mutant = case listToMaybe [ m | m <- allMutants, m.name == "contributor-identity-ignored" ] of
      Just found -> found
      Nothing    -> error "the contributor-identity-ignored mutant is missing"
    mutantDecision = case mutant.run built of
      BehaviourDecision decision -> decision
      _otherChannel              -> Refused RefusedNoApproval
