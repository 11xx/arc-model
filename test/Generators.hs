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
    , isIntegratable
    , mutations
    , Mutation(..)
    , Feature(..)
    , allFeatures
    , featureOf
    ) where

import Arc.Model
import Arc.Model.Ledger.Audit qualified as Audit
import Arc.Model.Ledger.Debt qualified as Debt
import Arc.Model.Ledger.Disposition qualified as Disposition
import Arc.Model.Ledger.ExternalVerdict qualified as ExternalVerdict
import Arc.Model.Ledger.Finding qualified as Finding
import Arc.Model.Ledger.Integration qualified as Integration
import Arc.Model.Ledger.Verdict qualified as Verdict
import Arc.Model.Ledger.Verification qualified as Verification
import Arc.Model.Observations qualified as Observations
import Scenario

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
  }
  where
    patchsets = patchsetsFor scenario
    latest    = NE.last patchsets
    verdictTarget
      | scenario.verdictOnFirst && scenario.patchsets > 1 = PatchsetId 1
      | otherwise                                         = latest.patchsetId
    verdictEvents =
      [ VerdictRecorded Verdict
          { event       = EventId 0
          , patchset    = verdictTarget
          , kind        = scenario.verdict
          , actor       = actorForPick pick
          , onBehalfOf  = Nothing
          , assumed     = pick == ActorAssumed
          , provisional = if scenario.provisional then Just "provisional" else Nothing
          , relation    = Supersedes
          , supersedes  = Nothing
          }
      | pick <- maybe [] pure scenario.reviewer
      ]
    externalEvents =
      [ ExternalVerdictRecorded ExternalVerdict
          { event     = EventId 0
          , revision  = latest.revision
          , kind      = kind
          , reference = "upstream/1"
          }
      | Just kind <- [scenario.externalVerdict]
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
          { debtId       = DebtId 1
          , event        = EventId 0
          , patchset     = Just (PatchsetId index)
          , declaredKind = kind
          , reason       = "declared coverage"
          , actor        = authorActor
          }
      | (index, kind) <- maybe [] pure scenario.debt
      ]
    verificationEvents = case scenario.gateMode of
      EvidenceOmitted -> []
      mode        ->
        [ VerificationRecorded Verification
            { event       = EventId 0
            , gate        = buildGate
            , declaration = buildDeclaration.declarationId
            , shape       = shapeFor mode
            , tree        = treeFor mode
            , result      = if mode == EvidenceFailing then GateFail else GatePass
            , execution   = RanLocally
            , answers     = Just (FailureLabel "known-failure")
            , readable    = mode /= EvidenceRecordUnreadable
            , environment = environmentFor mode
            }
        ]
    shapeFor = \case
      EvidenceShapeMoved -> DeclarationShape "cargo build --locked" 60
      _unchanged     -> declarationShape buildDeclaration
    treeFor = \case
      EvidenceOtherTree -> TreeId "tree-elsewhere"
      _here         -> latest.tree
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
    events = assignIds
      ( map PatchsetRecorded (NE.toList patchsets)
      <> verdictEvents
      <> externalEvents
      <> findingEvents
      <> debtEvents
      <> verificationEvents
      <> claimEvents
      )
    observations = observationsForOf patchsets scenario
    executionObs = observations
      { Observations.target    = if scenario.targetAfter then Revision "target-2" else observations.target
      , Observations.policy    = if scenario.policyAfter then flipPolicy observations.policy else observations.policy
      , Observations.authority = if scenario.authorityWithheld then AuthorityWithheld else AuthorityHeld
      }
    state    = replay scenarioChange events
    decision = decide observations state
    effectEvents = case decision of
      Permitted _
        | Right plan <- execute executionObs state decision
          -> IntegrationRecorded plan.integration { Integration.event = EventId 900 } : auditEvents
      _refused -> auditEvents
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
-- when the scenario asks for one.
patchsetsFor :: Scenario -> NonEmpty Patchset
patchsetsFor scenario = mkPatchset <$> (1 :| [2 .. scenario.patchsets])
  where
    mkPatchset index = Patchset
      { patchsetId   = PatchsetId index
      , ordinal      = index
      , revision     = Revision ("rev" <> show index)
      , tree         = TreeId ("tree" <> show index)
      , author       = authorActor
      , contributors = contributors
      }
    contributors
      | scenario.extraContributor = Set.fromList [authorActor, otherActor]
      | otherwise                 = Set.singleton authorActor

