{- | The candidate ledger: checked writes, replay, and derived queries.

Every write is checked on the way in. A registration is written once and no
later event can alter it, so selection, evaluation, review, promotion, and
episode expiry all leave every registration exactly as it was recorded. A
declaration's citation must resolve to a recorded read; a citation that
resolves to nothing is refused, never recorded as unknown. A parent must
share its child's contract, and an adopting registration's producers must
include every producer along the adopted registration's parent chain.
-}
module Arc.Candidate.State
    ( Event(..)
    , Root(..)
    , State(..)
    , WriteRefusal(..)
    , emptyState
    , record
    , replay
    , recordPromotion
    , registration
    , lineage
    , episodeLive
    , candidatesOf
    , sharedStorage
    , toolReads
    , declarations
    , relations
    ) where

import Arc.Candidate.Basis ( Promotion(..), PromotionPlan(..), SelectionBasis )
import Arc.Candidate.Basis qualified as Basis
import Arc.Candidate.Context ( ContextKey )
import Arc.Candidate.Context qualified as Context
import Arc.Candidate.Evaluation ( EvaluationRecord, ReviewRecord )
import Arc.Candidate.Evaluation qualified as Evaluation
import Arc.Candidate.Identifiers
import Arc.Candidate.Registration ( Registration, contractOf )
import Arc.Candidate.Registration qualified as Registration
import Arc.Candidate.Relation
import Arc.Model.Identifiers ( ActorId, Revision, TreeId )
import Arc.Model.Observed ( Observed(..) )

import Control.Monad ( foldM, unless, when )
import Data.Map.Strict ( Map )
import Data.Map.Strict qualified as Map
import Data.Set ( Set )
import Data.Set qualified as Set


-- | An explicitly declared retention root.
data Root = RootCandidate !CandidateId
          | RootEvaluation !EvaluationId
          | RootContext !ContextKey
  deriving stock (Eq, Ord, Show)

data Event = Registered !Registration
           | EpisodeOpened !EpisodeId
           | EpisodeExpired !EpisodeId
           | ContextRecorded !ContextRelation
           | Judged !Judgement
           | EvaluationRecorded !EvaluationRecord
           | ReviewRecorded !ReviewRecord
           | SelectionRecorded !SelectionBasis
           | PromotionRecorded !Promotion
           | RootDeclared !ActorId !Root
  deriving stock (Eq, Show)

-- | Episode liveness is 'True' while the episode is live. Liveness gates no
-- write and retains nothing.
data State = State
  { registrations :: !(Map CandidateId Registration)
  , episodes      :: !(Map EpisodeId Bool)
  , context       :: ![ContextRelation]
  , judgements    :: ![Judgement]
  , evaluations   :: !(Map EvaluationId EvaluationRecord)
  , reviews       :: !(Map ReviewId ReviewRecord)
  , selections    :: !(Map SelectionId SelectionBasis)
  , promotions    :: ![Promotion]
  , roots         :: ![(ActorId, Root)]
  }
  deriving stock (Eq, Show)

data WriteRefusal = DuplicateCandidate !CandidateId
                  | UnknownCandidate !CandidateId
                  | UnknownParent !CandidateId
                  | ParentOtherContract !CandidateId !CandidateId                   -- ^ The registration, then its parent.
                  | AdoptionDropsProducer !CandidateId !CandidateId !(Set ActorId) -- ^ The registration, the adopted one, and the producers it drops.
                  | UnknownEpisode !EpisodeId
                  | DuplicateEpisode !EpisodeId
                  | BriefUnversioned !CandidateId
                  | NoProducers !CandidateId
                  | CitationUnresolved !ToolRecordId
                  | DuplicateToolRecord !ToolRecordId
                  | DuplicateEvaluation !EvaluationId
                  | DuplicateReview !ReviewId
                  | DuplicateSelection !SelectionId
                  | UnknownSelection !SelectionId
                  | PromotionUnobserved !SelectionId
                  | UnknownEvaluation !EvaluationId
  deriving stock (Eq, Ord, Show)

emptyState :: State
emptyState = State
  { registrations = Map.empty
  , episodes      = Map.empty
  , context       = []
  , judgements    = []
  , evaluations   = Map.empty
  , reviews       = Map.empty
  , selections    = Map.empty
  , promotions    = []
  , roots         = []
  }

