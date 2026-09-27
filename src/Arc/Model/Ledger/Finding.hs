-- | A problem a review raised. 'audit' marks a finding raised after
-- integration, which is deliberately outside the shipped set.
module Arc.Model.Ledger.Finding ( Finding(..) ) where

import Arc.Model.Identifiers


data Finding = Finding
  { event     :: !EventId
  , findingId :: !FindingId
  , patchset  :: !PatchsetId
  , actor     :: !ActorId
  , blocking  :: !Bool
  , audit     :: !Bool
  }
  deriving stock (Eq, Ord, Show)
