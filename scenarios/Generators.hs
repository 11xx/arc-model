{- | Building a scenario into a history, and reading what it reached.

'build' interprets a 'Scenario' into events with coherent references and
decides them; 'mutations' names the one-invalid-transition neighbours of a
valid history; 'featureOf' says which required class a built scenario
reached.
-}
module Generators
    ( module Scenario
    , authorActor
    , reviewActor
    , otherActor
    , Built(..)
    , build
    , observationsFor
    , executionObservations
    , flipPolicy
    , reverts
    , isIntegratable
    , mutations
    , Mutation(..)
    , Feature(..)
    , allFeatures
    , featureOf
    ) where

import Arc.Model
import Arc.Model.Ledger.Audit qualified as Audit
import Arc.Model.Ledger.Brief qualified as Brief
import Arc.Model.Ledger.Debt qualified as Debt
import Arc.Model.Ledger.DirtyTreeWaiver qualified as DirtyTreeWaiver
import Arc.Model.Ledger.Disposition qualified as Disposition
import Arc.Model.Ledger.ExternalVerdict qualified as ExternalVerdict
import Arc.Model.Ledger.Finding qualified as Finding
import Arc.Model.Ledger.Integration qualified as Integration
import Arc.Model.Ledger.ProbeRun qualified as ProbeRun
import Arc.Model.Ledger.Verdict qualified as Verdict
import Arc.Model.Ledger.Verification qualified as Verification
import Arc.Model.Observations qualified as Observations
import Scenario

import Data.List ( mapAccumL, sortOn )
import Data.List.NonEmpty ( NonEmpty(..) )
import Data.List.NonEmpty qualified as NE
import Data.Set qualified as Set


authorActor, reviewActor, otherActor :: ActorId
authorActor = ActorId "author"
reviewActor = ActorId "reviewer"
otherActor  = ActorId "other"

scenarioChange :: ChangeId
scenarioChange = ChangeId "demo"

buildGate :: GateName
buildGate = GateName "build"

buildDeclaration :: Declaration
buildDeclaration = Declaration
  { declarationId  = DeclarationId "build"
  , command        = "cargo build"
  , timeoutSeconds = 60
  , environment    = Just probe
  }

probe :: ProbeCommand
probe = ProbeCommand "probe"

hereEnvironment, elsewhereEnvironment :: EnvironmentId
hereEnvironment      = EnvironmentId "env-here"
elsewhereEnvironment = EnvironmentId "env-elsewhere"

-- | The revision the change started from, before any patchset.
baseRevision :: Revision
baseRevision = Revision "base"

acceptProbe :: ProbeName
acceptProbe = ProbeName "accept"

-- | What one scenario yields: the ledger, the observations, and the
-- decisions those two produce.
data Built = Built
  { events               :: ![Event]
  , finalEvents          :: ![Event]
  , observation          :: !Observations
  , executionObservation :: !Observations
  , state                :: !ChangeState
  , finalState           :: !ChangeState
  , decision             :: !Decision
  , execution            :: !(Either Refusal ExecutionPlan)
  , redecidedState       :: !ChangeState  -- ^ The history had the integration been decided afresh under the execution observations.
  }

