{- | Post-integration audits.

An audit is anchored to a revision that shipped, so it can never rewrite
the answer to what shipped with what review. A negative audit may fulfil a
coverage obligation: a read happened, and the problems it raised stay
open. Fulfilled is not approved, and the audit's verdict is its own field.
-}
module Arc.Model.Discharge
    ( AuditRefusal(..)
    , auditRefusalText
    , Discharge(..)
    , auditDischarges
    , admitAudit
    ) where

import Arc.Model.Coverage ( ReadEvidence(..), auditIsIndependent, debtKindFor )
import Arc.Model.Identifiers
import Arc.Model.Ledger
import Arc.Model.Policy ( Policy )
import Arc.Model.Policy qualified as Policy
import Arc.Model.State

import Data.Maybe ( isNothing )


data AuditRefusal = AuditWhileOpen
                  | AuditAssumedAuditor
                  | AuditAuditorNotIndependent
  deriving stock (Eq, Ord, Show)

auditRefusalText :: AuditRefusal -> String
auditRefusalText = \case
  AuditWhileOpen             -> "the change is open; an audit reviews a revision that shipped"
  AuditAssumedAuditor        -> "an approving audit needs a declared identity, not an assumed one"
  AuditAuditorNotIndependent -> "an approving audit must come from another identity"

{- | What an audit discharged, and what it left open. 'approves' is derived
from the audit alone and never from the fact that the read was fulfilled.
-}
data Discharge = Discharge
  { debt         :: !DebtId
  , kind         :: !DebtKind
  , read         :: !ReadEvidence
  , verdict      :: !VerdictKind
  , approves     :: !Bool
  , openFindings :: ![FindingId]
  }
  deriving stock (Eq, Ord, Show)

{- | Whether an audit is recorded at all. A change that did not integrate
has no shipped revision to audit. Where policy forbids self-approval, an
approving audit that is not independent would clear the obligation its own
author owes, and is refused; elsewhere it is recorded and discharges
nothing, since 'auditDischarges' still asks for independence.
-}
admitAudit :: Policy -> ChangeState -> Audit -> Either AuditRefusal ()
admitAudit policy state audit
  | isNothing (latestIntegration state) = Left AuditWhileOpen
  | audit.kind == Approved
  , policy.forbidSelfApproval
  , not (auditIsIndependent state audit)
  = Left (if audit.assumed then AuditAssumedAuditor else AuditAuditorNotIndependent)
  | otherwise = Right ()

-- | Decide what an audit does to a recorded obligation. The state must
-- already include the audit event and any findings it raised.
auditDischarges :: ChangeState -> Debt -> Audit -> Either AuditRefusal Discharge
auditDischarges state debt audit = case latestIntegration state of
  Nothing -> Left AuditWhileOpen
  Just _  -> case approvingRefusal of
    Just refusal -> Left refusal
    Nothing      -> Right Discharge
      { debt         = debt.debtId
      , kind         = debtKindFor state debt
      , read         = ReadByAudit audit.event
      , verdict      = audit.kind
      , approves     = audit.kind == Approved
      , openFindings = openAuditFindings state
      }
  where
    approvingRefusal
      | audit.kind /= Approved               = Nothing
      | audit.assumed                        = Just AuditAssumedAuditor
      | not (auditIsIndependent state audit) = Just AuditAuditorNotIndependent
      | otherwise                            = Nothing
