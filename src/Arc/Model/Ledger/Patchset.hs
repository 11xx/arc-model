-- | An immutable snapshot of the branch, bound to the contributors whose
-- work it carries.
module Arc.Model.Ledger.Patchset
    ( Patchset(..)
    , effectiveContributors
    ) where

import Arc.Model.Identifiers

import Data.Set ( Set )
import Data.Set qualified as Set


data Patchset = Patchset
  { patchsetId   :: !PatchsetId
  , ordinal      :: !Int
  , revision     :: !Revision
  , tree         :: !TreeId
  , author       :: !ActorId
  , contributors :: !(Set ActorId)
  }
  deriving stock (Eq, Ord, Show)

-- | A contributor set that was never declared is the author alone. The
-- synthesized set is a compatibility reading, not a declaration.
effectiveContributors :: Patchset -> Set ActorId
effectiveContributors patchset
  | Set.null patchset.contributors = Set.singleton patchset.author
  | otherwise                      = patchset.contributors
