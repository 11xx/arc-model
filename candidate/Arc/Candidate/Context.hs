{- | References to context: a stable locator, and what was actually observed.

A reference names where an object lives and, separately, the version and
coverage an observer saw. The locator is an address; the version is what
makes the reference durable. Resolution goes through the observed version,
so an artifact amended after the observation still resolves to the text
the observation saw, and a reference whose version was never observed
resolves to nothing rather than to whatever the locator holds now.
-}
module Arc.Candidate.Context
    ( ArtifactLocator(..)
    , FileLocator(..)
    , Locator(..)
    , Extent(..)
    , covers
    , ContextRef(..)
    , ContextKey
    , contextKey
    , Capture(..)
    , Resolution(..)
    , resolve
    ) where

import Arc.Candidate.Identifiers
import Arc.Model.Observed ( Observed(..) )


-- | A journal artifact: its owning journal and complete filename.
data ArtifactLocator = ArtifactLocator
  { journal  :: !JournalId
  , filename :: !ArtifactName
  }
  deriving stock (Eq, Ord, Show)

-- | A file: its repository, the revision or content it was read at, and its
-- path. A path alone is not an identity.
data FileLocator = FileLocator
  { repository :: !RepositoryId
  , content    :: !ContentId
  , path       :: !PathName
  }
  deriving stock (Eq, Ord, Show)

data Locator = LocatesArtifact !ArtifactLocator
             | LocatesFile !FileLocator
  deriving stock (Eq, Ord, Show)

-- | The part of an object an observation covers: all of it, or an
-- inclusive line range.
data Extent = Whole
            | Lines !Int !Int
  deriving stock (Eq, Ord, Show)

-- | Whether an observed extent covers a required one.
covers :: Extent -> Extent -> Bool
covers Whole            _                = True
covers (Lines _ _)      Whole            = False
covers (Lines from to) (Lines from' to') = from <= from' && to' <= to

{- | A reference to context as it was observed.

'version' and 'coverage' are what the observer actually saw. Either may be
'Omitted'; an omitted coverage is unknown, never complete.
-}
data ContextRef = ContextRef
  { locator  :: !Locator
  , version  :: !(Observed VersionId)
  , coverage :: !(Observed Extent)
  }
  deriving stock (Eq, Ord, Show)

-- | A referenced object at one version: the unit a provider retains.
type ContextKey = (Locator, VersionId)

contextKey :: ContextRef -> Maybe ContextKey
contextKey reference = case reference.version of
  Observed version -> Just (reference.locator, version)
  Omitted          -> Nothing

-- | A provider's durable-capture guarantee for one referenced version.
data Capture = Pinned
             | Unpinned
  deriving stock (Eq, Ord, Show)

-- | What a reference resolves to, given the versions a provider holds.
data Resolution = ResolvedAt !VersionId ![VersionId]  -- ^ The observed version, and the versions recorded after it.
                | VersionUnobserved                   -- ^ The reference never named a version.
                | VersionUnavailable !VersionId       -- ^ The provider does not hold the observed version.
  deriving stock (Eq, Show)

-- | Resolve a reference against the versions a provider holds for each
-- locator, oldest first. The newest version never stands in for the one
-- that was observed.
resolve :: [(Locator, [VersionId])] -> ContextRef -> Resolution
resolve held reference = case reference.version of
  Omitted          -> VersionUnobserved
  Observed version -> case break (== version) versions of
    (_before, _seen : after) -> ResolvedAt version after
    (_before, [])            -> VersionUnavailable version
  where
    versions = concat [ vs | (locator, vs) <- held, locator == reference.locator ]
