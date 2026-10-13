-- | An immutable snapshot of the branch, bound to the contributors whose
-- work it carries.
module Arc.Model.Ledger.Patchset
    ( Patchset(..)
    , effectiveContributors
    , implementerModelMatch
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
  , brief        :: !(Maybe EventId)  -- ^ The brief in force when the patchset was recorded.
  , implementers :: !(Maybe (Set ModelSlug))  -- ^ The @Implemented-by@ models of the commits in the patchset's range; absent where the range cannot be read.
  }
  deriving stock (Eq, Ord, Show)

-- C1, C4
-- | A contributor set that was never declared is the author alone. The
-- synthesized set is a compatibility reading, not a declaration.
effectiveContributors :: Patchset -> Set ActorId
effectiveContributors patchset
  | Set.null patchset.contributors = Set.singleton patchset.author
  | otherwise                      = patchset.contributors

-- C4
{- | Whether a read recorded under this model is a second reading by one of
the patchset's own implementers. A model compares by its slug once the
effort is dropped; a read that recorded no model, or a range that cannot be
read, names nobody.
-}
implementerModelMatch :: Patchset -> Maybe ModelCoordinate -> Bool
implementerModelMatch patchset = \case
  Nothing    -> False
  Just model -> maybe False (Set.member model.slug) patchset.implementers
