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
    , ProbeName(..)
    , ModelSlug(..)
    , Effort(..)
    , RouteVersion(..)
    , ModelCoordinate(..)
    , modelCoordinate
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

-- | The name a brief gives one of its acceptance probes.
newtype ProbeName = ProbeName String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

-- | A model with its effort dropped: the string two models are compared by.
-- Arc holds no alias table, so a model a trailer spells another way is
-- another model.
newtype ModelSlug = ModelSlug String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

-- | The effort a coordinate's trailing @#suffix@ names.
newtype Effort = Effort String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

-- | The routing version that selected or assessed a read, a coordinate and
-- nothing else.
newtype RouteVersion = RouteVersion String
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)

-- | A model as an event recorded it: the model, and the effort its
-- coordinate names where it names one.
data ModelCoordinate = ModelCoordinate
  { slug   :: !ModelSlug
  , effort :: !(Maybe Effort)
  }
  deriving stock (Eq, Ord, Show)

-- | Split a recorded @model#effort@ coordinate at its trailing suffix.
modelCoordinate :: String -> ModelCoordinate
modelCoordinate recorded = case break (== '#') recorded of
  (model, '#' : effort) -> ModelCoordinate { slug = ModelSlug model, effort = Just (Effort effort) }
  (model, _noEffort)    -> ModelCoordinate { slug = ModelSlug model, effort = Nothing }
