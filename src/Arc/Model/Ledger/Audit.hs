-- | A review recorded after integration, anchored to the integrated
-- revision. Audit findings are deliberately outside the shipped set.
module Arc.Model.Ledger.Audit ( Audit(..) ) where

import Arc.Model.Identifiers
import Arc.Model.Ledger.Verdict ( VerdictKind )


data Audit = Audit
  { event    :: !EventId
  , revision :: !Revision
  , kind     :: !VerdictKind
  , actor    :: !ActorId
  , assumed  :: !Bool
  , findings :: ![FindingId]
  }
  deriving stock (Eq, Ord, Show)
