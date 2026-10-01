{- | Unit fixtures. Each one anchors a piece of intended meaning with an
exact expected answer, including the answer's shape: which refusal, which
authorization, which gate reading.
-}
module Fixtures ( fixtureChecks ) where

import Arc.Model
import Arc.Model.Declaration qualified as Declaration
import Arc.Model.Ledger.Audit qualified as Audit
import Arc.Model.Ledger.Brief qualified as Brief
import Arc.Model.Ledger.Patchset qualified as Patchset
import Arc.Model.Ledger.ProbeRun qualified as ProbeRun
import Arc.Model.Ledger.Verdict qualified as Verdict
import Arc.Model.State qualified as State
import Arc.Model.Ledger.Verification qualified as Verification
import Arc.Model.Observations qualified as Observations
import Generators
import Mutants ( Behaviour(..), Mutant(..), allMutants )
import Render
import Scenario qualified

import Data.Maybe ( fromMaybe, listToMaybe )
import Data.Set qualified as Set


fixtureChecks :: [Check]
fixtureChecks = concat
  [ waiverExpiry
  , debtBesideRefusal
  , underDebtThenNegativeAudit
  , repairFollowedByDeeperReview
  , derivedDebtKinds
  , unknownCoverage
  , environmentCoverage
  , evidenceKeyedByTree
  , contractQuestions
  , iteratingApproval
  , effectiveAuthors
  , equalTreeDifferentContributors
  , externalDecisions
  , externalDangerScopes
  , debtBesideExternal
  , retainedAcrossEpisodeExpiry
  , debtAuthorizedNothing
  , staleAndMovedBases
  , authorityStandsDown
  , readinessRebuilt
  , undeclaredInvoker
  , basisDeclarations
  , prerequisiteClosures
  , everyGround
  , permissionIsNotEffect
  , auditRefusals
  , provisionalGates
  , dirtyTree
  , mergedTree
  , acceptanceProbes
  , missingBranch
  , conflictingDeclarations
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
    scenario = defaultScenario { Scenario.reviewer = Nothing, Scenario.debts = [(1, Nothing)] }

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
      , Scenario.debts            = [(1, Nothing)]
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
    built    = build defaultScenario { Scenario.reviewer = Nothing, Scenario.debts = [(1, Nothing)], Scenario.audit = Just (ChangesRequested, True) }
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

{- | The kind a debt names where none is declared (C21). The ledger cannot
tell a merge resolution from a repair, so a merge resolution is only ever
declared; an approved patchset followed by one nobody read is a repair.
-}
derivedDebtKinds :: [Check]
derivedDebtKinds =
  [ expectEq "fixture/debt-kind: nothing read on any patchset" [NothingRead] (kindsIn defaultScenario { Scenario.reviewer = Nothing, Scenario.debts = [(1, Nothing)] })
  , expectEq "fixture/debt-kind: verdicts only from contributors" [ContributorOnly] (kindsIn defaultScenario { Scenario.reviewer = Just ActorContributor, Scenario.debts = [(1, Nothing)] })
  , expectEq "fixture/debt-kind: an approval, then a patchset nobody read" [RepairUnread] (kindsIn afterApproval { Scenario.debts = [(2, Nothing)] })
  , expectEq "fixture/debt-kind: a declared kind wins" [MergeResolutionUnread] (kindsIn afterApproval { Scenario.debts = [(2, Just MergeResolutionUnread)] })
  , expectEq "fixture/debt-kind: a comment, then a patchset nobody read, owes independent review" (OwedReview IndependentReview) (reviewObligation (build afterApproval { Scenario.verdict = CommentOnly }).state)
  ]
  where
    afterApproval = defaultScenario { Scenario.patchsets = 2, Scenario.verdictOnFirst = True }
    kindsIn scenario = let state = (build scenario).state in map (debtKindFor state) state.debts

-- the gate every scenario declares, read the way the decision reads it

gateName :: GateName
gateName = GateName "build"

declaration :: Declaration
declaration = Declaration (DeclarationId "build") "cargo build" 60 (Just (ProbeCommand "probe"))

readingIn :: GateMode -> GateReading
readingIn mode = readGate gateName declaration (TreeId "tree1") (hereIn built) Nothing built.state.verifications
  where
    built = build defaultScenario { Scenario.gateMode = mode }

readGateIn :: Scenario -> GateReading
readGateIn scenario = readGate gateName declaration (TreeId "tree1") (hereIn built) ((.revision) <$> dirtyTreeWaiver built.state) built.state.verifications
  where
    built = build scenario

hereIn :: Built -> Observed EnvironmentId
hereIn built = fromMaybe Omitted (lookup (ProbeCommand "probe") built.observation.environments)

decisionIn :: GateMode -> Decision
decisionIn mode = (build defaultScenario { Scenario.gateMode = mode }).decision

-- | Omitted evidence is unknown: not false, not successful. Each way a gate
-- can fail to answer is its own reading and its own refusal.
unknownCoverage :: [Check]
unknownCoverage =
  [ expectEq "fixture/unknown: result omitted" Omitted omitted.result
  , expectEq "fixture/unknown: coverage never evaluated" NeverEvaluated omitted.coverage
  , expectEq "fixture/unknown: availability not produced" NotProduced omitted.availability
  , expectEq "fixture/unknown: falsification omitted" Omitted omitted.falsified
  , expectTrue "fixture/unknown: omitted never permits" "omitted evidence must not be permitted" (not (isPermitted (decisionIn EvidenceOmitted)))
  , expectEq "fixture/unknown: gate refusal" (Left (GateNeverEvaluated gateName)) (gateGreen gateName (Just declaration) (TreeId "tree1") Omitted Nothing [])
  , expectEq "fixture/elsewhere: result observed" (Observed GatePass) elsewhere.result
  , expectEq "fixture/elsewhere: coverage elsewhere" (EvaluatedOtherTree (TreeId "tree-elsewhere")) elsewhere.coverage
  , expectRefusedWith "fixture/elsewhere: refused" "gates" (decisionIn EvidenceOtherTree)
  , expectEq "fixture/changed: declaration moved" (DeclarationMoved (DeclarationId "build")) changed.coverage
  , expectRefusedWith "fixture/changed: refused" "gates" (decisionIn EvidenceShapeMoved)
  , expectEq "fixture/unreadable: availability unreadable" EvidenceUnreadable unreadable.availability
  , expectEq "fixture/unreadable: result omitted" Omitted unreadable.result
  , expectRefusedWith "fixture/unreadable: refused" "gates" (decisionIn EvidenceRecordUnreadable)
  , expectEq "fixture/failed: result observed" (Observed GateFail) failed.result
  , expectEq "fixture/failed: covered" (Covered (EventId 3)) failed.coverage
  , expectRefusedWith "fixture/failed: refused" "gates" (decisionIn EvidenceFailing)
  ]
  where
    omitted    = readingIn EvidenceOmitted
    elsewhere  = readingIn EvidenceOtherTree
    changed    = readingIn EvidenceShapeMoved
    unreadable = readingIn EvidenceRecordUnreadable
    failed     = readingIn EvidenceFailing

{- | Evidence answers for the environment it was produced in. A gate that
declares a probe takes only evidence carrying the identity the probe yields
where the decision is made; one without a probe takes evidence from
anywhere.
-}
environmentCoverage :: [Check]
environmentCoverage =
  [ expectEq "fixture/environment: other environment is not coverage" (EvaluatedOtherEnvironment (EnvironmentId "env-elsewhere") (EnvironmentId "env-here")) (readingIn EvidenceOtherEnvironment).coverage
  , expectRefusedWith "fixture/environment: other environment refused" "gates" (decisionIn EvidenceOtherEnvironment)
  , expectEq "fixture/environment: unrecorded identity" EnvironmentUnrecorded (readingIn EvidenceUnrecordedEnvironment).coverage
  , expectRefusedWith "fixture/environment: unrecorded identity refused" "gates" (decisionIn EvidenceUnrecordedEnvironment)
  , expectEq "fixture/environment: probe failed here" EnvironmentUnobserved (readingIn EvidenceProbeFailed).coverage
  , expectRefusedWith "fixture/environment: probe failed refused" "gates" (decisionIn EvidenceProbeFailed)
  , expectTrue "fixture/environment: no probe takes evidence from anywhere" "a gate without a probe must accept evidence recorded without an identity" unprobedGreen
  ]
  where
    unprobed      = declaration { Declaration.environment = Nothing }
    anywhere      = Verification (EventId 1) gateName (DeclarationId "build") (declarationShape unprobed) (Revision "rev1") (TreeId "tree1") GatePass RanLocally Nothing True Nothing (Observed CleanWorktree)
    unprobedGreen = either (const False) (const True) (gateGreen gateName (Just unprobed) (TreeId "tree1") Omitted Nothing [anywhere])

{- | Evidence is keyed by the tree the run read, the declaration it ran, and
the environment it recorded (C14). A newer record under another key says
nothing at the evaluated tree and does not hide an older one that answers
there.
-}
evidenceKeyedByTree :: [Check]
evidenceKeyedByTree =
  [ expectEq "fixture/keyed: a newer run at another tree does not hide the pass here" (Covered (EventId 1)) (keyedAt [passHere, run 2 (Revision "rev2") (TreeId "tree2") GateFail here]).coverage
  , expectEq "fixture/keyed: the pass here is the result" (Observed GatePass) (keyedAt [passHere, run 2 (Revision "rev2") (TreeId "tree2") GateFail here]).result
  , expectEq "fixture/keyed: a newer run of another declaration does not hide the pass here" (Covered (EventId 1)) (keyedAt [passHere, (run 2 (Revision "rev1") (TreeId "tree1") GatePass here) { Verification.shape = DeclarationShape "cargo build --locked" 60 }]).coverage
  , expectEq "fixture/keyed: a newer run in another environment does not hide the pass here" (Covered (EventId 1)) (keyedAt [passHere, run 2 (Revision "rev1") (TreeId "tree1") GatePass (Just (EnvironmentId "env-elsewhere"))]).coverage
  , expectEq "fixture/keyed: an earlier revision with the same tree answers" (Covered (EventId 1)) (keyedAt [passHere { Verification.revision = Revision "rev0" }]).coverage
  , expectEq "fixture/keyed: with nothing here, the newest record says why" (EvaluatedOtherTree (TreeId "tree2")) (keyedAt [run 2 (Revision "rev2") (TreeId "tree2") GatePass here]).coverage
  , expectEq "fixture/falsified: any passing run here that names a failure discriminates" (Observed known) (keyedAt [passHere { Verification.answers = Just known }, run 2 (Revision "rev1") (TreeId "tree1") GatePass here]).falsified
  , expectEq "fixture/falsified: a pass in another environment discriminates at this tree" (Observed known) (keyedAt [passHere, (run 2 (Revision "rev1") (TreeId "tree1") GatePass (Just (EnvironmentId "elsewhere"))) { Verification.answers = Just known }]).falsified
  , expectEq "fixture/falsified: a pass under another declaration discriminates at this tree" (Observed known) (keyedAt [passHere, passHere { Verification.declaration = DeclarationId "old-build", Verification.shape = DeclarationShape "old command" 60, Verification.answers = Just known }]).falsified
  , expectEq "fixture/falsified: a failing run's label is no demonstration" Omitted (keyedAt [(run 1 (Revision "rev1") (TreeId "tree1") GateFail here) { Verification.answers = Just known }, run 2 (Revision "rev1") (TreeId "tree1") GatePass here]).falsified
  , expectEq "fixture/falsified: a pass at another tree is no demonstration here" Omitted (keyedAt [(run 1 (Revision "rev2") (TreeId "tree2") GatePass here) { Verification.answers = Just known }, passHere]).falsified
  ]
  where
    here     = Just (EnvironmentId "env-here")
    known    = FailureLabel "known-failure"
    passHere = run 1 (Revision "rev1") (TreeId "tree1") GatePass here
    run event revision tree result environment = Verification (EventId event) gateName (DeclarationId "build") (declarationShape declaration) revision tree result RanLocally Nothing True environment (Observed CleanWorktree)
    keyedAt  = readGate gateName declaration (TreeId "tree1") (Observed (EnvironmentId "env-here")) Nothing

{- | The three contract questions, each on the named history the
differential replays through arc, asserting the settled part of its clause.

(a) C14: an older pass at tree A and a newer run at tree B, evaluated at A.
The run at B says nothing; the pass at A answers.

(b) C7: two waivers for different patchsets. Each applies to its own
patchset only, and the latest one's waiver authorizes.

(c) C11: an iterating change with no approval is refused as iterating.
The approval ground is suppressed; gates and other blockers still stand.
-}
contractQuestions :: [Check]
contractQuestions =
  [ expectEq "fixture/question-a: the pass at A answers, the run at B says nothing" (Right [(gateName, passAtA, DeclarationId "build")]) (basisGates olderPass.decision)
  , expectEq "fixture/question-a: the latest patchset shares tree A" ((.tree) <$> patchsetById olderPass.state (PatchsetId 1)) ((.tree) <$> latestPatchset olderPass.state)
  , expectEq "fixture/question-b: the first waiver applies to ps-01" (Just (DebtId 1)) ((.debtId) <$> newestWaiver waivers.state (PatchsetId 1))
  , expectEq "fixture/question-b: the second waiver applies to ps-02" (Just (DebtId 2)) ((.debtId) <$> newestWaiver waivers.state (PatchsetId 2))
  , expectPermittedWith "fixture/question-b: the latest patchset's waiver authorizes" (AuthorizedByWaiver (DebtId 2)) waivers.decision
  , expectEq "fixture/question-c: iteration suppresses the approval ground" [RefusedIterating] (refusals iterating.observation iterating.state)
  ]
  where
    named name = maybe (error ("no named scenario " <> name)) build (lookup name namedScenarios)
    olderPass  = named "gate-older-pass-same-tree"
    waivers    = named "waivers-per-patchset"
    iterating  = named "iterating-unreviewed"
    passAtA    = fromMaybe (EventId 0) (listToMaybe [ v.event | v <- olderPass.state.verifications, v.revision == Revision "rev1" ])
    basisGates = \case
      Permitted basis -> Right basis.gates
      Refused refusal -> Left refusal

-- | C11 suppresses approval grounds while every other blocker stands.
iteratingApproval :: [Check]
iteratingApproval =
  [ expectEq "fixture/iterating: stale approval suppressed" [RefusedIterating] (grounds defaultScenario { Scenario.patchsets = 2, Scenario.verdictOnFirst = True })
  , expectEq "fixture/iterating: self-approval suppressed" [RefusedIterating] (grounds defaultScenario { Scenario.reviewer = Just Scenario.ActorContributor })
  , expectEq "fixture/iterating: negative verdict suppressed" [RefusedIterating] (grounds defaultScenario { Scenario.verdict = ChangesRequested })
  , expectEq "fixture/iterating: contested verdict suppressed" [RefusedIterating] (refusals contested.observation contested.state { State.verdicts = [tip, tip { Verdict.event = EventId 799 }] })
  , expectEq "fixture/iterating: a red gate still blocks" ["iterating", "gates"] (map refusalTag (grounds defaultScenario { Scenario.reviewer = Nothing, Scenario.gateMode = EvidenceFailing }))
  , expectRefusedWith "fixture/iterating: clearing iteration restores approval check" "no-approval" (build defaultScenario { Scenario.reviewer = Nothing }).decision
  ]
  where
    grounds scenario = let built = build scenario { Scenario.iterating = True } in refusals built.observation built.state
    contested = build defaultScenario { Scenario.iterating = True }
    tip = fromMaybe (error "fixture needs verdict") (governingVerdict contested.state)

-- | C4 uses the represented subject and falls back only for an empty set.
effectiveAuthors :: [Check]
effectiveAuthors =
  [ expectEq "fixture/effective-author: subject overrides invoker" authorActor (effectiveActor represented)
  , expectEq "fixture/effective-author: absent subject uses invoker" reviewActor (effectiveActor verdict)
  , expectEq "fixture/effective-author: empty contributors use effective author" (Set.singleton otherActor) (effectiveContributors representedPatchset)
  , expectEq "fixture/effective-author: declared contributors win" (Set.singleton authorActor) (effectiveContributors representedPatchset { Patchset.contributors = Set.singleton authorActor })
  , expectEq "fixture/effective-author: represented author cannot approve independently" (Left (RefusedSelfApproval verdict.event authorActor (effectiveContributors patchset))) (authorizationFor built.observation.policy built.state { State.verdicts = [represented] } patchset)
  ]
  where
    built = build defaultScenario
    verdict = fromMaybe (error "fixture needs verdict") (governingVerdict built.state)
    patchset = fromMaybe (error "fixture needs patchset") (latestPatchset built.state)
    represented = verdict { Verdict.onBehalfOf = Just authorActor }
    representedPatchset = patchset { Patchset.author = otherActor, Patchset.contributors = Set.empty }

{- | A run on a dirty worktree describes content no checkout of its
revision reproduces. It counts only under a waiver naming exactly the
revision it was recorded at; a run recording nothing about its worktree
counts under none, and evidence somebody attests to carries no worktree
of arc's observing.
-}
dirtyTree :: [Check]
dirtyTree =
  [ expectEq "fixture/dirty: dirty evidence is not coverage" EvaluatedDirtyTree dirty.coverage
  , expectEq "fixture/dirty: its result stands beside it" (Observed GatePass) dirty.result
  , expectRefusedWith "fixture/dirty: refused" "gates" (worktreeDecision WorktreeDirty)
  , expectPermittedWith "fixture/dirty: a waiver at its revision counts it" (AuthorizedByVerdict (EventId 2)) (worktreeDecision WorktreeDirtyWaived)
  , expectRefusedWith "fixture/dirty: a waiver at another revision does not" "gates" (worktreeDecision WorktreeDirtyWaivedElsewhere)
  , expectEq "fixture/dirty: nothing recorded about the worktree" (Left (GateWorktreeUnrecorded gateName)) (gateGreen gateName (Just declaration) (TreeId "tree1") here Nothing [unrecorded])
  , expectTrue "fixture/dirty: attested evidence carries no worktree" "an attested pass must be covered whatever its worktree" (either (const False) (const True) (gateGreen gateName (Just declaration) (TreeId "tree1") here Nothing [attested]))
  ]
  where
    dirty      = (readGateIn defaultScenario { Scenario.worktree = WorktreeDirty })
    here       = Observed (EnvironmentId "env-here")
    unrecorded = Verification (EventId 1) gateName (DeclarationId "build") (declarationShape declaration) (Revision "rev1") (TreeId "tree1") GatePass RanLocally Nothing True (Just (EnvironmentId "env-here")) Omitted
    attested   = Verification (EventId 1) gateName (DeclarationId "build") (declarationShape declaration) (Revision "rev1") (TreeId "tree1") GatePass Attested Nothing True (Just (EnvironmentId "env-here")) (Observed DirtyWorktree)
    worktreeDecision mode = (build defaultScenario { Scenario.worktree = mode }).decision

{- | A change behind its target ships the merge, a tree neither branch
committed. Evidence at the head says nothing about it: a merge nobody ran
a gate on is its own ground beside the gate's. A head that does not merge
with its target owes a rebase, and nothing else about it changes.
-}
mergedTree :: [Check]
mergedTree =
  [ expectRefusedWith "fixture/merged-tree: unevaluated merge refused" "merged-tree-unevaluated" behind.decision
  , expectTrue "fixture/merged-tree: the gate is refused beside it" "evidence at the head tree must not cover the merge" (any isGates (refusals behind.observation behind.state))
  , expectTrue "fixture/merged-tree: evaluated merge permits on the merged tree" "the basis must name the merge's tree" (basisTree evaluated.decision == Just (TreeId "merged"))
  , expectEq "fixture/needs-rebase: the rebase is the only ground" [RefusedNeedsRebase] (refusals conflicting.observation conflicting.state)
  ]
  where
    behind      = build defaultScenario { Scenario.targetMode = TargetBehind }
    evaluated   = build defaultScenario { Scenario.targetMode = TargetBehindEvaluated }
    conflicting = build defaultScenario { Scenario.targetMode = TargetConflicting }
    isGates     = \case
      RefusedGates _ -> True
      _other         -> False
    basisTree   = \case
      Permitted basis -> Just basis.tree
      Refused _       -> Nothing

{- | A probe a brief declares is discharged by a failure at the brief's base
and a pass at the head. A pass at the base, a missing or failing final run,
and a base that is the head itself each leave it undischarged.
-}
acceptanceProbes :: [Check]
acceptanceProbes =
  [ expectPermittedWith "fixture/probes: discharged" (AuthorizedByVerdict (EventId 2)) (probeDecision ProbeDischarged)
  , expectEq "fixture/probes: a pass at the base does not discriminate" [ProbeNotDiscriminating accept (Observed GatePass) (Observed GatePass)] (probeGrounds ProbeBaselinePassed)
  , expectEq "fixture/probes: no final run" [ProbeNotDiscriminating accept (Observed GateFail) Omitted] (probeGrounds ProbeFinalMissing)
  , expectEq "fixture/probes: a failing final run" [ProbeNotDiscriminating accept (Observed GateFail) (Observed GateFail)] (probeGrounds ProbeFinalFailed)
  , expectEq "fixture/probes: fail and pass at one revision" [ProbeCannotDischarge accept] (probeGrounds ProbeUndischargeable)
  , expectEq "fixture/probes: no brief base cannot discharge" [ProbeCannotDischarge accept] (at discharged.state { State.briefs = map (\b -> b { Brief.base = Nothing }) discharged.state.briefs })
  , expectEq "fixture/probes: newer failing final supersedes pass" [ProbeNotDiscriminating accept (Observed GateFail) (Observed GateFail)] (at discharged.state { State.probeRuns = discharged.state.probeRuns <> [finalRun { ProbeRun.event = EventId 800, ProbeRun.result = GateFail }] })
  , expectEq "fixture/probes: another brief supplies no final evidence" [ProbeNotDiscriminating accept (Observed GateFail) Omitted] (at discharged.state { State.probeRuns = [ r { ProbeRun.brief = if r.phase == Final then EventId 799 else r.brief } | r <- discharged.state.probeRuns ] })
  , expectEq "fixture/probes: another revision supplies no final evidence" [ProbeNotDiscriminating accept (Observed GateFail) Omitted] (at discharged.state { State.probeRuns = [ r { ProbeRun.revision = if r.phase == Final then Revision "elsewhere" else r.revision } | r <- discharged.state.probeRuns ] })
  , expectRefusedWith "fixture/probes: refused" "acceptance-probes" (probeDecision ProbeFinalMissing)
  ]
  where
    accept = ProbeName "accept"
    discharged = build defaultScenario { Scenario.probe = ProbeDischarged }
    finalRun = fromMaybe (error "fixture needs final run") (listToMaybe [ r | r <- discharged.state.probeRuns, r.phase == Final ])
    at state = probeRefusals state (fromMaybe (error "fixture needs patchset") (latestPatchset state))
    probeDecision mode = (build defaultScenario { Scenario.probe = mode }).decision
    probeGrounds mode = concat
      [ refused
      | let built = build defaultScenario { Scenario.probe = mode }
      , RefusedAcceptanceProbes refused <- refusals built.observation built.state
      ]

-- | A change whose branch is gone has no head to decide about or to act on.
missingBranch :: [Check]
missingBranch =
  [ expectRefusedWith "fixture/branch-missing: refused" "branch-missing" missing.decision
  , expectTrue "fixture/branch-missing: no moved head beside it" "a missing head is not a moved one" (all ((/= "head-moved") . refusalTag) (refusals missing.observation missing.state))
  , expectEq "fixture/branch-missing: execution refused" (Left RefusedBranchMissing) (execute permitted.executionObservation { Observations.head = Omitted } permitted.state permitted.decision)
  ]
  where
    missing   = build defaultScenario { Scenario.branchMissing = True, Scenario.headMoved = True }
    permitted = build defaultScenario

-- | Two policy layers declaring one gate differently leave no declaration
-- set to evaluate against: that refusal stands alone, whatever else the
-- history holds.
conflictingDeclarations :: [Check]
conflictingDeclarations =
  [ expectEq "fixture/conflicting-gates: the only ground" [RefusedConflictingDeclarations [gateName]] (refusals built.observation built.state)
  ]
  where
    built = build defaultScenario { Scenario.conflictingGates = True, Scenario.blockingFinding = True, Scenario.gateMode = EvidenceFailing }

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
    waivedContributorBuilt = build defaultScenario { Scenario.reviewer = Just ActorContributor, Scenario.debts = [(1, Nothing)] }
    independentState       = (build defaultScenario { Scenario.reviewer = Just ActorIndependent, Scenario.debts = [(1, Nothing)] }).state
    patchsetTreeOf built   = (.tree) <$> latestPatchset built.state

{- | A decision made outside arc: an approval authorizes only where no
independent review is owed and never over a local refusal; a change request
or rejection stands over any approval and is not waivable; when a local
approval also stands, the basis names the verdict arc witnessed.
-}
externalDecisions :: [Check]
externalDecisions =
  [ expectPermittedWith "fixture/external: approval authorizes where no independent review is owed" (AuthorizedByExternalVerdict (EventId 2)) (decisionOf open)
  , expectRefusedWith "fixture/external: approval is not independent review" "no-approval" (decisionOf danger)
  , expectPermittedWith "fixture/external: a local approval is the one named" (AuthorizedByVerdict (EventId 2)) (decisionOf both)
  , expectRefusedWith "fixture/external: a change request stands over a local approval" "external-verdict-stands" (decisionOf requested)
  , expectRefusedWith "fixture/external: a change request is not waivable" "external-verdict-stands" (decisionOf requestedWaived)
  , expectRefusedWith "fixture/external: a local refusal stands over an external approval" "verdict-stands" (decisionOf localRefusal)
  , expectRefusedWith "fixture/external: a rejection closes the change" "closed" (decisionOf rejected)
  , expectTrue "fixture/external: a rejection stands beneath the closure" "the rejection must be a ground beside the closure" (RefusedExternalVerdictStands ExternalRejected (EventId 2) `elem` refusals (build rejected).observation (build rejected).state)
  , expectTrue "fixture/external: an external approval is no independent read" "coverage must not report a read arc cannot verify" (coverage.read == Nothing)
  ]
  where
    decisionOf scenario = (build scenario).decision
    open            = defaultScenario { Scenario.reviewer = Nothing, Scenario.externalVerdict = Just ExternalApproved, Scenario.policy = openPolicy }
    danger          = open { Scenario.policy = dangerPolicy }
    both            = defaultScenario { Scenario.externalVerdict = Just ExternalApproved }
    requested       = defaultScenario { Scenario.externalVerdict = Just ExternalChangesRequested }
    requestedWaived = requested { Scenario.reviewer = Nothing, Scenario.debts = [(1, Nothing)] }
    localRefusal    = defaultScenario { Scenario.verdict = ChangesRequested, Scenario.externalVerdict = Just ExternalApproved, Scenario.policy = openPolicy }
    rejected        = defaultScenario { Scenario.reviewer = Nothing, Scenario.externalVerdict = Just ExternalRejected, Scenario.policy = openPolicy }
    coverage        = coverageAfterIntegration (build open).finalState

{- | An external approval never counts alone inside the danger gate,
whatever self-approval policy says, though a local approval beside it
still authorizes. A repository that declares no danger path lets it count
alone unless self-approval is forbidden.
-}
externalDangerScopes :: [Check]
externalDangerScopes =
  [ expectRefusedWith "fixture/external-scope: alone on a danger path with self-approval permitted" "no-approval" (decisionOf dangerAlone)
  , expectPermittedWith "fixture/external-scope: a local approval beside it on that path" (AuthorizedByVerdict (EventId 2)) (decisionOf dangerBeside)
  , expectPermittedWith "fixture/external-scope: alone where no danger path is declared" (AuthorizedByExternalVerdict (EventId 2)) (decisionOf undeclared)
  , expectRefusedWith "fixture/external-scope: alone where none is declared and self-approval is forbidden" "no-approval" (decisionOf undeclaredForbidden)
  ]
  where
    decisionOf scenario = (build scenario).decision
    dangerAlone         = defaultScenario { Scenario.reviewer = Nothing, Scenario.externalVerdict = Just ExternalApproved, Scenario.policy = dangerPermittingSelfPolicy }
    dangerBeside        = dangerAlone { Scenario.reviewer = Just ActorIndependent }
    undeclared          = dangerAlone { Scenario.policy = undeclaredDangerPolicy }
    undeclaredForbidden = dangerAlone { Scenario.policy = undeclaredDangerPolicy { forbidSelfApproval = True } }

-- | A debt beside an external approval that authorizes alone supplied
-- nothing: the basis names the external approval, and the review the debt
-- records is still owed after the merge.
debtBesideExternal :: [Check]
debtBesideExternal =
  [ expectPermittedWith "fixture/debt-beside-external: the external approval authorizes" (AuthorizedByExternalVerdict (EventId 2)) built.decision
  , expectEq "fixture/debt-beside-external: the debt is not in the basis" [DebtId 1] (debtsNotUsed built.state authorization)
  , expectEq "fixture/debt-beside-external: the debt is still owed" (Just (DebtId 1), Nothing) (coverage.debt, coverage.read)
  ]
  where
    built         = build defaultScenario { Scenario.reviewer = Nothing, Scenario.debts = [(1, Nothing)], Scenario.externalVerdict = Just ExternalApproved, Scenario.policy = openPolicy }
    coverage      = coverageAfterIntegration built.finalState
    authorization = case built.decision of
      Permitted basis -> basis.authorization
      Refused _       -> AuthorizedByWaiver (DebtId 0)

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
    built = build defaultScenario { Scenario.reviewer = Nothing, Scenario.debts = [(1, Nothing)], Scenario.episodeExpired = True }
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
    built = build defaultScenario { Scenario.reviewer = Just ActorIndependent, Scenario.debts = [(1, Nothing)] }
    authorization = case built.decision of
      Permitted basis -> basis.authorization
      Refused _       -> AuthorizedByVerdict (EventId 0)

{- | A stale patchset is refused; a target or policy that moves between the
decision and the execution stands the action down rather than reusing the
basis. A moved target moves the tree that would ship with it: the head is
behind the new target, and readiness computed again finds the new merge
unevaluated.
-}
staleAndMovedBases :: [Check]
staleAndMovedBases =
  [ expectRefusedWith "fixture/stale: head moved" "head-moved" (build defaultScenario { Scenario.headMoved = True }).decision
  , expectTrue "fixture/target-moved: decision permits" "the decision is made against target-1" (isPermitted targetBuilt.decision)
  , expectEq "fixture/target-moved: execution stands down" (Left (RefusedBasisMoved [MovedTarget (Revision "target-1") (Revision "target-2"), MovedTree (TreeId "tree1") (TreeId "merged-after"), MovedReadiness [RefusedMergedTreeUnevaluated (TreeId "merged-after"), RefusedGates [GateEvaluatedOtherTree gateName (TreeId "tree1")]]])) targetBuilt.execution
  , expectTrue "fixture/policy-moved: decision permits" "the decision is made under the danger policy" (isPermitted policyBuilt.decision)
  , expectEq "fixture/policy-moved: execution stands down" (Left (RefusedBasisMoved [MovedPolicy dangerPolicy openPolicy])) policyBuilt.execution
  ]
  where
    targetBuilt = build defaultScenario { Scenario.targetAfter = True }
    policyBuilt = build defaultScenario { Scenario.policyAfter = True }

{- | Before acting, readiness is computed again and the basis rebuilt; if
the two differ nothing is written (C20). A finding opened, a hold set, a
refusing verdict, or newer gate evidence recorded after the decision each
stand the action down. The plan still records nothing: only
'recordIntegration' does.
-}
readinessRebuilt :: [Check]
readinessRebuilt =
  [ expectTrue "fixture/rebuilt: the decision permits" "the history is integratable when decided" (isPermitted built.decision)
  , expectEq "fixture/rebuilt: a finding opened after the decision" (Left (RefusedBasisMoved [MovedReadiness [RefusedBlockingFindings [FindingId 7]]])) (executeAfter [finding])
  , expectEq "fixture/rebuilt: a hold set after the decision" (Left (RefusedBasisMoved [MovedReadiness [RefusedHoldActive (HoldId 1)]])) (executeAfter [HoldSet (HoldId 1)])
  , expectEq "fixture/rebuilt: a refusing verdict after the decision" (Left (RefusedBasisMoved [MovedReadiness [RefusedVerdictStands ChangesRequested (EventId 81)]])) (executeAfter [refusing])
  , expectEq "fixture/rebuilt: a failing run after the decision" (Left (RefusedBasisMoved [MovedReadiness [RefusedGates [GateFailed gateName (EventId 82)]]])) (executeAfter [rerun GateFail])
  , expectEq "fixture/rebuilt: a newer pass rebuilds another basis" (Left (RefusedBasisMoved [MovedGates [(gateName, EventId 3, DeclarationId "build")] [(gateName, EventId 82, DeclarationId "build")]])) (executeAfter [rerun GatePass])
  , expectTrue "fixture/rebuilt: an unchanged history executes and records nothing" "the plan is not the effect" (either (const False) (const True) (executeAfter []) && null built.state.integrations)
  ]
  where
    built = build defaultScenario
    executeAfter later = execute built.executionObservation (replay (ChangeId "demo") (built.events <> later)) built.decision
    finding  = FindingRecorded Finding { event = EventId 80, findingId = FindingId 7, patchset = PatchsetId 1, actor = otherActor, blocking = True, audit = False }
    refusing = VerdictRecorded Verdict
      { event = EventId 81, patchset = PatchsetId 1, kind = ChangesRequested, actor = otherActor, onBehalfOf = Nothing
      , assumed = False, provisional = Nothing, relation = Supersedes, supersedes = Just (EventId 2)
      }
    rerun result = VerificationRecorded (Verification (EventId 82) gateName (DeclarationId "build") (declarationShape declaration) (Revision "rev1") (TreeId "tree1") result RanLocally Nothing True (Just (EnvironmentId "env-here")) (Observed CleanWorktree))

-- | Integration authority is asked of the store that acts, not of the
-- history: the decision permits, and the execution stands down.
authorityStandsDown :: [Check]
authorityStandsDown =
  [ expectTrue "fixture/authority: decision permits" "a check does not consult replica authority" (isPermitted built.decision)
  , expectEq "fixture/authority: execution stands down" (Left RefusedAuthorityWithheld) built.execution
  ]
  where
    built = build defaultScenario { Scenario.authorityWithheld = True }

{- | Under @require_declared_actor@, reading is unaffected (C18): a readiness
check does not refuse an undeclared invoker, and the integration refuses
it before it merges.
-}
undeclaredInvoker :: [Check]
undeclaredInvoker =
  [ expectEq "fixture/undeclared-actor: the check does not refuse the invoker" [] (refusals undeclared built.state)
  , expectTrue "fixture/undeclared-actor: the decision permits" "a readiness check reads without refusing" (isPermitted decision)
  , expectEq "fixture/undeclared-actor: execution refuses" (Left RefusedUndeclaredActor) (execute undeclared built.state decision)
  , expectTrue "fixture/undeclared-actor: a declared invoker executes" "a declared invoker satisfies the policy" (either (const False) (const True) (execute built.observation built.state built.decision))
  ]
  where
    built      = build defaultScenario { Scenario.policy = requireDeclaredPolicy }
    undeclared = built.observation { Observations.invokerDeclared = False }
    decision   = decide undeclared built.state

-- | C19 records consumed values, so later declarations cannot rewrite them.
basisDeclarations :: [Check]
basisDeclarations =
  [ expectEq "fixture/basis: declaration values are captured" (Right [(gateName, declaration)]) ((.integration.declarations) <$> built.execution)
  , expectEq "fixture/basis: declaration motion with applicable evidence stands down" (Left (RefusedBasisMoved [MovedDeclarations [(gateName, declaration)] [(gateName, unprobed)]])) (execute moved built.state built.decision)
  , expectEq "fixture/basis: recorded values survive later observations" (Just [(gateName, declaration)]) ((.declarations) <$> latestIntegration built.finalState)
  ]
  where
    built = build defaultScenario
    unprobed = declaration { Declaration.environment = Nothing }
    moved = built.executionObservation { Observations.declarations = [unprobed] }

-- | A permission names each prerequisite's closure beside the rest of its
-- basis (C19); a prerequisite that has not integrated refuses.
prerequisiteClosures :: [Check]
prerequisiteClosures =
  [ expectEq "fixture/prerequisites: the basis names each closure" (Just [(ChangeId "groundwork", EventId 50)]) (basisPrerequisites (decide integrated built.state))
  , expectEq "fixture/prerequisites: the integration records them" (Right [(ChangeId "groundwork", EventId 50)]) ((.integration.prerequisites) <$> execute integrated built.state (decide integrated built.state))
  , expectEq "fixture/prerequisites: an open prerequisite refuses" [RefusedBlockedBy [ChangeId "groundwork"]] (refusals open built.state)
  ]
  where
    built      = build defaultScenario
    integrated = built.observation { Observations.prerequisites = [(ChangeId "groundwork", Just (EventId 50))] }
    open       = built.observation { Observations.prerequisites = [(ChangeId "groundwork", Nothing)] }
    basisPrerequisites = \case
      Permitted basis -> Just basis.prerequisites
      Refused _       -> Nothing

-- | A history refused on more than one ground reports every ground, in the
-- model's presentation order, and the decision is the first of them.
everyGround :: [Check]
everyGround =
  [ expectEq "fixture/every-ground: both grounds reported" [RefusedBlockingFindings [FindingId 1], RefusedGates [GateFailed gateName (EventId 4)]] grounds
  , expectRefusedWith "fixture/every-ground: the finding decides" "blocking-findings" built.decision
  ]
  where
    built   = build defaultScenario { Scenario.blockingFinding = True, Scenario.gateMode = EvidenceFailing }
    grounds = refusals built.observation built.state

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
  , expectEq "fixture/audit: a contributor's approval is not recorded where self-approval is forbidden" (Left AuditAuditorNotIndependent) (admitAudit dangerPolicy closedState approving { Audit.actor = authorActor })
  , expectEq "fixture/audit: elsewhere it is recorded" (Right ()) (admitAudit openPolicy closedState approving { Audit.actor = authorActor })
  , expectEq "fixture/audit: an open change records no audit" (Left AuditWhileOpen) (admitAudit openPolicy openState openAudit)
  , expectTrue "fixture/audit: a refused audit is not in the ledger" "the builder must not record an audit the admission refuses" (null refusedAudit.finalState.audits)
  ]
  where
    debt        = Debt (DebtId 9) (EventId 900) (Just (PatchsetId 1)) Nothing "owed review" authorActor
    openState   = (build defaultScenario { Scenario.verdict = ChangesRequested }).state
    closedState = (build defaultScenario { Scenario.audit = Just (Approved, True) }).finalState
    refusedAudit = build defaultScenario { Scenario.reviewer = Nothing, Scenario.debts = [(1, Nothing)], Scenario.audit = Just (Approved, False) }
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
      BehaviourDecision (Right basis) -> Permitted basis
      _refusedOrOtherChannel          -> Refused RefusedNoApproval
