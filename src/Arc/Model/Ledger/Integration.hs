{- | What one integration consumed and the exact facts it relied upon.

Later reviews and audits are separate events; they never rewrite this
record.
-}
module Arc.Model.Ledger.Integration
    ( Authorization(..)
    , authorizationDebts
    , IntegrationRecord(..)
    ) where

import Arc.Model.Declaration ( Declaration )
import Arc.Model.Identifiers
import Arc.Model.Policy ( Policy )


{- | What a recorded merge actually rested on, read from the ledger. An
external approval is named only when no local authorization stood: arc can
verify the revision it covers and nothing about who gave it.
-}
data Authorization = AuthorizedByVerdict EventId
                   | AuthorizedByWaiver DebtId
                   | AuthorizedByVerdictUnderWaiver EventId DebtId
                   | AuthorizedByExternalVerdict EventId
  deriving stock (Eq, Ord, Show)

-- | The debt declarations an authorization named.
authorizationDebts :: Authorization -> [DebtId]
authorizationDebts = \case
  AuthorizedByVerdict _                 -> []
  AuthorizedByWaiver debt               -> [debt]
  AuthorizedByVerdictUnderWaiver _ debt -> [debt]
  AuthorizedByExternalVerdict _         -> []

data IntegrationRecord = IntegrationRecord
  { event            :: !EventId
  , patchset         :: !PatchsetId
  , head             :: !Revision
  , targetBranch     :: !TargetBranch
  , targetBefore     :: !Revision
  , tree             :: !TreeId
  , authorization    :: !Authorization
  , gates            :: ![(GateName, EventId, DeclarationId)]
  , declarations     :: ![(GateName, Declaration)]            -- ^ Normalized values consumed by required gates.
  , prerequisites    :: ![(ChangeId, EventId)]
  , consumedFindings :: ![FindingId]
  , consumedHolds    :: ![HoldId]
  , policy           :: !Policy
  }
  deriving stock (Eq, Ord, Show)