build :: Scenario -> Built
build scenario = Built
  { events               = events
  , finalEvents          = finalEvents
  , observation          = observations
  , executionObservation = executionObs
  , state                = state
  , finalState           = replay scenarioChange finalEvents
  , decision             = decision
  , execution            = execute executionObs state decision
  , redecidedState       = replay scenarioChange (events <> effectsOf (decide executionObs state))
  }
  where
    patchsets = patchsetsFor scenario briefEvent
    latest    = NE.last patchsets
    verdictTarget
      | scenario.verdictOnFirst && scenario.patchsets > 1 = PatchsetId 1
      | otherwise                                         = latest.patchsetId
    -- verdicts are recorded as the plan makes them, patchset by patchset,
    -- the earlier verdicts on a patchset before the scenario's own; each
    -- supersedes the one recorded before it, as a review does by default
    verdictEvents = map snd . sortOn fst $
      [ (index, verdictBy pick kind (PatchsetId index) Nothing) | (index, pick, kind) <- scenario.priorVerdicts ]
      <> [ (ordinalOf verdictTarget, verdictBy pick scenario.verdict verdictTarget provisional) | pick <- maybe [] pure scenario.reviewer ]
    provisional = if scenario.provisional then Just "provisional" else Nothing
    ordinalOf (PatchsetId index) = index
    verdictBy pick kind patchset provisionally = VerdictRecorded Verdict
      { event       = EventId 0
      , patchset    = patchset
      , kind        = kind
      , actor       = actorForPick pick
      , onBehalfOf  = Nothing
      , assumed     = pick == ActorAssumed
      , provisional = provisionally
      , relation    = Supersedes
      , supersedes  = Nothing
      }
    -- a rejection of the head is followed by the closure arc records with
    -- it: the change is abandoned, with the decision as its reason
    externalEvents = concat
      [ [ ExternalVerdictRecorded ExternalVerdict
            { event     = EventId 0
            , revision  = latest.revision
            , kind      = kind
            , reference = "upstream/1"
            }
        | Just kind <- [scenario.externalVerdict]
        ]
      , [ ChangeClosed ClosedAbandoned | scenario.externalVerdict == Just ExternalRejected ]
      ]
    findingEvents
      | scenario.blockingFinding
          = FindingRecorded Finding
              { event     = EventId 0
              , findingId = FindingId 1
              , patchset  = verdictTarget
              , actor     = otherActor
              , blocking  = True
              , audit     = False
              }
          : [ FindingDisposed Disposition
                { event    = EventId 0
                , finding  = FindingId 1
                , resolved = True
                }
            | scenario.resolveFinding
            ]
      | otherwise = []
    debtEvents =
      [ DebtDeclared Debt
          { debtId       = DebtId ordinal
          , event        = EventId 0
          , patchset     = Just (PatchsetId index)
          , declaredKind = kind
          , reason       = "declared coverage"
          , actor        = authorActor
          }
      | (ordinal, (index, kind)) <- zip [1 ..] scenario.debts
      ]
    -- runs are recorded as the plan makes them: patchset by patchset, the
    -- scenario's own run first
    verificationEvents = concat
      [ [ primaryRun mode | patchset.ordinal == verifiedAt.ordinal, mode <- [scenario.gateMode], mode /= EvidenceOmitted ]
        <> [ furtherRun patchset result | (index, result) <- scenario.gateRuns, index == patchset.ordinal ]
      | patchset <- NE.toList patchsets
      ]
    primaryRun mode = VerificationRecorded Verification
      { event       = EventId 0
      , gate        = buildGate
      , declaration = buildDeclaration.declarationId
      , shape       = shapeFor mode
      , revision    = verifiedAt.revision
      , tree        = treeFor mode
      , result      = if mode == EvidenceFailing then GateFail else GatePass
      , execution   = RanLocally
      , answers     = Just (FailureLabel "known-failure")
      , readable    = mode /= EvidenceRecordUnreadable
      , environment = environmentFor mode
      , worktree    = Observed (if scenario.worktree == WorktreeClean then CleanWorktree else DirtyWorktree)
      }
    -- a further run is clean, at the patchset's own head, in the
    -- environment here, under the declaration every run was recorded under
    furtherRun patchset result = VerificationRecorded Verification
      { event       = EventId 0
      , gate        = buildGate
      , declaration = buildDeclaration.declarationId
      , shape       = shapeFor scenario.gateMode
      , revision    = patchset.revision
      , tree        = patchset.tree
      , result      = result
      , execution   = RanLocally
      , answers     = Nothing
      , readable    = True
      , environment = Just hereEnvironment
      , worktree    = Observed CleanWorktree
      }
    -- the patchset whose head the gate ran at: the one before the latest
    -- when the evidence is for another tree and there is one
    verifiedAt
      | scenario.gateMode == EvidenceOtherTree, (earlier : _) <- reverse (NE.init patchsets) = earlier
      | otherwise = latest
    shapeFor = \case
      EvidenceShapeMoved -> DeclarationShape "cargo build --locked" 60
      _unchanged     -> declarationShape buildDeclaration
    -- a run against the merge records the merge's tree
    treeFor = \case
      EvidenceOtherTree -> TreeId "tree-elsewhere"
      _here
        | scenario.targetMode == TargetBehindEvaluated -> mergedTree
        | otherwise                                    -> latest.tree
    environmentFor = \case
      EvidenceOtherEnvironment      -> Just elsewhereEnvironment
      EvidenceUnrecordedEnvironment -> Nothing
      _here                     -> Just hereEnvironment
    claimEvents = concat
      [ [ ClaimStarted (Claim (ClaimId 1) authorActor False)
        , ClaimExpired (ClaimId 1)
        ]
      | scenario.episodeExpired
      ]
    iteratingEvents = [ IteratingChanged True | scenario.iterating ]
    waiverEvents =
      [ DirtyTreeWaived DirtyTreeWaiver { event = EventId 0, revision = revision }
      | revision <- case scenario.worktree of
          WorktreeDirtyWaived          | scenario.gateMode /= EvidenceOmitted -> [verifiedAt.revision]
          WorktreeDirtyWaivedElsewhere -> [baseRevision]
          _unwaived                    -> []
      ]
    -- the brief is recorded after every other event, so its identifier is
    -- the next one and the events before it keep theirs
    precedingEvents = concat
      [ map PatchsetRecorded (NE.toList patchsets)
      , verdictEvents
      , externalEvents
      , findingEvents
      , debtEvents
      , verificationEvents
      , claimEvents
      , waiverEvents
      , iteratingEvents
      ]
    probeEvents = case briefFor scenario of
      Nothing        -> []
      Just (base, _) ->
        BriefRecorded Brief { event = briefEvent, base = Just base, probes = [acceptProbe] }
        : [ ProbeRunRecorded ProbeRun
              { event    = EventId 0
              , brief    = briefEvent
              , probe    = acceptProbe
              , phase    = phase
              , revision = revision
              , result   = result
              }
          | (phase, revision, result) <- probeRunsFor scenario base latest.revision
          ]
    briefEvent = EventId (length precedingEvents + 1)
    events = assignIds (precedingEvents <> probeEvents)
    observations = observationsForOf patchsets scenario
    mergedTree = TreeId "merged"
    -- a target that moves puts the head behind it, so what would ship is a
    -- new merge nobody evaluated; a head that conflicts still conflicts,
    -- and a change without a branch has nothing to merge
    targetMoves  = scenario.targetAfter && observations.targetRelation /= HeadConflictsWithTarget && not scenario.branchMissing
    executionObs = observations
      { Observations.target         = if scenario.targetAfter then Revision "target-2" else observations.target
      , Observations.targetRelation = if targetMoves then HeadBehindTarget else observations.targetRelation
      , Observations.evaluatedTree  = if targetMoves then TreeId "merged-after" else observations.evaluatedTree
      , Observations.policy         = if scenario.policyAfter then flipPolicy observations.policy else observations.policy
      , Observations.authority      = if scenario.authorityWithheld then AuthorityWithheld else AuthorityHeld
      }
    state    = replay scenarioChange events
    decision = decide observations state
    -- an audit is recorded only where arc would record it: after an
    -- integration, and never as a contributor's approval where policy
    -- forbids self-approval
    effectEvents = effectsOf decision
    effectsOf decided = case decided of
      Permitted _
        | Right plan <- execute executionObs state decided
          -> let integration = IntegrationRecorded plan.integration { Integration.event = EventId 900 }
             in integration : admittedAudits integration
      _refused -> []
    admittedAudits integration = case auditEvents of
      AuditRecorded audit : _
        | Right () <- admitAudit observations.policy (replay scenarioChange (events <> [integration])) audit
          -> auditEvents
      _refusedOrNone -> []
    auditEvents = case scenario.audit of
      Nothing                  -> []
      Just (kind, independent) ->
        AuditRecorded Audit
          { event    = EventId 901
          , revision = latest.revision
          , kind     = kind
          , actor    = if independent then otherActor else authorActor
          , assumed  = False
          , findings = [ FindingId 2 | kind == ChangesRequested ]
          }
        : [ FindingRecorded Finding
              { event     = EventId 902
              , findingId = FindingId 2
              , patchset  = latest.patchsetId
              , actor     = if independent then otherActor else authorActor
              , blocking  = True
              , audit     = True
              }
          | kind == ChangesRequested
          ]
    finalEvents = events <> effectEvents