-- writes

-- | Check one event against the state and append it.
record :: State -> Event -> Either WriteRefusal State
record state = \case
  Registered registered -> do
    let candidate = registered.candidateId
    when (Map.member candidate state.registrations)    (Left (DuplicateCandidate candidate))
    when (Set.null registered.producers)               (Left (NoProducers candidate))
    when (registered.brief.version == Omitted)         (Left (BriefUnversioned candidate))
    mapM_ (knownCandidate UnknownParent) registered.parents
    mapM_ (sameContract registered) registered.parents
    mapM_ (knownCandidate UnknownCandidate) registered.adopts
    mapM_ (carriesProducers registered) registered.adopts
    mapM_ knownEpisode registered.episodes
    pure state { registrations = Map.insert candidate registered state.registrations }

  EpisodeOpened episode -> do
    when (Map.member episode state.episodes) (Left (DuplicateEpisode episode))
    pure state { episodes = Map.insert episode True state.episodes }

  EpisodeExpired episode -> do
    knownEpisode episode
    pure state { episodes = Map.insert episode False state.episodes }

  ContextRecorded relation -> do
    case relation of
      Supplied supply   -> knownEpisode supply.episode
      Read toolRead     -> do
        knownEpisode toolRead.episode
        when (toolRead.record `elem` map (.record) (toolReads state)) (Left (DuplicateToolRecord toolRead.record))
      Declared declared -> do
        knownCandidate UnknownCandidate declared.candidate
        mapM_ citationResolves declared.citation
      Inferred inferred -> knownCandidate UnknownCandidate inferred.candidate
    pure state { context = state.context <> [relation] }

  Judged judgement -> do
    knownCandidate UnknownCandidate judgement.candidate
    case judgement.kind of
      SupersededBy other  -> knownCandidate UnknownCandidate other
      RejectedAlternative -> pure ()
    pure state { judgements = state.judgements <> [judgement] }

  EvaluationRecorded evaluation -> do
    knownCandidate UnknownCandidate evaluation.candidate
    when (Map.member evaluation.evaluationId state.evaluations) (Left (DuplicateEvaluation evaluation.evaluationId))
    pure state { evaluations = Map.insert evaluation.evaluationId evaluation state.evaluations }

  ReviewRecorded review -> do
    knownCandidate UnknownCandidate review.candidate
    when (Map.member review.reviewId state.reviews) (Left (DuplicateReview review.reviewId))
    pure state { reviews = Map.insert review.reviewId review state.reviews }

  SelectionRecorded basis -> do
    knownCandidate UnknownCandidate basis.chosen
    when (Map.member basis.selectionId state.selections) (Left (DuplicateSelection basis.selectionId))
    pure state { selections = Map.insert basis.selectionId basis state.selections }

  PromotionRecorded promotion -> do
    unless (Map.member promotion.selection state.selections) (Left (UnknownSelection promotion.selection))
    pure state { promotions = state.promotions <> [promotion] }

  RootDeclared actor root -> do
    case root of
      RootCandidate candidate   -> knownCandidate UnknownCandidate candidate
      RootEvaluation evaluation -> unless (Map.member evaluation state.evaluations) (Left (UnknownEvaluation evaluation))
      RootContext _             -> pure ()
    pure state { roots = state.roots <> [(actor, root)] }
  where
    knownCandidate refusal candidate = unless (Map.member candidate state.registrations) (Left (refusal candidate))
    knownEpisode episode = unless (Map.member episode state.episodes) (Left (UnknownEpisode episode))
    citationResolves cited = unless (cited `elem` map (.record) (toolReads state)) (Left (CitationUnresolved cited))
    sameContract registered parent = case registration state parent of
      Just found | contractOf found /= contractOf registered -> Left (ParentOtherContract registered.candidateId parent)
      _shared                                                -> pure ()
    carriesProducers registered adopted = case registration state adopted of
      Just found
        | let dropped = foldMap (.producers) (lineage state found) `Set.difference` registered.producers
        , not (Set.null dropped) -> Left (AdoptionDropsProducer registered.candidateId adopted dropped)
      _carried -> pure ()

-- | Replay a ledger, refusing at the first write that would not be recorded.
replay :: [Event] -> Either WriteRefusal State
replay = foldM record emptyState

