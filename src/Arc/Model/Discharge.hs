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
    ) where

import Arc.Model.Coverage ( ReadEvidence(..), auditIsIndependent, debtKindFor )
import Arc.Model.Identifiers
import Arc.Model.Ledger
import Arc.Model.State


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
