{- | A candidate registration: immutable content and provenance.

A registration names its content tree, an immutable brief reference, its
producer identities, its parent candidates, and the work episodes it cites.
It names no change: registering an alternative never opens one. Two
registrations of one tree are two identities and share nothing but the
tree.
-}
module Arc.Candidate.Registration ( Registration(..) ) where

import Arc.Candidate.Context ( ContextRef )
import Arc.Candidate.Identifiers
import Arc.Model.Identifiers ( ActorId, TreeId )

import Data.Set ( Set )


data Registration = Registration
  { candidateId :: !CandidateId
  , tree        :: !TreeId
  , brief       :: !ContextRef
  , producers   :: !(Set ActorId)
  , parents     :: ![CandidateId]
  , episodes    :: ![EpisodeId]
  }
  deriving stock (Eq, Ord, Show)
