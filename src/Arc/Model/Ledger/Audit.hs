-- | A review recorded after integration, anchored to the integrated
-- revision. Audit findings are deliberately outside the shipped set.
module Arc.Model.Ledger.Audit
    ( Role(..)
    , Audit(..)
    ) where

import Arc.Model.Identifiers
import Arc.Model.Ledger.Assessment ( Assessment )
import Arc.Model.Ledger.Verdict ( VerdictKind )

import Data.Set ( Set )


{- | A role an auditor held beside authorship. The ledger records planning
and orchestration as the auditor's dirty context for routing, and
integrating somebody else's work credits no authorship; no rule reads these
roles.
-}
data Role = Planner
          | Orchestrator
          | Integrator
  deriving stock (Eq, Ord, Show)


data Audit = Audit
  { event      :: !EventId
  , revision   :: !Revision
  , kind       :: !VerdictKind
  , actor      :: !ActorId
  , assumed    :: !Bool
  , findings   :: ![FindingId]
  , model      :: !(Maybe ModelCoordinate)  -- ^ The model the audit recorded; absent for an audit by a person.
  , heldRoles  :: !(Set Role)               -- ^ The roles the auditor held beside authorship.
  , assessment :: !(Maybe Assessment)
  }
  deriving stock (Eq, Ord, Show)
