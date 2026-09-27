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
      GateOmitted -> []
      mode        ->
        [ VerificationRecorded Verification
            { event       = EventId 0
            , gate        = GateName "build"
            , declaration = DeclarationId "build"
            , shape       = shapeFor mode
            , tree        = treeFor mode
            , result      = GatePass
            , execution   = RanLocally
            , answers     = Just (FailureLabel "known-failure")
            , readable    = mode /= GateUnreadable
            }
        ]
    shapeFor = \case
      GateShapeMoved -> DeclarationShape "cargo build --locked" 60
      _unchanged     -> DeclarationShape "cargo build" 60
    treeFor = \case
      GateOtherTree -> TreeId "tree-elsewhere"
      _here         -> latest.tree
    claimEvents = concat
      [ [ ClaimStarted (Claim (ClaimId 1) authorActor False)
        , ClaimExpired (ClaimId 1)
        ]
      | scenario.episodeExpired
      ]
    events = assignIds
      ( map PatchsetRecorded (NE.toList patchsets)
      <> verdictEvents
      <> findingEvents
      <> debtEvents
      <> verificationEvents
      <> claimEvents
      )
    observations = observationsForOf patchsets scenario.headMoved scenario.policy
    executionObs = observations
      { Observations.target = if scenario.targetAfter then Revision "target-2" else observations.target
      , Observations.policy = if scenario.policyAfter then flipPolicy observations.policy else observations.policy
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
observationsFor scenario = observationsForOf (patchsetsFor scenario) scenario.headMoved scenario.policy

observationsForOf :: NonEmpty Patchset -> Bool -> Policy -> Observations
observationsForOf patchsets headMoved policy = Observations
  { change          = scenarioChange
  , head            = if headMoved then Revision "rev-moved" else latest.revision
  , targetBranch    = TargetBranch "main"
  , target          = Revision "target-1"
  , evaluatedTree   = latest.tree
  , declarations    = [Declaration (DeclarationId "build") "cargo build" 60]
  , requiredGates   = [(GateName "build", DeclarationId "build")]
  , policy          = policy
  , blockedBy       = []
  , invokerDeclared = True
  }
  where
    latest = NE.last patchsets

executionObservations :: Scenario -> Observations
executionObservations scenario = base
  { Observations.target = if scenario.targetAfter then Revision "target-2" else base.target
  , Observations.policy = if scenario.policyAfter then flipPolicy base.policy else base.policy
  }
  where
    base = observationsFor scenario

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
      VerdictRecorded value      -> VerdictRecorded value { Verdict.event = eventId }
      FindingRecorded value      -> FindingRecorded value { Finding.event = eventId }
      FindingDisposed value      -> FindingDisposed value { Disposition.event = eventId }
      VerificationRecorded value -> VerificationRecorded value { Verification.event = eventId }
      DebtDeclared value         -> DebtDeclared value { Debt.event = eventId }
      AuditRecorded value        -> AuditRecorded value { Audit.event = eventId }
      IntegrationRecorded value  -> IntegrationRecorded value { Integration.event = eventId }
      unnumbered                 -> unnumbered

{- | Histories an integration would permit: an independent approval, or a
waiver bound to the latest patchset; covered gate evidence; no open
finding, no moved head, no verdict bound to an older patchset.
-}
isIntegratable :: Scenario -> Bool
isIntegratable scenario
  = authorized
  && scenario.gateMode == GateCovered
  && not scenario.blockingFinding
  && not scenario.headMoved
  && not (scenario.verdictOnFirst && scenario.patchsets > 1)
  where
    authorized = case scenario.reviewer of
      Just ActorIndependent -> scenario.verdict == Approved
      Just _contributing    -> False
      Nothing               -> scenario.debt /= Nothing

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
  [ [ Mutation "gate-omitted" scenario { Scenario.gateMode = GateOmitted }                | scenario.gateMode == GateCovered ]
  , [ Mutation "gate-elsewhere" scenario { Scenario.gateMode = GateOtherTree }            | scenario.gateMode == GateCovered ]
  , [ Mutation "gate-declaration-changed" scenario { Scenario.gateMode = GateShapeMoved } | scenario.gateMode == GateCovered ]
  , [ Mutation "gate-evidence-unreadable" scenario { Scenario.gateMode = GateUnreadable } | scenario.gateMode == GateCovered ]
  , [ Mutation "head-moved" scenario { Scenario.headMoved = True }                        | not scenario.headMoved ]
  , [ Mutation "target-moved" scenario { Scenario.targetAfter = True }                    | not scenario.targetAfter ]
  , [ Mutation "policy-moved" scenario { Scenario.policyAfter = True }                    | not scenario.policyAfter ]
  , [ Mutation "finding-opened" scenario { Scenario.blockingFinding = True }              | reviewed, not scenario.blockingFinding ]
  , [ Mutation "verdict-refused" scenario { Scenario.verdict = ChangesRequested }         | reviewed, scenario.verdict == Approved ]
  , [ Mutation "review-patchset-stale" scenario { Scenario.verdictOnFirst = True }        | reviewed, scenario.patchsets > 1, not (debtBindsLatest scenario) ]
  , [ Mutation "reviewer-is-contributor" scenario { Scenario.reviewer = Just ActorContributor }
    | scenario.reviewer == Just ActorIndependent
    , scenario.policy.independentVerdictRequired
    , scenario.policy.forbidSelfApproval
    , not (debtBindsLatest scenario)
    ]
  , [ Mutation "waiver-expired" scenario { Scenario.patchsets = scenario.patchsets + 1 }  | scenario.debt /= Nothing, scenario.reviewer == Nothing ]
  ]
  where
    reviewed = scenario.reviewer /= Nothing

-- | The behaviours a generated scenario is expected to reach. A run that
-- never reaches one is reported so the suite cannot pass on trivial inputs.
data Feature = FeaturePermitted
             | FeatureWaived
             | FeatureSelfApprovalRefused
             | FeatureGatesRefused
             | FeatureVerdictStands
             | FeatureHeadMoved
             | FeatureTargetMoved
             | FeaturePolicyMoved
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
  FeatureSelfApprovalRefused           -> refusedWith "self-approval"
  FeatureGatesRefused                  -> refusedWith "gates"
  FeatureVerdictStands                 -> refusedWith "verdict-stands"
  FeatureHeadMoved                     -> refusedWith "head-moved"
  FeatureTargetMoved                   -> movedFact isMovedTarget
  FeaturePolicyMoved                   -> movedFact isMovedPolicy
  FeatureDebtUnused                    -> permittedBy isUnusedDebt
  FeatureUnknownObservation            -> scenario.gateMode `elem` [GateOmitted, GateUnreadable]
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
    movedFact predicate = case built.execution of
      Left (RefusedBasisMoved facts) -> any predicate facts
      _stood                         -> False
    isWaiver = \case
      AuthorizedByWaiver _               -> True
      AuthorizedByVerdictUnderWaiver _ _ -> True
      AuthorizedByVerdict _              -> False
    isUnusedDebt = \case
      AuthorizedByVerdict _ -> any ((== DebtId 1) . (.debtId)) built.state.debts
      _waived               -> False
    isMovedTarget = \case
      MovedTarget _ _ -> True
      _other          -> False
    isMovedPolicy = \case
      MovedPolicy _ _ -> True
      _other          -> False