-- | The patchsets a scenario records: one per ordinal, on its own revision
-- and tree, all by the author, with the extra contributor declared on each
-- when the scenario asks for one, and bound to the brief from the patchset
-- recorded after it. A latest patchset that reverts the one before it
-- returns to the tree of the patchset before that.
patchsetsFor :: Scenario -> EventId -> NonEmpty Patchset
patchsetsFor scenario briefEvent = mkPatchset <$> (1 :| [2 .. scenario.patchsets])
  where
    mkPatchset index = Patchset
      { patchsetId   = PatchsetId index
      , ordinal      = index
      , revision     = Revision ("rev" <> show index)
      , tree         = TreeId ("tree" <> show (treeIndex index))
      , author       = authorActor
      , contributors = contributors
      , brief        = case briefFor scenario of
          Just (_, from) | index >= from -> Just briefEvent
          _unbound                       -> Nothing
      }
    contributors
      | scenario.extraContributor = Set.fromList [authorActor, otherActor]
      | otherwise                 = Set.singleton authorActor
    treeIndex index
      | reverts scenario, index == scenario.patchsets = index - 2
      | otherwise                                     = index

-- | Whether the latest patchset reverts the one before it: only where there
-- is an earlier patchset for it to return to.
reverts :: Scenario -> Bool
reverts scenario = scenario.revertLatest && scenario.patchsets >= 3

