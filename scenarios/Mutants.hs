{- | Deliberate faults.

Each mutant changes exactly one rule of the model. The suite must kill
every one of them, and it must kill each for the predicted reason: a
mutant that permits where the model refuses is a different fault from one
that rewrites a recorded basis. A mutant that survives is a gap in the
suite, not a hobby.
-}
module Mutants
    ( Behaviour(..)
    , Channel(..)
    , specBehaviour
    , Predicted
    , Divergence(..)
    , divergenceOf
    , predictedHolds
    , Mutant(..)
    , allMutants
    ) where

import Arc.Model
import Arc.Model.Coverage qualified as Coverage
import Arc.Model.Ledger.Brief qualified as Brief
import Arc.Model.Declaration qualified as Declaration
import Arc.Model.Ledger.Debt qualified as Debt
import Arc.Model.Ledger.Verdict qualified as Verdict
import Arc.Model.Ledger.Verification qualified as Verification
import Arc.Model.Observations qualified as Observations
import Arc.Model.State qualified as State
import Generators

import Data.Maybe ( listToMaybe )


-- | One observable channel of the model.
data Behaviour = BehaviourDecision Decision
               | BehaviourExecution (Either Refusal ExecutionPlan)
               | BehaviourHistorical (Maybe Authorization)
               | BehaviourCoverage CoverageAfterIntegration
  deriving stock (Eq, Show)

data Channel = ChannelDecision
             | ChannelExecution
             | ChannelHistorical
             | ChannelCoverage
  deriving stock (Eq, Show)

-- | What the model says on one channel.
specBehaviour :: Channel -> Built -> Behaviour
specBehaviour channel built = case channel of
  ChannelDecision   -> BehaviourDecision built.decision
  ChannelExecution  -> BehaviourExecution built.execution
  ChannelHistorical -> BehaviourHistorical (historicalAuthorization built.finalState)
  ChannelCoverage   -> BehaviourCoverage (coverageAfterIntegration built.finalState)

-- | The divergence classes a mutant is allowed to exhibit. A fault can show
-- as a permission where the model refused, or as one refusal replaced by
-- another that no longer rests on the dropped fact.
type Predicted = [Divergence]

-- | How a mutant's answer differs from the model's.
data Divergence = DivergenceAgrees
                | DivergencePermits
                | DivergenceRefuses
                | DivergenceDifferentRefusal
                | DivergenceDifferentValue
  deriving stock (Eq, Show)

divergenceOf :: Behaviour -> Behaviour -> Divergence
divergenceOf mutant spec
  | mutant == spec = DivergenceAgrees
  | otherwise = case (mutant, spec) of
      (BehaviourDecision (Permitted _), BehaviourDecision (Refused _)) -> DivergencePermits
      (BehaviourDecision (Refused _), BehaviourDecision (Permitted _)) -> DivergenceRefuses
      (BehaviourDecision (Refused _), BehaviourDecision (Refused _))   -> DivergenceDifferentRefusal
      (BehaviourExecution (Right _), BehaviourExecution (Left _))      -> DivergencePermits
      (BehaviourExecution (Left _), BehaviourExecution (Right _))      -> DivergenceRefuses
      (BehaviourExecution (Left _), BehaviourExecution (Left _))       -> DivergenceDifferentRefusal
      _values                                                          -> DivergenceDifferentValue

predictedHolds :: Predicted -> Divergence -> Bool
predictedHolds predicted divergence = divergence == DivergenceAgrees || divergence `elem` predicted

data Mutant = Mutant
  { name      :: !String
  , channel   :: !Channel
  , predicted :: !Predicted
  , run       :: !(Built -> Behaviour)
  }

