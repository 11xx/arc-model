-- | An immutable snapshot of the branch, bound to the contributors whose
-- work it carries and the coordinates the ledger recorded for them.
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
  , implementerModels :: !(Set ModelSlug)  -- ^ The models the ledger records for the patchset's implementers: its declared contributors, else its effective author. Empty where it records none. A mechanical replay carries the replayed patchset's coordinates here.
  , trailerImplementers :: !(Maybe (Set ModelSlug))  -- ^ The @Implemented-by@ values of the commits in the patchset's range, a projection; absent where the range was not read.
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
the patchset's own implementers. The models are the ledger's, so a commit
trailer never supplies one; a model compares by its slug once the effort is
dropped, and a read that recorded no model, or a ledger that records none
for the implementer, names nobody.
-}
implementerModelMatch :: Patchset -> Maybe ModelCoordinate -> Bool
implementerModelMatch patchset = \case
  Nothing    -> False
  Just model -> model.slug `Set.member` patchset.implementerModels