{- | The brief a scenario records, as its base and the first patchset
recorded under it. A probe that can be discharged is based where the change
started; one that cannot is based at the latest patchset's head, recorded
just before that patchset.
-}
briefFor :: Scenario -> Maybe (Revision, Int)
briefFor scenario = case scenario.probe of
  ProbeNone            -> Nothing
  ProbeUndischargeable -> Just (Revision ("rev" <> show scenario.patchsets), scenario.patchsets)
  _based               -> Just (baseRevision, 1)

-- | The probe runs a scenario records, as phase, revision, and result.
probeRunsFor :: Scenario -> Revision -> Revision -> [(ProbePhase, Revision, GateResult)]
probeRunsFor scenario base final = case scenario.probe of
  ProbeNone            -> []
  ProbeDischarged      -> [(Baseline, base, GateFail), (Final, final, GatePass)]
  ProbeBaselinePassed  -> [(Baseline, base, GatePass), (Final, final, GatePass)]
  ProbeFinalMissing    -> [(Baseline, base, GateFail)]
  ProbeFinalFailed     -> [(Baseline, base, GateFail), (Final, final, GateFail)]
  ProbeUndischargeable -> [(Baseline, base, GateFail), (Final, final, GatePass)]

observationsFor :: Scenario -> Observations
observationsFor scenario = (build scenario).observation