allMutants :: [Mutant]
allMutants =
  [ Mutant
      { name      = "contributor-identity-ignored"
      , channel   = ChannelDecision
      , predicted = [DivergencePermits, DivergenceDifferentRefusal, DivergenceDifferentValue]
      , run       = decisionOn withoutContributors
      }
  , Mutant
      { name      = "gate-matched-by-name"
      , channel   = ChannelDecision
      , predicted = [DivergencePermits, DivergenceDifferentRefusal]
      , run       = decisionOn evidenceNormalized
      }
  , Mutant
      { name      = "unknown-treated-as-success"
      , channel   = ChannelDecision
      , predicted = [DivergencePermits, DivergenceDifferentRefusal]
      , run       = decisionOn evidenceFabricated
      }
  , Mutant
      { name      = "authorization-reused-after-basis-moved"
      , channel   = ChannelExecution
      , predicted = [DivergencePermits, DivergenceDifferentRefusal]
      , run       = \b -> BehaviourExecution (execute b.observation b.state b.decision)
      }
  , Mutant
      { name      = "fulfilled-implies-approved"
      , channel   = ChannelCoverage
      , predicted = [DivergenceDifferentValue]
      , run       = BehaviourCoverage . approvedByRead . coverageAfterIntegration . (.finalState)
      }
  , Mutant
      { name      = "latest-debt-applied-to-every-patchset"
      , channel   = ChannelDecision
      , predicted = [DivergencePermits, DivergenceDifferentRefusal]
      , run       = decisionOn debtsRelocated
      }
  , Mutant
      { name      = "debt-clears-refusing-verdict"
      , channel   = ChannelDecision
      , predicted = [DivergencePermits, DivergenceDifferentRefusal]
      , run       = decisionOn refusalDropped
      }
  , Mutant
      { name      = "later-audit-rewrites-integration-basis"
      , channel   = ChannelHistorical
      , predicted = [DivergenceDifferentValue]
      , run       = BehaviourHistorical . auditRewritesBasis . (.finalState)
      }
  , Mutant
      { name      = "unreadable-evidence-counts-as-review"
      , channel   = ChannelDecision
      , predicted = [DivergencePermits, DivergenceDifferentRefusal]
      , run       = decisionOn evidenceMadeReadable
      }
  , Mutant
      { name      = "external-approval-counts-as-independent-review"
      , channel   = ChannelDecision
      -- where an external approval already authorizes, the fault names a
      -- witnessed verdict in the basis instead: a different value
      , predicted = [DivergencePermits, DivergenceDifferentRefusal, DivergenceDifferentValue]
      , run       = decisionOn externalTreatedAsWitnessed
      }
  , Mutant
      { name      = "environment-ignored"
      , channel   = ChannelDecision
      , predicted = [DivergencePermits, DivergenceDifferentRefusal]
      , run       = \b -> BehaviourDecision (decide (probesDropped b.observation) b.state)
      }
  , Mutant
      { name      = "authority-ignored"
      , channel   = ChannelExecution
      , predicted = [DivergencePermits, DivergenceDifferentRefusal]
      , run       = \b -> BehaviourExecution (execute (authorityAssumed b.executionObservation) b.state b.decision)
      }
  , Mutant
      { name      = "dirty-evidence-counts"
      , channel   = ChannelDecision
      , predicted = [DivergencePermits, DivergenceDifferentRefusal]
      , run       = decisionOn worktreesCleaned
      }
  , Mutant
      { name      = "merge-read-as-head"
      , channel   = ChannelDecision
      -- evidence recorded against the merge no longer answers for the head
      -- tree the fault reads instead, so the fault also refuses
      , predicted = [DivergencePermits, DivergenceDifferentRefusal, DivergenceRefuses]
      , run       = \b -> BehaviourDecision (decide (mergeReadAsHead b) b.state)
      }
  , Mutant
      { name      = "rebase-ignored"
      , channel   = ChannelDecision
      , predicted = [DivergencePermits, DivergenceDifferentRefusal]
      , run       = \b -> BehaviourDecision (decide (conflictIgnored b.observation) b.state)
      }
  , Mutant
      { name      = "final-probe-pass-suffices"
      , channel   = ChannelDecision
      , predicted = [DivergencePermits, DivergenceDifferentRefusal]
      , run       = decisionOn baselinesFabricated
      }
  , Mutant
      { name      = "missing-branch-read-as-head"
      , channel   = ChannelDecision
      , predicted = [DivergencePermits, DivergenceDifferentRefusal]
      , run       = \b -> BehaviourDecision (decide (branchAssumed b) b.state)
      }
  , Mutant
      { name      = "first-gate-declaration-wins"
      , channel   = ChannelDecision
      , predicted = [DivergencePermits, DivergenceDifferentRefusal]
      , run       = \b -> BehaviourDecision (decide (b.observation { Observations.conflictingGates = [] }) b.state)
      }
  ]

