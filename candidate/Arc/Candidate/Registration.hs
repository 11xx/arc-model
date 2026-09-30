{- | A candidate registration: immutable content and provenance.

A registration names its content tree, an immutable brief reference, its
producer identities, its parent candidates, the registrations it adopts,
and the work episodes it cites. It names no change: registering an
alternative never opens one. Two registrations of one tree are two
identities and share nothing but the tree.

A parent is registered under the same contract as its child, so a parent
chain never crosses a contract. Content carried into another contract is
an adoption, which makes the adopted registration no ancestor.
-}
module Arc.Candidate.Registration
    ( Registration(..)
    , Contract
    , contractOf
    ) where

import Arc.Candidate.Context ( ContextRef(..), Locator )
import Arc.Candidate.Identifiers
import Arc.Model.Identifiers ( ActorId, TreeId )
import Arc.Model.Observed ( Observed )

import Data.Set ( Set )


data Registration = Registration
  { candidateId :: !CandidateId
  , tree        :: !TreeId
  , brief       :: !ContextRef
  , producers   :: !(Set ActorId)
  , parents     :: ![CandidateId]
  , adopts      :: ![CandidateId]
  , episodes    :: ![EpisodeId]
  }
  deriving stock (Eq, Ord, Show)

-- | The brief a registration answers, at the version it was registered
-- against. Coverage of the brief is no part of it.
type Contract = (Locator, Observed VersionId)

contractOf :: Registration -> Contract
contractOf registered = (registered.brief.locator, registered.brief.version)