{- | The decision-time observations: the probe yields the local identity
unless the scenario makes it fail, and authority is held; the execution
observations move what the scenario says moves. A change behind its target
evaluates the merge of whatever head is observed, so a moved head is a
different merge; a change without a branch has no head to merge at all.
-}
observationsForOf :: NonEmpty Patchset -> Scenario -> Observations
observationsForOf patchsets scenario = Observations
  { change           = scenarioChange
  , head             = observedHead
  , targetBranch     = TargetBranch "main"
  , target           = Revision "target-1"
  , targetRelation   = relation
  , evaluatedTree    = case relation of
      HeadBehindTarget -> TreeId (if scenario.headMoved then "merged-moved" else "merged")
      _headTree        -> latest.tree
  , declarations     = [buildDeclaration]
  , conflictingGates = [ buildGate | scenario.conflictingGates ]
  , requiredGates    = [(buildGate, buildDeclaration.declarationId)]
  , environments     = [(probe, if scenario.gateMode == EvidenceProbeFailed then Omitted else Observed hereEnvironment)]
  , policy           = scenario.policy
  , prerequisites    = []
  , invokerDeclared  = True
  , authority        = AuthorityHeld
  }
  where
    latest = NE.last patchsets
    observedHead
      | scenario.branchMissing = Omitted
      | scenario.headMoved     = Observed (Revision "rev-moved")
      | otherwise              = Observed latest.revision
    relation
      | scenario.branchMissing = HeadContainsTarget
      | otherwise = case scenario.targetMode of
          TargetContained       -> HeadContainsTarget
          TargetBehind          -> HeadBehindTarget
          TargetBehindEvaluated -> HeadBehindTarget
          TargetConflicting     -> HeadConflictsWithTarget

executionObservations :: Scenario -> Observations
executionObservations scenario = (build scenario).executionObservation

-- | The policy a moved observation lands on: whichever declared policy is
-- not the one the decision rested on.
flipPolicy :: Policy -> Policy
flipPolicy policy = if policy == openPolicy then dangerPolicy else openPolicy

actorForPick :: ActorPick -> ActorId
actorForPick ActorIndependent = reviewActor
actorForPick ActorContributor = authorActor
actorForPick ActorAssumed     = reviewActor

-- | Assign one event id per recorded event, in recording order. Each verdict
-- supersedes the verdict recorded before it, the tip it observed.
assignIds :: [Event] -> [Event]
assignIds = snd . mapAccumL withId (EventId 1, Nothing)
  where
    withId (eventId@(EventId next), tip) event = ((EventId (next + 1), tipAfter), number eventId tip event)
      where
        tipAfter = case event of
          VerdictRecorded _ -> Just eventId
          _other            -> tip
    number eventId tip = \case
      VerdictRecorded value         -> VerdictRecorded value { Verdict.event = eventId, Verdict.supersedes = tip }
      ExternalVerdictRecorded value -> ExternalVerdictRecorded value { ExternalVerdict.event = eventId }
      FindingRecorded value         -> FindingRecorded value { Finding.event = eventId }
      FindingDisposed value         -> FindingDisposed value { Disposition.event = eventId }
      VerificationRecorded value    -> VerificationRecorded value { Verification.event = eventId }
      DebtDeclared value            -> DebtDeclared value { Debt.event = eventId }
      AuditRecorded value           -> AuditRecorded value { Audit.event = eventId }
      IntegrationRecorded value     -> IntegrationRecorded value { Integration.event = eventId }
      DirtyTreeWaived value         -> DirtyTreeWaived value { DirtyTreeWaiver.event = eventId }
      BriefRecorded value           -> BriefRecorded value { Brief.event = eventId }
      ProbeRunRecorded value        -> ProbeRunRecorded value { ProbeRun.event = eventId }
      unnumbered                    -> unnumbered

{- | Histories an integration would permit: an independent approval, a
waiver bound to the latest patchset, or an external approval where no
independent review is owed; covered gate evidence, from a clean tree or a
dirty one waived at its own revision, and at the merge when the target
moved; no open finding, no moved head, no verdict bound to an older
patchset, no external refusal, no probe left undischarged, a branch to
integrate, one gate declaration, and the authority to act.
-}
isIntegratable :: Scenario -> Bool
isIntegratable scenario
  = authorized
  && scenario.gateMode == EvidenceCovered
  && not scenario.blockingFinding
  && not scenario.headMoved
  && not (scenario.verdictOnFirst && scenario.patchsets > 1)
  && scenario.externalVerdict `elem` [Nothing, Just ExternalApproved]
  && not scenario.authorityWithheld
  && scenario.worktree `elem` [WorktreeClean, WorktreeDirtyWaived]
  && scenario.targetMode `elem` [TargetContained, TargetBehindEvaluated]
  && scenario.probe `elem` [ProbeNone, ProbeDischarged]
  && not scenario.branchMissing
  && not scenario.conflictingGates
  && not scenario.iterating
  && all ((== GatePass) . snd) scenario.gateRuns
  where
    authorized = case scenario.reviewer of
      Just ActorIndependent -> scenario.verdict == Approved
      Just _contributing    -> False
      Nothing               -> debtBindsLatest scenario || externallyApproved
    externallyApproved
      = scenario.externalVerdict == Just ExternalApproved
      && not (scenario.policy.independentVerdictRequired && scenario.policy.forbidSelfApproval)

