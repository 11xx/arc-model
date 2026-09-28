{- | Validating a named selection, and re-checking it at promotion.

'evaluate' takes a proposal and answers with every ground that stands
against it, or with the basis it would rest on. It never picks a candidate
and never writes: the choice is the proposal's, and recording it is the
caller's. The reuse policy is an argument, because the model does not know
which policy holds.

'promote' re-checks a basis against the observations at promotion time. A
basis whose target has moved stands down; it is never reused.
-}
module Arc.Candidate.Selection
    ( evaluate
    , refusals
    , contributorsOf
    , shippedTree
    , evidenceShortfall
    , reviewShortfall
    , readSatisfaction
    , promote
    ) where

import Arc.Candidate.Basis
import Arc.Candidate.Context ( ContextRef(..), covers )
import Arc.Candidate.Evaluation
import Arc.Candidate.Identifiers
import Arc.Candidate.Observations ( Observations(..) )
import Arc.Candidate.Registration ( Registration(..) )
import Arc.Candidate.Relation
import Arc.Candidate.State
import Arc.Model.Identifiers ( ActorId, DeclarationId, EnvironmentId, GateName, TreeId )
import Arc.Model.Observed ( Observed(..) )

import Data.Either ( lefts, rights )
import Data.List.NonEmpty ( NonEmpty, nonEmpty )
import Data.Map.Strict qualified as Map
import Data.Maybe ( listToMaybe )
import Data.Set ( Set )
import Data.Set qualified as Set


-- | Every ground standing against a proposal, or the basis it rests on.
evaluate :: ReusePolicy -> Requirements -> Observations -> State -> Proposal -> Either (NonEmpty Refusal) SelectionBasis
evaluate policy requirements observations state proposal = case registration state proposal.chosen of
  Nothing     -> Left (pure (RefusedUnknownCandidate proposal.chosen))
  Just chosen -> case nonEmpty grounds of
    Just stood    -> Left stood
    Nothing       -> Right SelectionBasis
      { selectionId  = proposal.selectionId
      , chosen       = proposal.chosen
      , destination  = proposal.destination
      , target       = proposal.target
      , tree         = shippedTree chosen proposal
      , contributors = contributorsOf chosen proposal
      , selector     = proposal.selector
      , gates        = rights gateAnswers
      , review       = either (const Nothing) id reviewAnswer
      , reads        = rights readAnswers
      , reuse        = policy
      }
    where
      grounds = concat
        [ targetGrounds
        , environmentGrounds
        , lefts gateAnswers
        , lefts [reviewAnswer]
        , lefts readAnswers
        ]
      targetGrounds = case observations.target of
        Omitted -> [RefusedTargetUnobserved]
        Observed seen
          | seen /= proposal.target -> [RefusedTargetMoved proposal.target seen]
          | otherwise               -> []
      environmentGrounds = case observations.environment of
        Omitted | not (null requirements.gates) -> [RefusedEnvironmentUnobserved]
        _known                                  -> []
      gateAnswers = case observations.environment of
        Omitted       -> []
        Observed here ->
          [ gateAnswer policy state chosen proposal here gate declaration
          | (gate, declaration) <- requirements.gates
          ]
      reviewAnswer
        | requirements.independentReview = Just <$> reviewAnswerFor state chosen proposal
        | otherwise                      = Right Nothing
      readAnswers = [ readAnswer state chosen requirement | requirement <- requirements.reads ]

-- | The grounds alone: empty exactly when 'evaluate' permits.
refusals :: ReusePolicy -> Requirements -> Observations -> State -> Proposal -> [Refusal]
refusals policy requirements observations state proposal =
  either (foldr (:) []) (const []) (evaluate policy requirements observations state proposal)

-- | The content shipped: the last repair's tree, or the registration's.
shippedTree :: Registration -> Proposal -> TreeId
shippedTree chosen proposal = maybe chosen.tree (.tree) (listToMaybe (reverse proposal.repairs))

-- | The chosen registration's producers and every repair author. A lead
-- who repairs is a contributor, never only the selector.
contributorsOf :: Registration -> Proposal -> Set ActorId
contributorsOf chosen proposal = chosen.producers <> Set.fromList (map (.author) proposal.repairs)

-- gates

gateAnswer :: ReusePolicy -> State -> Registration -> Proposal -> EnvironmentId -> GateName -> DeclarationId -> Either Refusal (GateName, EvaluationId)
gateAnswer policy state chosen proposal here gate declaration =
  case [ evaluation | (evaluation, Nothing) <- judged ] of
    evaluation : _ -> Right (gate, evaluation)
    []             -> Left (RefusedGate gate [ (evaluation, shortfall) | (evaluation, Just shortfall) <- judged ])
  where
    named  = [ evaluation | evaluation <- proposal.evaluations, forGate evaluation ]
    judged = [ (evaluation, evidenceShortfall policy state chosen proposal here declaration evaluation) | evaluation <- named ]
    forGate evaluation = maybe True (\e -> e.gate == gate) (Map.lookup evaluation state.evaluations)

