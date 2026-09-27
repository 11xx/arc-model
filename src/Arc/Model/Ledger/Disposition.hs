-- | What became of a finding.
module Arc.Model.Ledger.Disposition ( Disposition(..) ) where

import Arc.Model.Identifiers


data Disposition = Disposition
  { event    :: !EventId
  , finding  :: !FindingId
  , resolved :: !Bool
  }
  deriving stock (Eq, Ord, Show)