-- | One invalidating transition applied to a valid history. Each mutation
-- removes exactly one load-bearing fact.
data Mutation = Mutation
  { name     :: !String
  , scenario :: !Scenario
  }

-- | Whether a debt of the scenario is bound to the newest patchset, where it
-- would rescue a rejected self-approval.
debtBindsLatest :: Scenario -> Bool
debtBindsLatest scenario = any ((== scenario.patchsets) . fst) scenario.debts

mutations :: Scenario -> [Mutation]
mutations scenario = concat
  [ [ Mutation "gate-omitted" scenario { Scenario.gateMode = EvidenceOmitted }                              | covered ]
  , [ Mutation "gate-failed" scenario { Scenario.gateMode = EvidenceFailing }                                | covered ]
  , [ Mutation "gate-elsewhere" scenario { Scenario.gateMode = EvidenceOtherTree }                          | covered ]
  , [ Mutation "gate-declaration-changed" scenario { Scenario.gateMode = EvidenceShapeMoved }               | covered ]
  , [ Mutation "gate-other-environment" scenario { Scenario.gateMode = EvidenceOtherEnvironment }           | covered ]
  , [ Mutation "gate-environment-unrecorded" scenario { Scenario.gateMode = EvidenceUnrecordedEnvironment } | covered ]
  , [ Mutation "gate-probe-failed" scenario { Scenario.gateMode = EvidenceProbeFailed }                     | covered ]
  , [ Mutation "gate-evidence-unreadable" scenario { Scenario.gateMode = EvidenceRecordUnreadable }               | covered ]
  , [ Mutation "head-moved" scenario { Scenario.headMoved = True }                                      | not scenario.headMoved ]
  , [ Mutation "target-moved" scenario { Scenario.targetAfter = True }                                  | not scenario.targetAfter ]
  , [ Mutation "policy-moved" scenario { Scenario.policyAfter = True }                                  | not scenario.policyAfter ]
  , [ Mutation "authority-withheld" scenario { Scenario.authorityWithheld = True }                      | not scenario.authorityWithheld ]
  , [ Mutation "external-verdict-refused" scenario { Scenario.externalVerdict = Just ExternalChangesRequested }
    | scenario.externalVerdict /= Just ExternalChangesRequested
    ]
  , [ Mutation "finding-opened" scenario { Scenario.blockingFinding = True }                            | reviewed, not scenario.blockingFinding ]
  , [ Mutation "verdict-refused" scenario { Scenario.verdict = ChangesRequested }                       | reviewed, scenario.verdict == Approved ]
  , [ Mutation "review-patchset-stale" scenario { Scenario.verdictOnFirst = True }
    | reviewed
    , scenario.patchsets > 1
    , not (debtBindsLatest scenario)
    , scenario.externalVerdict == Nothing
    ]
  , [ Mutation "reviewer-is-contributor" scenario { Scenario.reviewer = Just ActorContributor }
    | scenario.reviewer == Just ActorIndependent
    , scenario.policy.independentVerdictRequired
    , scenario.policy.forbidSelfApproval
    , not (debtBindsLatest scenario)
    ]
  , [ Mutation "waiver-expired" scenario { Scenario.patchsets = scenario.patchsets + 1 }
    | not (null scenario.debts)
    , scenario.reviewer == Nothing
    , scenario.externalVerdict == Nothing
    ]
  , [ Mutation "evidence-dirty" scenario { Scenario.worktree = WorktreeDirty }                           | covered, scenario.worktree /= WorktreeDirty ]
  , [ Mutation "merge-unevaluated" scenario { Scenario.targetMode = TargetBehind }                      | scenario.targetMode /= TargetBehind ]
  , [ Mutation "target-conflicting" scenario { Scenario.targetMode = TargetConflicting }                | scenario.targetMode /= TargetConflicting ]
  , [ Mutation "probe-baseline-passed" scenario { Scenario.probe = ProbeBaselinePassed }                | scenario.probe /= ProbeBaselinePassed ]
  , [ Mutation "branch-missing" scenario { Scenario.branchMissing = True }                              | not scenario.branchMissing ]
  , [ Mutation "gates-conflict" scenario { Scenario.conflictingGates = True }                           | not scenario.conflictingGates ]
  ]
  where
    -- a further run could answer where the scenario's own run no longer does
    covered  = scenario.gateMode == EvidenceCovered && null scenario.gateRuns
    reviewed = scenario.reviewer /= Nothing

