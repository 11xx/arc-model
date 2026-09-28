{- | Deliberate faults in the candidate protocol.

Each mutant changes exactly one rule. The suite must kill every one, for
the predicted reason: a fault that lets a selection through is a different
fault from one that lets rooted content be collected.
-}
module Mutants
    ( Behaviour(..)
    , Channel(..)
    , specBehaviour
    , Divergence(..)
    , divergenceOf
    , predictedHolds
    , Mutant(..)
    , allMutants
    ) where

import Arc.Candidate
import Arc.Candidate.State qualified as State
import Arc.Model.Identifiers ( ActorId(..) )
import Arc.Model.Observed ( Observed(..) )
import Plan

import Data.List.NonEmpty ( NonEmpty )
import Data.Map.Strict qualified as Map
import Data.Maybe ( listToMaybe )


-- | One observable channel of the candidate model.
data Behaviour = BehaviourDecision (Either (NonEmpty Refusal) SelectionBasis)
               | BehaviourPromotion (Maybe (Either Refusal PromotionPlan))
               | BehaviourRetention [(Object, Collection)]
  deriving stock (Eq, Show)

data Channel = ChannelDecision
             | ChannelPromotion
             | ChannelRetention
  deriving stock (Eq, Show)

specBehaviour :: Channel -> Built -> Behaviour
specBehaviour channel built = case channel of
  ChannelDecision  -> BehaviourDecision built.decision
  ChannelPromotion -> BehaviourPromotion built.promotion
  ChannelRetention -> BehaviourRetention [ (object, collection built.finalState object) | object <- objects built.finalState ]

-- | How a mutant's answer differs from the model's. On the retention
-- channel, permitting means some object the model refuses to collect is
-- reported as reached by no root.
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
      (BehaviourDecision (Right _), BehaviourDecision (Left _))                  -> DivergencePermits
      (BehaviourDecision (Left _), BehaviourDecision (Right _))                  -> DivergenceRefuses
      (BehaviourDecision (Left _), BehaviourDecision (Left _))                   -> DivergenceDifferentRefusal
      (BehaviourPromotion (Just (Right _)), BehaviourPromotion (Just (Left _)))  -> DivergencePermits
      (BehaviourPromotion (Just (Left _)), BehaviourPromotion (Just (Right _)))  -> DivergenceRefuses
      (BehaviourPromotion (Just (Left _)), BehaviourPromotion (Just (Left _)))   -> DivergenceDifferentRefusal
      (BehaviourRetention answers, BehaviourRetention expected)
        | or [ a == NoRootReaches && e /= NoRootReaches | ((_, a), (_, e)) <- zip answers expected ] -> DivergencePermits
      _values                                                                    -> DivergenceDifferentValue

predictedHolds :: [Divergence] -> Divergence -> Bool
predictedHolds predicted divergence = divergence == DivergenceAgrees || divergence `elem` predicted

data Mutant = Mutant
  { name      :: !String
  , channel   :: !Channel
  , predicted :: ![Divergence]
  , run       :: !(Plan -> Built -> Behaviour)
  }

allMutants :: [Mutant]
allMutants =
  [ Mutant
      { name      = "candidate-identity-dropped-when-trees-match"
      , channel   = ChannelDecision
      , predicted = [DivergencePermits, DivergenceDifferentRefusal]
      , run       = decisionOn identityByTree
      }
  , Mutant
      { name      = "decision-reused-after-target-moved"
      , channel   = ChannelPromotion
      , predicted = [DivergencePermits]
      , run       = \_plan built -> BehaviourPromotion (either (const Nothing) (Just . Right . PromotionPlan) built.decision)
      }
  , Mutant
      { name      = "contributor-identity-ignored-in-selection-authority"
      , channel   = ChannelDecision
      , predicted = [DivergencePermits, DivergenceDifferentRefusal]
      , run       = decisionOn reviewersAnonymized
      }
  , Mutant
      { name      = "unknown-context-treated-as-complete"
      , channel   = ChannelDecision
      , predicted = [DivergencePermits, DivergenceDifferentRefusal]
      , run       = decisionOn coverageAssumed
      }
  , Mutant
      { name      = "collection-permitted-of-rooted-content"
      , channel   = ChannelRetention
      , predicted = [DivergencePermits]
      , run       = \_plan built -> BehaviourRetention (shallowCollection built.finalState)
      }
  , Mutant
      { name      = "episode-ttl-expires-retained-candidate"
      , channel   = ChannelRetention
      , predicted = [DivergencePermits]
      , run       = \_plan built -> BehaviourRetention (expiryCollection built.finalState)
      }
  , Mutant
      { name      = "declared-context-consumed-as-read"
      , channel   = ChannelDecision
      , predicted = [DivergencePermits, DivergenceDifferentRefusal]
      , run       = decisionOn declarationsAsReads
      }
  ]

