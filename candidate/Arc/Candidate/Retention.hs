{- | Retention follows references.

Retained decisions and evidence are roots: every recorded selection, every
promotion, and every root somebody declared. Whatever a root reaches is
retained, and collecting it is refused. Episode liveness plays no part:
an expired episode deletes nothing a root reaches.

Whether content no root reaches should be collected, and when, is a budget
the model does not state. 'collection' answers 'NoRootReaches' for it,
which is a fact about references, not a permission to delete.

A referenced version is only as durable as its provider's guarantee. A
context object a root reaches is reported at risk unless the provider
reported it pinned.
-}
module Arc.Candidate.Retention
    ( Object(..)
    , RootSource(..)
    , Risk(..)
    , Retention(..)
    , Collection(..)
    , objects
    , rootObjects
    , references
    , reachable
    , collection
    , retention
    ) where

import Arc.Candidate.Basis ( Promotion(..), SelectionBasis(..) )
import Arc.Candidate.Context ( Capture(..), ContextRef(..), Locator )
import Arc.Candidate.Evaluation ( EvaluationRecord(..), ReviewRecord(..) )
import Arc.Candidate.Identifiers
import Arc.Candidate.Observations ( Observations, captureOf )
import Arc.Candidate.Registration ( Registration(..) )
import Arc.Candidate.Relation
import Arc.Candidate.State
import Arc.Model.Identifiers ( ActorId, TreeId )
import Arc.Model.Observed ( Observed(..) )

import Data.List ( nub )
import Data.Map.Strict ( Map )
import Data.Map.Strict qualified as Map
import Data.Maybe ( maybeToList )


data Object = CandidateObject !CandidateId
            | TreeObject !TreeId
            | EpisodeObject !EpisodeId
            | ContextObject !Locator !(Observed VersionId)
            | EvaluationObject !EvaluationId
            | ReviewObject !ReviewId
            | SelectionObject !SelectionId
  deriving stock (Eq, Ord, Show)

-- | Why an object is a root.
data RootSource = SelectionRoot !SelectionId
                | PromotionRoot !SelectionId
                | DeclaredRoot !ActorId !Root
  deriving stock (Eq, Ord, Show)

data Risk = CaptureUnpinned
          | CaptureUnobserved
          | ReferenceUnversioned
  deriving stock (Eq, Ord, Show)

data Retention = Retained !RootSource
               | RetainedAtRisk !RootSource !Risk
               | Unrooted
  deriving stock (Eq, Ord, Show)

data Collection = CollectionRefused !RootSource
                | NoRootReaches
  deriving stock (Eq, Ord, Show)

contextObject :: ContextRef -> Object
contextObject reference = ContextObject reference.locator reference.version

-- | Every object the ledger knows of.
objects :: State -> [Object]
objects state = nub $ concat
  [ concat [ [CandidateObject r.candidateId, TreeObject r.tree, contextObject r.brief] | r <- Map.elems state.registrations ]
  , [ EpisodeObject episode | episode <- Map.keys state.episodes ]
  , [ contextObject (relationReference relation) | relation <- state.context ]
  , [ EvaluationObject evaluation | evaluation <- Map.keys state.evaluations ]
  , [ ReviewObject review | review <- Map.keys state.reviews ]
  , [ SelectionObject selection | selection <- Map.keys state.selections ]
  , [ TreeObject s.tree | s <- Map.elems state.selections ]
  ]

relationReference :: ContextRelation -> ContextRef
relationReference = \case
  Supplied supply   -> supply.reference
  Read toolRead     -> toolRead.reference
  Declared declared -> declared.reference
  Inferred inferred -> inferred.reference

-- | The roots, each with the object it retains.
rootObjects :: State -> [(RootSource, Object)]
rootObjects state = concat
  [ [ (SelectionRoot selection, SelectionObject selection) | selection <- Map.keys state.selections ]
  , [ (PromotionRoot p.selection, SelectionObject p.selection) | p <- state.promotions ]
  , [ (DeclaredRoot actor root, declared root) | (actor, root) <- state.roots ]
  ]
  where
    declared = \case
      RootCandidate candidate   -> CandidateObject candidate
      RootEvaluation evaluation -> EvaluationObject evaluation
      RootContext (locator, v)  -> ContextObject locator (Observed v)

-- | The objects one object references directly.
references :: State -> Object -> [Object]
references state = \case
  CandidateObject candidate -> case Map.lookup candidate state.registrations of
    Nothing -> []
    Just r  -> concat
      [ [TreeObject r.tree, contextObject r.brief]
      , map CandidateObject r.parents
      , map CandidateObject r.adopts
      , map EpisodeObject r.episodes
      , [ contextObject d.reference | d <- declarations state, d.candidate == candidate ]
      ]
  EpisodeObject episode -> [ contextObject (relationReference relation) | relation <- state.context, byEpisode episode relation ]
  EvaluationObject evaluation -> case Map.lookup evaluation state.evaluations of
    Nothing -> []
    Just e  -> [CandidateObject e.candidate, TreeObject e.tree]
  ReviewObject review -> case Map.lookup review state.reviews of
    Nothing -> []
    Just r  -> [CandidateObject r.candidate, TreeObject r.tree]
  SelectionObject selection -> case Map.lookup selection state.selections of
    Nothing -> []
    Just s  -> concat
      [ [CandidateObject s.chosen, TreeObject s.tree]
      , [ EvaluationObject evaluation | (_gate, evaluation) <- s.gates ]
      , map ReviewObject (maybeToList s.review)
      , [ contextObject r.reference | r <- toolReads state, (_requirement, toolRecord) <- s.reads, r.record == toolRecord ]
      ]
  TreeObject _      -> []
  ContextObject _ _ -> []
  where
    byEpisode episode = \case
      Supplied supply -> supply.episode == episode
      Read toolRead   -> toolRead.episode == episode
      _declared       -> False

-- | Every object a root reaches, with the first root that reaches it.
reachable :: State -> Map Object RootSource
reachable state = foldl visitRoot Map.empty (rootObjects state)
  where
    visitRoot seen (source, object) = visit source seen [object]
    visit _source seen [] = seen
    visit source seen (object : rest)
      | Map.member object seen = visit source seen rest
      | otherwise              = visit source (Map.insert object source seen) (references state object <> rest)

-- | Whether collecting an object is refused, and by which root.
collection :: State -> Object -> Collection
collection state object = maybe NoRootReaches CollectionRefused (Map.lookup object (reachable state))

-- | Whether an object is retained, and whether its provider guarantees it.
retention :: Observations -> State -> Object -> Retention
retention observations state object = case Map.lookup object (reachable state) of
  Nothing     -> Unrooted
  Just source -> case object of
    ContextObject _ Omitted            -> RetainedAtRisk source ReferenceUnversioned
    ContextObject locator (Observed v) -> case captureOf observations (locator, v) of
      Observed Pinned   -> Retained source
      Observed Unpinned -> RetainedAtRisk source CaptureUnpinned
      Omitted           -> RetainedAtRisk source CaptureUnobserved
    _stored -> Retained source