-- | The decision the model makes on a faulted reading of the built state.
decisionOn :: (Built -> ChangeState) -> Built -> Behaviour
decisionOn fault built = BehaviourDecision (decide built.observation (fault built))

{- | A state where the reviewer's identity is not compared against the
contributor set: every verdict reads as if it came from a declared
stranger. The assumed-identity half of the rule still applies, because a
mutant that ignores identity entirely would not be the fault under test.
-}
withoutContributors :: Built -> ChangeState
withoutContributors built = built.state
  { State.verdicts =
      [ verdict { Verdict.actor = ActorId "identity-ignored", Verdict.onBehalfOf = Nothing }
      | verdict <- built.state.verdicts
      ]
  }

-- | A state where every recorded evaluation is moved to the evaluated tree
-- and the declared shape, so a gate is green by name alone.
evidenceNormalized :: Built -> ChangeState
evidenceNormalized built = built.state { State.verifications = map normalize built.state.verifications }
  where
    normalize verification = case declarationFor verification.declaration of
      Just declaration -> verification
        { Verification.tree  = built.observation.evaluatedTree
        , Verification.shape = declarationShape declaration
        }
      Nothing -> verification
    declarationFor wanted = listToMaybe [ d | d <- built.observation.declarations, d.declarationId == wanted ]

-- | A state where a missing observation is answered with a passing record.
evidenceFabricated :: Built -> ChangeState
evidenceFabricated built = case built.decision of
  Refused (RefusedGates _) -> built.state { State.verifications = built.state.verifications <> fabricated }
  _otherwise               -> built.state
  where
    fabricated =
      [ Verification
          { event       = EventId 990
          , gate        = gate
          , declaration = declaration.declarationId
          , shape       = declarationShape declaration
          , revision    = maybe (Revision "none") (.revision) (latestPatchset built.state)
          , tree        = built.observation.evaluatedTree
          , result      = GatePass
          , execution   = RanLocally
          , answers     = Nothing
          , readable    = True
          , environment = declaration.environment >>= \probe -> lookup probe built.observation.environments >>= observedToMaybe
          , worktree    = Observed CleanWorktree
          }
      | (gate, wanted) <- take 1 built.observation.requiredGates
      , declaration    <- take 1 [ d | d <- built.observation.declarations, d.declarationId == wanted ]
      ]

-- | A state where one debt declaration is rebound from its patchset to the
-- newest one.
debtsRelocated :: Built -> ChangeState
debtsRelocated built = built.state { State.debts = [ debt { Debt.patchset = latest } | debt <- built.state.debts ] }
  where
    latest = (.patchsetId) <$> latestPatchset built.state

-- | A state where a refusing verdict has been dropped, as if the debt
-- cleared it.
refusalDropped :: Built -> ChangeState
refusalDropped built = case built.decision of
  Refused (RefusedVerdictStands _ event)
    | waiverBindsLatest -> built.state { State.verdicts = filter ((/= event) . (.event)) built.state.verdicts }
  _otherwise -> built.state
  where
    waiverBindsLatest = case latestPatchset built.state of
      Nothing       -> False
      Just patchset -> not (null (debtsForPatchset built.state patchset.patchsetId))

-- | A state where every evidence record is readable.
evidenceMadeReadable :: Built -> ChangeState
evidenceMadeReadable built = built.state
  { State.verifications = [ verification { Verification.readable = True } | verification <- built.state.verifications ]
  }