-- | The decision the model makes on a faulted reading of the built state.
decisionOn :: (Built -> State) -> Plan -> Built -> Behaviour
decisionOn fault plan built = BehaviourDecision (evaluate plan.policy built.requirements built.observations (fault built) built.proposal)

{- | A state where registrations of one tree are one candidate: every
evaluation and review recorded for a registration sharing the chosen
registration's tree reads as recorded for the chosen one.
-}
identityByTree :: Built -> State
identityByTree built = case registration built.state built.proposal.chosen of
  Nothing     -> built.state
  Just chosen -> built.state
    { State.evaluations = Map.map (relabelEvaluation chosen) built.state.evaluations
    , State.reviews     = Map.map (relabelReview chosen) built.state.reviews
    }
  where
    sameTree chosen candidate = ((.tree) <$> registration built.state candidate) == Just chosen.tree
    relabelEvaluation chosen e
      | sameTree chosen e.candidate = EvaluationRecord
          { evaluationId = e.evaluationId
          , candidate    = chosen.candidateId
          , tree         = e.tree
          , gate         = e.gate
          , declaration  = e.declaration
          , environment  = e.environment
          , outcome      = e.outcome
          , evaluator    = e.evaluator
          }
      | otherwise = e
    relabelReview chosen r
      | sameTree chosen r.candidate = ReviewRecord
          { reviewId  = r.reviewId
          , candidate = chosen.candidateId
          , tree      = r.tree
          , reviewer  = r.reviewer
          , kind      = r.kind
          }
      | otherwise = r

-- | A state where no reviewer's identity is compared with the contributors:
-- every review reads as if a stranger recorded it.
reviewersAnonymized :: Built -> State
reviewersAnonymized built = built.state { State.reviews = Map.map anonymize built.state.reviews }
  where
    anonymize r = ReviewRecord
      { reviewId  = r.reviewId
      , candidate = r.candidate
      , tree      = r.tree
      , reviewer  = ActorId "identity-ignored"
      , kind      = r.kind
      }

-- | A state where a read whose coverage was never observed reads as whole.
coverageAssumed :: Built -> State
coverageAssumed built = built.state { State.context = map assume built.state.context }
  where
    assume = \case
      Read toolRead | toolRead.reference.coverage == Omitted -> Read ToolRead
        { episode   = toolRead.episode
        , record    = toolRead.record
        , reference = ContextRef
            { locator  = toolRead.reference.locator
            , version  = toolRead.reference.version
            , coverage = Observed Whole
            }
        }
      relation -> relation

-- | A state where every declared citation or reliance on context reads as
-- a tool's record of the chosen candidate's episode reading it.
declarationsAsReads :: Built -> State
declarationsAsReads built = built.state { State.context = built.state.context <> consumed }
  where
    episode  = listToMaybe . (.episodes) =<< registration built.state built.proposal.chosen
    consumed =
      [ Read ToolRead { episode = reader, record = ToolRecordId "declared-as-read", reference = declared.reference }
      | Just reader   <- [episode]
      , Declared declared <- built.state.context
      , declared.kind `elem` [Cites, ReliesOn]
      ]

-- | Collection that consults the roots themselves and nothing they reach.
shallowCollection :: State -> [(Object, Collection)]
shallowCollection state =
  [ (object, maybe NoRootReaches CollectionRefused (Map.lookup object direct)) | object <- objects state ]
  where
    direct = Map.fromList (reverse [ (object, source) | (source, object) <- rootObjects state ])

-- | Collection where a candidate whose every episode has expired is
-- reached by no root.
expiryCollection :: State -> [(Object, Collection)]
expiryCollection state = [ (object, answer object) | object <- objects state ]
  where
    answer object = case object of
      CandidateObject candidate
        | Just r <- registration state candidate
        , not (null r.episodes)
        , not (any (episodeLive state) r.episodes) -> NoRootReaches
      _other -> collection state object