-- | The behaviours a generated scenario is expected to reach. A run that
-- never reaches one is reported so the suite cannot pass on trivial inputs.
data Feature = FeaturePermitted
             | FeatureWaived
             | FeatureExternallyAuthorized
             | FeatureExternalRefused
             | FeatureSelfApprovalRefused
             | FeatureGatesRefused
             | FeatureGateFailed
             | FeatureEnvironmentRefused
             | FeatureVerdictStands
             | FeatureHeadMoved
             | FeatureTargetMoved
             | FeaturePolicyMoved
             | FeatureAuthorityWithheld
             | FeatureDebtUnused
             | FeatureUnknownObservation
             | FeatureAuditFulfilledRead
             | FeatureAuditNegativeNotApproved
             | FeatureEpisodeExpired
             | FeatureEqualTreeContributorVariation
             | FeatureDirtyRefused
             | FeatureDirtyWaived
             | FeatureMergedTreeUnevaluated
             | FeatureMergeEvaluated
             | FeatureNeedsRebase
             | FeatureProbesRefused
             | FeatureProbeDischarged
             | FeatureBranchMissing
             | FeatureConflictingGates
             | FeatureSeveralVerdicts
             | FeatureSeveralDebts
             | FeatureWaiverPerPatchset
             | FeatureOlderEvidenceAnswers
             | FeatureEvidenceInherited
             | FeatureIterating
             | FeatureRepairUnreadDerived
  deriving stock (Eq, Ord, Show, Enum, Bounded)

allFeatures :: [Feature]
allFeatures = [minBound .. maxBound]