{- | A state where an external approval of the latest head is read as a
verdict arc witnessed from a declared independent reviewer, superseding
whatever local verdict stood. That is the fault of trusting an identity arc
cannot check.
-}
externalTreatedAsWitnessed :: Built -> ChangeState
externalTreatedAsWitnessed built = case (latestPatchset built.state, externalVerdictAt built.state =<< ((.revision) <$> latestPatchset built.state)) of
  (Just patchset, Just external)
    | external.kind == ExternalApproved -> built.state
        { State.verdicts = built.state.verdicts <>
            [ Verdict
                { event       = EventId 980
                , patchset    = patchset.patchsetId
                , kind        = Approved
                , actor       = ActorId "upstream"
                , onBehalfOf  = Nothing
                , assumed     = False
                , provisional = Nothing
                , relation    = Supersedes
                , supersedes  = (.event) <$> governingVerdict built.state
                }
            ]
        }
  _absent -> built.state

-- | Observations where no declaration names a probe, so evidence from any
-- environment answers for every gate.
probesDropped :: Observations -> Observations
probesDropped observations = observations
  { Observations.declarations = [ d { Declaration.environment = Nothing } | d <- observations.declarations ]
  }

-- | A state where every run arc observed reads as run on a clean worktree.
worktreesCleaned :: Built -> ChangeState
worktreesCleaned built = built.state
  { State.verifications = [ verification { Verification.worktree = Observed CleanWorktree } | verification <- built.state.verifications ]
  }

-- | Observations where a change behind its target is decided on its head's
-- own tree, as if nothing would be merged.
mergeReadAsHead :: Built -> Observations
mergeReadAsHead built = case (built.observation.targetRelation, latestPatchset built.state) of
  (HeadBehindTarget, Just patchset) -> built.observation
    { Observations.targetRelation = HeadContainsTarget
    , Observations.evaluatedTree  = patchset.tree
    }
  _contained -> built.observation

-- | Observations where a head that does not merge with its target reads as
-- one that contains it.
conflictIgnored :: Observations -> Observations
conflictIgnored observations = case observations.targetRelation of
  HeadConflictsWithTarget -> observations { Observations.targetRelation = HeadContainsTarget }
  _merges                 -> observations

-- | A state where every brief has a base apart from the head and every
-- probe a failing baseline there, so a pass at the head discharges it.
baselinesFabricated :: Built -> ChangeState
baselinesFabricated built = built.state
  { State.briefs    = [ brief { Brief.base = Just faultBase } | brief <- built.state.briefs ]
  , State.probeRuns = built.state.probeRuns <>
      [ ProbeRun
          { event    = EventId 970
          , brief    = brief.event
          , probe    = name
          , phase    = Baseline
          , revision = faultBase
          , result   = GateFail
          }
      | brief <- built.state.briefs
      , name  <- brief.probes
      ]
  }
  where
    faultBase = Revision "fault-base"

-- | Observations where a missing branch reads as the recorded patchset's
-- head.
branchAssumed :: Built -> Observations
branchAssumed built = case (built.observation.head, latestPatchset built.state) of
  (Omitted, Just patchset) -> built.observation { Observations.head = Observed patchset.revision }
  _observed                -> built.observation

-- | Observations where the store always holds integration authority.
authorityAssumed :: Observations -> Observations
authorityAssumed observations = observations { Observations.authority = AuthorityHeld }

-- | A coverage projection where a fulfilled read counts as an approval.
approvedByRead :: CoverageAfterIntegration -> CoverageAfterIntegration
approvedByRead coverage = coverage { Coverage.approved = coverage.approved || coverage.read /= Nothing }

-- | A historical reading where the newest audit replaces what the merge
-- rested on.
auditRewritesBasis :: ChangeState -> Maybe Authorization
auditRewritesBasis state = case newest state.audits of
  Nothing    -> historicalAuthorization state
  Just audit -> Just (AuthorizedByVerdict audit.event)
