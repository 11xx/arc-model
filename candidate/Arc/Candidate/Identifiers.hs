{- | Identifier types the candidate protocol adds.

The coordinates it shares with the existing-authorization model — trees,
revisions, actors, gates, declarations, environments, changes, patchsets —
come from "Arc.Model.Identifiers". The ones here name objects that model
has no reason to know: registrations, episodes, evaluation and review
records, selections, tool records, and the locators of context.
-}
module Arc.Candidate.Identifiers
    ( CandidateId(..)
    , EpisodeId(..)
    , EvaluationId(..)
    , ReviewId(..)
    , SelectionId(..)
    , ToolRecordId(..)
    , JournalId(..)
    , ArtifactName(..)
    , RepositoryId(..)
    , ContentId(..)
    , PathName(..)
    , VersionId(..)
    , InferenceSource(..)
    ) where

import Data.String ( IsString )


-- | One immutable registration. Two registrations of one tree are two
-- identifiers.
newtype CandidateId = CandidateId String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

-- | One span of temporal work activity.
newtype EpisodeId = EpisodeId String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

newtype EvaluationId = EvaluationId String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

newtype ReviewId = ReviewId String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

newtype SelectionId = SelectionId String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

-- | A tool's own record of an operation it performed, such as a read.
newtype ToolRecordId = ToolRecordId String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

-- | The project or journal that owns an artifact's namespace.
newtype JournalId = JournalId String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

-- | An artifact's complete filename: timestamp, slug, kind, and any
-- collision suffix.
newtype ArtifactName = ArtifactName String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

newtype RepositoryId = RepositoryId String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

-- | A revision, blob, or content digest naming what a file locator reads.
newtype ContentId = ContentId String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

newtype PathName = PathName String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

-- | The version of a referenced object that was actually observed: a body
-- digest or an event frontier.
newtype VersionId = VersionId String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

-- | What an inferred relation was inferred from.
newtype InferenceSource = InferenceSource String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)