observationsFor :: Scenario -> Observations
observationsFor scenario = observationsForOf (patchsetsFor scenario) scenario

-- | The decision-time observations: the probe yields the local identity
-- unless the scenario makes it fail, and authority is held; the execution
-- observations move what the scenario says moves.
observationsForOf :: NonEmpty Patchset -> Scenario -> Observations
observationsForOf patchsets scenario = Observations
  { change          = scenarioChange
  , head            = if scenario.headMoved then Revision "rev-moved" else latest.revision
  , targetBranch    = TargetBranch "main"
  , target          = Revision "target-1"
  , evaluatedTree   = latest.tree
  , declarations    = [buildDeclaration]
  , requiredGates   = [(buildGate, buildDeclaration.declarationId)]
  , environments    = [(probe, if scenario.gateMode == EvidenceProbeFailed then Omitted else Observed hereEnvironment)]
  , policy          = scenario.policy
  , blockedBy       = []
  , invokerDeclared = True
  , authority       = AuthorityHeld
  }
  where
    latest = NE.last patchsets

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

-- | Assign one event id per recorded event, in recording order.
assignIds :: [Event] -> [Event]
assignIds = zipWith withId [EventId 1 ..]
  where
    withId eventId = \case
      VerdictRecorded value         -> VerdictRecorded value { Verdict.event = eventId }
      ExternalVerdictRecorded value -> ExternalVerdictRecorded value { ExternalVerdict.event = eventId }
      FindingRecorded value         -> FindingRecorded value { Finding.event = eventId }
      FindingDisposed value         -> FindingDisposed value { Disposition.event = eventId }
      VerificationRecorded value    -> VerificationRecorded value { Verification.event = eventId }
      DebtDeclared value            -> DebtDeclared value { Debt.event = eventId }
      AuditRecorded value           -> AuditRecorded value { Audit.event = eventId }
      IntegrationRecorded value     -> IntegrationRecorded value { Integration.event = eventId }
      unnumbered                    -> unnumbered

{- | Histories an integration would permit: an independent approval, a
waiver bound to the latest patchset, or an external approval where no
independent review is owed; covered gate evidence; no open finding, no
moved head, no verdict bound to an older patchset, no external refusal,
and the authority to act.
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
  where
    authorized = case scenario.reviewer of
      Just ActorIndependent -> scenario.verdict == Approved
      Just _contributing    -> False
      Nothing               -> scenario.debt /= Nothing || externallyApproved
    externallyApproved
      = scenario.externalVerdict == Just ExternalApproved
      && not (scenario.policy.independentVerdictRequired && scenario.policy.forbidSelfApproval)

-- | One invalidating transition applied to a valid history. Each mutation
-- removes exactly one load-bearing fact.
data Mutation = Mutation
  { name     :: !String
  , scenario :: !Scenario
  }

-- | Whether the scenario's debt is bound to the newest patchset, where it
-- would rescue a rejected self-approval.
debtBindsLatest :: Scenario -> Bool
debtBindsLatest scenario = case scenario.debt of
  Just (index, _) -> index == scenario.patchsets
  Nothing         -> False

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
    | scenario.debt /= Nothing
    , scenario.reviewer == Nothing
    , scenario.externalVerdict == Nothing
    ]
  ]
  where
    covered  = scenario.gateMode == EvidenceCovered
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
  where
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