-- | Which of the required scenario classes a built scenario reached.
featureOf :: Scenario -> Built -> Feature -> Bool
featureOf scenario built = \case
  FeaturePermitted                     -> isPermitted built.decision
  FeatureWaived                        -> permittedBy isWaiver
  FeatureExternallyAuthorized          -> permittedBy isExternal
  FeatureExternalRefused               -> refusedWith "external-verdict-stands"
  FeatureSelfApprovalRefused           -> refusedWith "self-approval"
  FeatureGatesRefused                  -> refusedWith "gates"
  FeatureGateFailed                    -> gateRefusedBy isGateFailed
  FeatureEnvironmentRefused            -> gateRefusedBy isEnvironmentRefusal
  FeatureVerdictStands                 -> refusedWith "verdict-stands"
  FeatureHeadMoved                     -> refusedWith "head-moved"
  FeatureTargetMoved                   -> movedFact isMovedTarget
  FeaturePolicyMoved                   -> movedFact isMovedPolicy
  FeatureAuthorityWithheld             -> built.execution == Left RefusedAuthorityWithheld
  FeatureDebtUnused                    -> permittedBy isUnusedDebt
  FeatureUnknownObservation            -> scenario.gateMode `elem` [EvidenceOmitted, EvidenceRecordUnreadable]
  FeatureAuditFulfilledRead            -> coverage.read /= Nothing
  FeatureAuditNegativeNotApproved      -> coverage.verdict == Just ChangesRequested && not coverage.approved
  FeatureEpisodeExpired                -> any (.expired) built.finalState.claims
  FeatureEqualTreeContributorVariation -> scenario.extraContributor
  FeatureDirtyRefused                  -> any (\case RefusedGates refused -> GateEvaluatedDirtyTree buildGate `elem` refused; _other -> False) grounds
  FeatureDirtyWaived                   -> isPermitted built.decision && scenario.worktree == WorktreeDirtyWaived
  FeatureMergedTreeUnevaluated         -> groundedOn "merged-tree-unevaluated"
  FeatureMergeEvaluated                -> isPermitted built.decision && built.observation.targetRelation == HeadBehindTarget
  FeatureNeedsRebase                   -> groundedOn "needs-rebase"
  FeatureProbesRefused                 -> groundedOn "acceptance-probes"
  FeatureProbeDischarged               -> isPermitted built.decision && scenario.probe == ProbeDischarged
  FeatureBranchMissing                 -> groundedOn "branch-missing"
  FeatureConflictingGates              -> groundedOn "conflicting-declarations"
  FeatureSeveralVerdicts               -> length built.state.verdicts >= 2
  FeatureSeveralDebts                  -> length built.state.debts >= 2
  -- a debt on an earlier patchset beside the latest one's waiver, which
  -- is the one that authorizes
  FeatureWaiverPerPatchset             -> permittedBy isWaiver && any (\debt -> debt.patchset /= latestId) built.state.debts
  -- the evidence that answers is older than a record under another key
  FeatureOlderEvidenceAnswers          -> any (\(_, event, _) -> Just event /= newestRun) answering
  -- the evidence that answers was recorded at an earlier commit with the
  -- same tree
  FeatureEvidenceInherited             -> any (\(_, event, _) -> any (\v -> v.event == event && Just v.revision /= latestRevision) built.state.verifications) answering
  FeatureIterating                     -> groundedOn "iterating"
  FeatureRepairUnreadDerived           -> reviewObligation built.state == OwedReview RepairUnread || any (\debt -> debt.declaredKind == Nothing && debtKindFor built.state debt == RepairUnread) built.state.debts
  where
    latest         = latestPatchset built.state
    latestId       = (.patchsetId) <$> latest
    latestRevision = (.revision) <$> latest
    newestRun      = (.event) <$> newest built.state.verifications
    answering      = either (const []) id (gateEvidence built.observation built.state)
    -- every ground, so a fact the first ground would hide is still counted
    grounds     = refusals built.observation built.state
    groundedOn tag = any ((== tag) . refusalTag) grounds
    coverage = coverageAfterIntegration built.finalState
    permittedBy predicate = case built.decision of
      Permitted basis -> predicate basis.authorization
      Refused _       -> False
    refusedWith tag = case built.decision of
      Refused refusal -> refusalTag refusal == tag
      Permitted _     -> False
    gateRefusedBy predicate = case built.decision of
      Refused (RefusedGates refused) -> any predicate refused
      _otherwise                     -> False
    movedFact predicate = case built.execution of
      Left (RefusedBasisMoved facts) -> any predicate facts
      _stood                         -> False
    isWaiver = \case
      AuthorizedByWaiver _               -> True
      AuthorizedByVerdictUnderWaiver _ _ -> True
      _unwaived                          -> False
    isExternal = \case
      AuthorizedByExternalVerdict _ -> True
      _local                        -> False
    isUnusedDebt = \case
      AuthorizedByVerdict _ -> any ((== DebtId 1) . (.debtId)) built.state.debts
      _waived               -> False
    isGateFailed = \case
      GateFailed _ _ -> True
      _other         -> False
    isEnvironmentRefusal = \case
      GateEvaluatedOtherEnvironment {} -> True
      GateEnvironmentUnrecorded _      -> True
      GateEnvironmentUnobserved _      -> True
      _other                           -> False
    isMovedTarget = \case
      MovedTarget _ _ -> True
      _other          -> False
    isMovedPolicy = \case
      MovedPolicy _ _ -> True
      _other          -> False
