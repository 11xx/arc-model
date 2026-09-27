-- | A liveness episode. Its expiry ends the claim, never the ledger facts
-- recorded while it ran.
module Arc.Model.Ledger.Claim ( Claim(..) ) where

import Arc.Model.Identifiers


data Claim = Claim
  { claimId :: !ClaimId
  , actor   :: !ActorId
  , expired :: !Bool
  }
  deriving stock (Eq, Ord, Show)