-- | Record a promotion the shell performed. A plan is permission, not
-- effect: without an observed result there is nothing to record.
recordPromotion :: PromotionPlan -> Observed Revision -> State -> Either WriteRefusal State
recordPromotion (PromotionPlan basis) effect state = case effect of
  Omitted         -> Left (PromotionUnobserved basis.selectionId)
  Observed merged -> record state (PromotionRecorded Promotion { selection = basis.selectionId, merged = merged })

-- queries

registration :: State -> CandidateId -> Maybe Registration
registration state candidate = Map.lookup candidate state.registrations

-- | A registration and every registration along its parent chain, each
-- once, the registration first. An adopted registration is not on it.
lineage :: State -> Registration -> [Registration]
lineage state start = go Set.empty [start]
  where
    go _seen [] = []
    go seen (current : rest)
      | Set.member current.candidateId seen = go seen rest
      | otherwise = current : go (Set.insert current.candidateId seen) (rest <> [ p | parent <- current.parents, Just p <- [registration state parent] ])

-- | An episode is live until it expires. Liveness says nothing about what
-- the episode produced.
episodeLive :: State -> EpisodeId -> Bool
episodeLive state episode = Map.lookup episode state.episodes == Just True

-- | The candidates that cite an episode: zero, one, or many.
candidatesOf :: State -> EpisodeId -> [CandidateId]
candidatesOf state episode = [ r.candidateId | r <- Map.elems state.registrations, episode `elem` r.episodes ]

-- | Registrations grouped by the tree they share. Sharing storage shares
-- nothing else.
sharedStorage :: State -> Map TreeId (Set CandidateId)
sharedStorage state = Map.fromListWith Set.union [ (r.tree, Set.singleton r.candidateId) | r <- Map.elems state.registrations ]

toolReads :: State -> [ToolRead]
toolReads state = [ toolRead | Read toolRead <- state.context ]

declarations :: State -> [Declaration]
declarations state = [ declared | Declared declared <- state.context ]

-- | Every relation the ledger holds, each with who established it.
relations :: State -> [Relation]
relations state = concat
  [ [ Relation Produced (EpisodeNode episode) (CandidateNode r.candidateId) ByLedger | r <- registered, episode <- r.episodes ]
  , [ Relation Adopted (CandidateNode r.candidateId) (CandidateNode adopted) ByLedger | r <- registered, adopted <- r.adopts ]
  , map contextRelation state.context
  , [ judged judgement | judgement <- state.judgements ]
  , [ Relation Evaluated (EvaluationNode e.evaluationId) (CandidateNode e.candidate) ByLedger | e <- Map.elems state.evaluations ]
  , [ Relation Reviewed (ReviewNode r.reviewId) (CandidateNode r.candidate) ByLedger | r <- Map.elems state.reviews ]
  , [ Relation Selected (SelectionNode s.selectionId) (CandidateNode s.chosen) ByLedger | s <- Map.elems state.selections ]
  , [ Relation Promoted (SelectionNode p.selection) (CandidateNode s.chosen) ByLedger
    | p <- state.promotions, Just s <- [Map.lookup p.selection state.selections] ]
  ]
  where
    registered = Map.elems state.registrations
    contextRelation = \case
      Supplied supply   -> Relation SuppliedContext (EpisodeNode supply.episode) (ContextNode supply.reference) BySupplyRecord
      Read toolRead     -> Relation ObservedRead (EpisodeNode toolRead.episode) (ContextNode toolRead.reference) (ByToolRecord toolRead.record)
      Declared declared -> Relation (declaredKind declared.kind) (CandidateNode declared.candidate) (ContextNode declared.reference) (ByDeclaration declared.declarant)
      Inferred inferred -> Relation inferred.kind (CandidateNode inferred.candidate) (ContextNode inferred.reference) (ByInference inferred.source)
    declaredKind = \case
      Cites     -> CitedContext
      ReliesOn  -> ReliedOn
      Considers -> ConsideredContext
    judged judgement = case judgement.kind of
      RejectedAlternative -> Relation Rejected (ActorNode judgement.declarant) (CandidateNode judgement.candidate) (ByDeclaration judgement.declarant)
      SupersededBy other  -> Relation Superseded (CandidateNode other) (CandidateNode judgement.candidate) (ByDeclaration judgement.declarant)
