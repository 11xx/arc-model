{- | A decision made outside arc about an exact revision.

The receiver of a contribution decides it in its own forge, and the
operator records that decision here with its provenance. It is kept apart
from verdicts arc witnessed: arc can check the revision it names and
nothing about who decided.
-}
module Arc.Model.Ledger.ExternalVerdict
    ( ExternalKind(..)
    , ExternalVerdict(..)
    ) where

import Arc.Model.Identifiers


data ExternalKind = ExternalApproved
                  | ExternalChangesRequested
                  | ExternalRejected
  deriving stock (Eq, Ord, Show)

data ExternalVerdict = ExternalVerdict
  { event     :: !EventId
  , revision  :: !Revision       -- ^ The exact revision the decision covered.
  , kind      :: !ExternalKind
  , reference :: !String         -- ^ Where the decision lives, opaque to arc.
  }
  deriving stock (Eq, Ord, Show)
