{- | A change-scoped contract naming acceptance probes.

A brief names the revision its premises were checked against, its base. A
probe is discharged by failing at the base and passing at the head, which
is what shows it tests the change rather than something already true.
-}
module Arc.Model.Ledger.Brief ( Brief(..) ) where

import Arc.Model.Identifiers


data Brief = Brief
  { event  :: !EventId
  , base   :: !(Maybe Revision)  -- ^ Nothing for a brief recorded without one, which no probe can be discharged against.
  , probes :: ![ProbeName]
  }
  deriving stock (Eq, Ord, Show)
