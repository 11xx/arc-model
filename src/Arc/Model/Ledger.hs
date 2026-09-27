{- | The append-only ledger.

Each record kind lives in its own module, so a module that updates one can
name it. This module gathers them into the event sum a history is made of.
-}
module Arc.Model.Ledger
    ( module Arc.Model.Ledger.Audit
    , module Arc.Model.Ledger.Claim
    , module Arc.Model.Ledger.Debt
    , module Arc.Model.Ledger.Disposition
    , module Arc.Model.Ledger.Finding
    , module Arc.Model.Ledger.Integration
    , module Arc.Model.Ledger.Patchset
    , module Arc.Model.Ledger.Verdict
    , module Arc.Model.Ledger.Verification
    , Closure(..)
    , Event(..)
    ) where

import Arc.Model.Identifiers
import Arc.Model.Ledger.Audit
import Arc.Model.Ledger.Claim
import Arc.Model.Ledger.Debt
import Arc.Model.Ledger.Disposition
import Arc.Model.Ledger.Finding
import Arc.Model.Ledger.Integration
import Arc.Model.Ledger.Patchset
import Arc.Model.Ledger.Verdict
import Arc.Model.Ledger.Verification


data Closure = ClosedAbandoned
             | ClosedSuperseded
  deriving stock (Eq, Ord, Show)

data Event = PatchsetRecorded Patchset
           | VerdictRecorded Verdict
           | FindingRecorded Finding
           | FindingDisposed Disposition
           | VerificationRecorded Verification
           | DebtDeclared Debt
           | AuditRecorded Audit
           | ClaimStarted Claim
           | ClaimExpired ClaimId
           | HoldSet HoldId
           | HoldReleased HoldId
           | ChangeClosed Closure
           | IteratingChanged Bool
           | IntegrationRecorded IntegrationRecord
  deriving stock (Eq, Ord, Show)
