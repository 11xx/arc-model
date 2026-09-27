{- | Distinct identifier types.

Every coordinate the model compares is its own type. A revision is not a
tree, a patchset is not a change, and a gate is not a declaration, so a
mix-up is a type error rather than a comparison that happens to succeed.
-}
module Arc.Model.Identifiers
    ( ChangeId(..)
    , PatchsetId(..)
    , Revision(..)
    , TreeId(..)
    , ActorId(..)
    , GateName(..)
    , DeclarationId(..)
    , EventId(..)
    , FindingId(..)
    , DebtId(..)
    , ClaimId(..)
    , HoldId(..)
    , FailureLabel(..)
    , TargetBranch(..)
    , ProbeCommand(..)
    , EnvironmentId(..)
    ) where

import Data.String ( IsString )


newtype ChangeId = ChangeId String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

newtype PatchsetId = PatchsetId Int
  deriving stock (Eq, Ord, Show)
  deriving newtype (Enum)

newtype Revision = Revision String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

newtype TreeId = TreeId String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

newtype ActorId = ActorId String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

newtype GateName = GateName String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

newtype DeclarationId = DeclarationId String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

newtype EventId = EventId Int
  deriving stock (Eq, Ord, Show)
  deriving newtype (Enum)

newtype FindingId = FindingId Int
  deriving stock (Eq, Ord, Show)
  deriving newtype (Enum)

newtype DebtId = DebtId Int
  deriving stock (Eq, Ord, Show)
  deriving newtype (Enum)

newtype ClaimId = ClaimId Int
  deriving stock (Eq, Ord, Show)
  deriving newtype (Enum)

newtype HoldId = HoldId Int
  deriving stock (Eq, Ord, Show)
  deriving newtype (Enum)

newtype FailureLabel = FailureLabel String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

newtype TargetBranch = TargetBranch String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

-- | The command a gate declares to name the environment it runs in.
newtype ProbeCommand = ProbeCommand String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

-- | The identity a probe yields: a digest of what it printed, so two
-- environments compare by what the probe saw and never by name.
newtype EnvironmentId = EnvironmentId String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)