{- | Why a named evaluation does not answer for a gate, or 'Nothing' when it
does. The registration is checked under the reuse policy first, then the
coordinates, then the observed outcome.
-}
evidenceShortfall :: ReusePolicy -> State -> Registration -> Proposal -> EnvironmentId -> DeclarationId -> EvaluationId -> Maybe EvidenceShortfall
evidenceShortfall policy state chosen proposal here declaration evaluationId = case Map.lookup evaluationId state.evaluations of
  Nothing -> Just EvaluationUnrecorded
  Just evaluation
    | evaluation.candidate /= chosen.candidateId
    , policy == ReuseNever                          -> Just (OtherRegistration evaluation.candidate)
    | evaluation.tree /= shippedTree chosen proposal -> Just (OtherTree evaluation.tree)
    | evaluation.declaration /= declaration         -> Just (OtherDeclaration evaluation.declaration)
    | otherwise -> case (evaluation.environment, evaluation.outcome) of
        (Omitted, _outcome)                        -> Just EnvironmentUnrecorded
        (Observed there, _outcome) | there /= here -> Just (OtherEnvironment there)
        (_here, Omitted)                           -> Just OutcomeUnknown
        (_here, Observed Failed)                   -> Just OutcomeFailed
        (_here, Observed Passed)                   -> Nothing

-- review

reviewAnswerFor :: State -> Registration -> Proposal -> Either Refusal ReviewId
reviewAnswerFor state chosen proposal = case [ review | (review, Nothing) <- judged ] of
  review : _ -> Right review
  []         -> Left (RefusedNoIndependentReview [ (review, shortfall) | (review, Just shortfall) <- judged ])
  where
    judged = [ (review, reviewShortfall state chosen proposal review) | review <- proposal.reviews ]

{- | Why a named review does not authorize the selection, or 'Nothing' when
it does. Review authority belongs to the registration the review names: an
equal tree does not carry it to another registration.
-}
reviewShortfall :: State -> Registration -> Proposal -> ReviewId -> Maybe ReviewShortfall
reviewShortfall state chosen proposal reviewId = case Map.lookup reviewId state.reviews of
  Nothing -> Just ReviewUnrecorded
  Just review
    | review.candidate /= chosen.candidateId                     -> Just (ReviewOfOtherCandidate review.candidate)
    | review.tree /= shippedTree chosen proposal                 -> Just (ReviewOfOtherTree review.tree)
    | review.reviewer `Set.member` contributorsOf chosen proposal -> Just (ReviewerIsContributor review.reviewer)
    | review.kind == RequestsChanges                             -> Just ReviewRequestsChanges
    | otherwise                                                  -> Nothing

-- reads

readAnswer :: State -> Registration -> ReadRequirement -> Either Refusal (ReadRequirement, ToolRecordId)
readAnswer state chosen requirement = case readSatisfaction state chosen requirement of
  Right toolRecord -> Right (requirement, toolRecord)
  Left shortfall   -> Left (RefusedReadUnsatisfied requirement shortfall)

{- | A read requirement is met only by a tool's record of a read, made by an
episode the chosen registration cites, of exactly the required version,
with an observed coverage that covers the required extent. A declaration,
a supply, or an inference never meets one; each is reported as what it is.
-}
readSatisfaction :: State -> Registration -> ReadRequirement -> Either ReadShortfall ToolRecordId
readSatisfaction state chosen requirement = case [ r.record | r <- found, coverageOf r == Just True ] of
  toolRecord : _ -> Right toolRecord
  []
    | not (null partial)  -> Left (ReadPartial partial)
    | not (null unknown)  -> Left (ReadCoverageUnknown unknown)
    | not (null declared) -> Left (OnlyDeclared declared)
    | not (null inferred) -> Left (OnlyInferred inferred)
    | supplied            -> Left OnlySupplied
    | otherwise           -> Left NotRead
  where
    sameVersion reference = reference.locator == requirement.locator && reference.version == Observed requirement.version
    found    = [ r | r <- toolReads state, r.episode `elem` chosen.episodes, sameVersion r.reference ]
    coverageOf r = case r.reference.coverage of
      Observed extent -> Just (extent `covers` requirement.extent)
      Omitted         -> Nothing
    partial  = [ r.record | r <- found, coverageOf r == Just False ]
    unknown  = [ r.record | r <- found, coverageOf r == Nothing ]
    declared = [ d.declarant | d <- declarations state, d.candidate == chosen.candidateId, sameVersion d.reference ]
    inferred = [ i.source | Inferred i <- state.context, i.candidate == chosen.candidateId, sameVersion i.reference ]
    supplied = or [ sameVersion s.reference && s.episode `elem` chosen.episodes | Supplied s <- state.context ]

-- promotion

-- | Re-check a basis at promotion time. The target observed then must be the
-- one the selection was decided against.
promote :: Observations -> SelectionBasis -> Either Refusal PromotionPlan
promote observations basis = case observations.target of
  Observed seen | seen == basis.target -> Right (PromotionPlan basis)
  Observed seen                        -> Left (RefusedBasisMoved basis.target (Just seen))
  Omitted                              -> Left (RefusedBasisMoved basis.target Nothing)
