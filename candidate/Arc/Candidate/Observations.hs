{- | Everything the candidate model is told at decision time.

The model reads no clock, repository, or provider. The target, the
environment the decision is made in, the versions a provider holds, and the
provider's durable-capture guarantees arrive here, and any of them may be
unknown.
-}
module Arc.Candidate.Observations
    ( Observations(..)
    , captureOf
    ) where

import Arc.Candidate.Context ( Capture, ContextKey, Locator )
import Arc.Candidate.Identifiers ( VersionId )
import Arc.Model.Identifiers ( EnvironmentId, Revision )
import Arc.Model.Observed ( Observed(..) )


data Observations = Observations
  { target      :: !(Observed Revision)
  , environment :: !(Observed EnvironmentId)
  , held        :: ![(Locator, [VersionId])]   -- ^ Versions a provider holds per locator, oldest first.
  , captures    :: ![(ContextKey, Capture)]    -- ^ The capture guarantee a provider reported per version.
  }
  deriving stock (Eq, Show)

-- | The capture guarantee observed for one referenced version. A version
-- the provider reported nothing about is 'Omitted'.
captureOf :: Observations -> ContextKey -> Observed Capture
captureOf observations key = maybe Omitted Observed (lookup key observations.captures)
