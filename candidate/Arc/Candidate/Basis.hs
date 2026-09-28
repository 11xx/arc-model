{- | Selection proposals, their requirements, the basis a permitted selection
rests on, and the structured grounds of a refusal.

A proposal names everything a selection relies on; the model validates it
and never chooses. A basis names the facts the permission rested on, and a
refusal names the facts that stood in the way.
-}
module Arc.Candidate.Basis
    ( Destination(..)
    , Repair(..)
    , ReadRequirement(..)
    , Requirements(..)
    , Proposal(..)
    , SelectionBasis(..)
    , EvidenceShortfall(..)
    , ReviewShortfall(..)
    , ReadShortfall(..)
    , Refusal(..)
    , refusalTag
    , PromotionPlan(..)
    , Promotion(..)
    ) where

import Arc.Candidate.Context ( Extent, Locator )
import Arc.Candidate.Evaluation ( ReusePolicy )
import Arc.Candidate.Identifiers
import Arc.Model.Identifiers ( ActorId, ChangeId, DeclarationId, EnvironmentId, GateName, PatchsetId, Revision, TreeId )

import Data.Set ( Set )


-- | The change and patchset a selected candidate is promoted into.
data Destination = Destination
  { change   :: !ChangeId
  , patchset :: !PatchsetId
  }
  deriving stock (Eq, Ord, Show)

-- | Work a selector adds to the chosen content, and the tree it leaves.
data Repair = Repair
  { author :: !ActorId
  , tree   :: !TreeId
  }
  deriving stock (Eq, Ord, Show)

-- | A version of some context that the chosen candidate's episodes must
-- have read, and how much of it.
data ReadRequirement = ReadRequirement
  { locator :: !Locator
  , version :: !VersionId
  , extent  :: !Extent
  }
  deriving stock (Eq, Ord, Show)

-- | The acceptance contract a selection is checked against.
data Requirements = Requirements
  { gates             :: ![(GateName, DeclarationId)]
  , independentReview :: !Bool
  , reads             :: ![ReadRequirement]
  }
  deriving stock (Eq, Show)

-- | A named selection: the choice is the caller's, never the model's.
data Proposal = Proposal
  { selectionId :: !SelectionId
  , chosen      :: !CandidateId
  , destination :: !Destination
  , target      :: !Revision
  , evaluations :: ![EvaluationId]
  , reviews     :: ![ReviewId]
  , selector    :: !ActorId
  , repairs     :: ![Repair]
  }
  deriving stock (Eq, Show)

{- | What a permitted selection rests on.

'tree' is the content shipped: the last repair's tree, or the chosen
registration's. 'contributors' are the chosen registration's producers and
every repair author. 'reuse' is the policy the evaluations were judged
under.
-}
data SelectionBasis = SelectionBasis
  { selectionId  :: !SelectionId
  , chosen       :: !CandidateId
  , destination  :: !Destination
  , target       :: !Revision
  , tree         :: !TreeId
  , contributors :: !(Set ActorId)
  , selector     :: !ActorId
  , gates        :: ![(GateName, EvaluationId)]
  , review       :: !(Maybe ReviewId)
  , reads        :: ![(ReadRequirement, ToolRecordId)]
  , reuse        :: !ReusePolicy
  }
  deriving stock (Eq, Ord, Show)

-- | Why one named evaluation does not answer for a required gate.
data EvidenceShortfall = EvaluationUnrecorded
                       | OtherRegistration !CandidateId
                       | OtherTree !TreeId
                       | OtherDeclaration !DeclarationId
                       | EnvironmentUnrecorded
                       | OtherEnvironment !EnvironmentId
                       | OutcomeUnknown
                       | OutcomeFailed
  deriving stock (Eq, Ord, Show)

-- | Why one named review does not authorize the selection.
data ReviewShortfall = ReviewUnrecorded
                     | ReviewOfOtherCandidate !CandidateId
                     | ReviewOfOtherTree !TreeId
                     | ReviewerIsContributor !ActorId
                     | ReviewRequestsChanges
  deriving stock (Eq, Ord, Show)

-- | Why a read requirement is not met. Each carries what was found instead,
-- so a claim or a partial read is shown for what it is.
data ReadShortfall = ReadCoverageUnknown ![ToolRecordId]
                   | ReadPartial ![ToolRecordId]
                   | OnlyDeclared ![ActorId]
                   | OnlyInferred ![InferenceSource]
                   | OnlySupplied
                   | NotRead
  deriving stock (Eq, Ord, Show)

data Refusal = RefusedUnknownCandidate !CandidateId
             | RefusedTargetUnobserved
             | RefusedTargetMoved !Revision !Revision                         -- ^ Proposed, then observed.
             | RefusedEnvironmentUnobserved
             | RefusedGate !GateName ![(EvaluationId, EvidenceShortfall)]
             | RefusedNoIndependentReview ![(ReviewId, ReviewShortfall)]
             | RefusedReadUnsatisfied !ReadRequirement !ReadShortfall
             | RefusedBasisMoved !Revision !(Maybe Revision)                   -- ^ At promotion: the basis target, then what was observed.
  deriving stock (Eq, Ord, Show)

refusalTag :: Refusal -> String
refusalTag = \case
  RefusedUnknownCandidate _    -> "unknown-candidate"
  RefusedTargetUnobserved      -> "target-unobserved"
  RefusedTargetMoved _ _       -> "target-moved"
  RefusedEnvironmentUnobserved -> "environment-unobserved"
  RefusedGate _ _              -> "gate"
  RefusedNoIndependentReview _ -> "no-independent-review"
  RefusedReadUnsatisfied _ _   -> "read-unsatisfied"
  RefusedBasisMoved _ _        -> "basis-moved"

-- | A permission re-checked against the observations at promotion time.
-- It is not the promotion: only 'Arc.Candidate.State.recordPromotion'
-- records one, from an observed effect.
newtype PromotionPlan = PromotionPlan SelectionBasis
  deriving stock (Eq, Show)

-- | A promotion the shell performed and observed.
data Promotion = Promotion
  { selection :: !SelectionId
  , merged    :: !Revision
  }
  deriving stock (Eq, Ord, Show)
