{- | Typed relationships, each typed by who can establish it.

An observed read comes only from a tool's record of the read, with the
coverage it recorded. Supplying context to an operation is the operation's
own record and establishes no read. Citing, relying on, and considering are
attributed declarations: claims a projection shows as claims. An inferred
relation names what it was inferred from and bears no authority.
-}
module Arc.Candidate.Relation
    ( Supply(..)
    , ToolRead(..)
    , DeclaredKind(..)
    , Declaration(..)
    , Inference(..)
    , ContextRelation(..)
    , JudgementKind(..)
    , Judgement(..)
    , RelationKind(..)
    , Node(..)
    , Establishment(..)
    , Relation(..)
    , Standing(..)
    , standing
    ) where

import Arc.Candidate.Context ( ContextRef )
import Arc.Candidate.Identifiers
import Arc.Model.Identifiers ( ActorId, TreeId )


-- | Context an operation supplied to an episode: available, not read.
data Supply = Supply
  { episode   :: !EpisodeId
  , reference :: !ContextRef
  }
  deriving stock (Eq, Ord, Show)

-- | A tool's record of a read an episode performed, and what it covered.
data ToolRead = ToolRead
  { episode   :: !EpisodeId
  , record    :: !ToolRecordId
  , reference :: !ContextRef
  }
  deriving stock (Eq, Ord, Show)

data DeclaredKind = Cites
                  | ReliesOn
                  | Considers
  deriving stock (Eq, Ord, Show, Enum, Bounded)

{- | An attributed claim about a candidate's context. A citation names the
tool record the claim rests on; it is checked when the claim is recorded
and never turns the claim into the read it cites.
-}
data Declaration = Declaration
  { candidate :: !CandidateId
  , kind      :: !DeclaredKind
  , reference :: !ContextRef
  , declarant :: !ActorId
  , citation  :: !(Maybe ToolRecordId)
  }
  deriving stock (Eq, Ord, Show)

-- | A relation nobody recorded or declared, labelled with its source.
data Inference = Inference
  { candidate :: !CandidateId
  , kind      :: !RelationKind
  , reference :: !ContextRef
  , source    :: !InferenceSource
  }
  deriving stock (Eq, Ord, Show)

data ContextRelation = Supplied !Supply
                     | Read !ToolRead
                     | Declared !Declaration
                     | Inferred !Inference
  deriving stock (Eq, Ord, Show)

data JudgementKind = RejectedAlternative
                   | SupersededBy !CandidateId
  deriving stock (Eq, Ord, Show)

-- | An attributed judgement about a candidate as an alternative.
data Judgement = Judgement
  { candidate :: !CandidateId
  , kind      :: !JudgementKind
  , declarant :: !ActorId
  }
  deriving stock (Eq, Ord, Show)

data RelationKind = SuppliedContext
                  | ObservedRead
                  | CitedContext
                  | ReliedOn
                  | ConsideredContext
                  | Rejected
                  | Superseded
                  | Produced
                  | Adopted
                  | Evaluated
                  | Reviewed
                  | Selected
                  | Promoted
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data Node = ActorNode !ActorId
          | CandidateNode !CandidateId
          | EpisodeNode !EpisodeId
          | ContextNode !ContextRef
          | TreeNode !TreeId
          | EvaluationNode !EvaluationId
          | ReviewNode !ReviewId
          | SelectionNode !SelectionId
  deriving stock (Eq, Ord, Show)

-- | Who established a relation.
data Establishment = ByToolRecord !ToolRecordId
                   | BySupplyRecord
                   | ByDeclaration !ActorId
                   | ByInference !InferenceSource
                   | ByLedger
  deriving stock (Eq, Ord, Show)

-- | One edge of the evidence graph.
data Relation = Relation
  { kind          :: !RelationKind
  , from          :: !Node
  , to            :: !Node
  , establishment :: !Establishment
  }
  deriving stock (Eq, Ord, Show)

-- | How a projection presents a relation: as a recorded fact, as a claim,
-- or as an inference.
data Standing = StandsAsRecord
              | StandsAsClaim
              | StandsAsInference
  deriving stock (Eq, Ord, Show)

standing :: Establishment -> Standing
standing = \case
  ByToolRecord _  -> StandsAsRecord
  BySupplyRecord  -> StandsAsRecord
  ByLedger        -> StandsAsRecord
  ByDeclaration _ -> StandsAsClaim
  ByInference _   -> StandsAsInference
