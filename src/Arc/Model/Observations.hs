{- | Everything the model is told about the world at decision time.

The evaluated tree is explicit because a change behind its target evaluates
the merge, not its own head, and only Git can say what that tree is. The
environment each declared probe yields is explicit for the same reason: only
the checkout the decision is made in can answer, and a probe that failed
there answers nothing.
-}
module Arc.Model.Observations
    ( Observations(..)
    , IntegrationAuthority(..)
    ) where

import Arc.Model.Declaration ( Declaration )
import Arc.Model.Identifiers
import Arc.Model.Observed ( Observed )
import Arc.Model.Policy ( Policy )


{- | Whether the store the decision is made in may integrate at all. A store
paired with replicas integrates only while it holds the authority; an
unpaired store is its own authority.
-}
data IntegrationAuthority = AuthorityUnpaired
                          | AuthorityHeld
                          | AuthorityWithheld
  deriving stock (Eq, Ord, Show)

data Observations = Observations
  { change          :: !ChangeId
  , head            :: !Revision
  , targetBranch    :: !TargetBranch
  , target          :: !Revision
  , evaluatedTree   :: !TreeId
  , declarations    :: ![Declaration]
  , requiredGates   :: ![(GateName, DeclarationId)]
  , environments    :: ![(ProbeCommand, Observed EnvironmentId)]  -- ^ What each declared probe yields where the decision is made.
  , policy          :: !Policy
  , blockedBy       :: ![ChangeId]
  , invokerDeclared :: !Bool
  , authority       :: !IntegrationAuthority
  }
  deriving stock (Eq, Ord, Show)
