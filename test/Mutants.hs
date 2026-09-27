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
import Arc.Model.Ledger.Debt qualified as Debt
import Arc.Model.Ledger.Verdict qualified as Verdict
import Arc.Model.Ledger.Verification qualified as Verification
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
          , tree        = built.observation.evaluatedTree
          , result      = GatePass
          , execution   = RanLocally
          , answers     = Nothing
          , readable    = True
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

-- | A coverage projection where a fulfilled read counts as an approval.
approvedByRead :: CoverageAfterIntegration -> CoverageAfterIntegration
approvedByRead coverage = coverage { Coverage.approved = coverage.approved || coverage.read /= Nothing }

-- | A historical reading where the newest audit replaces what the merge
-- rested on.
auditRewritesBasis :: ChangeState -> Maybe Authorization
auditRewritesBasis state = case newest state.audits of
  Nothing    -> historicalAuthorization state
  Just audit -> Just (AuthorizedByVerdict audit.event)
