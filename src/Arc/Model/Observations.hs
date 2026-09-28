{- | Everything the model is told about the world at decision time.

The evaluated tree is explicit because a change behind its target evaluates
the merge, not its own head, and only Git can say what that tree is. The
environment each declared probe yields is explicit for the same reason: only
the checkout the decision is made in can answer, and a probe that failed
there answers nothing. The head is an observation that can be missing: a
change whose branch is gone has no head to decide about.
-}
module Arc.Model.Observations
    ( Observations(..)
    , IntegrationAuthority(..)
    , TargetRelation(..)
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

-- | How the head merges with its target.
data TargetRelation = HeadContainsTarget       -- ^ The head's own tree is what would ship.
                    | HeadBehindTarget         -- ^ The merge's tree, which neither branch committed, is what would ship.
                    | HeadConflictsWithTarget  -- ^ The merge does not resolve; the head's own tree is evaluated.
  deriving stock (Eq, Ord, Show)

data Observations = Observations
  { change           :: !ChangeId
  , head             :: !(Observed Revision)                        -- ^ Omitted where the change's branch is gone.
  , targetBranch     :: !TargetBranch
  , target           :: !Revision
  , targetRelation   :: !TargetRelation
  , evaluatedTree    :: !TreeId
  , declarations     :: ![Declaration]
  , conflictingGates :: ![GateName]                                 -- ^ Gates two policy layers declare differently.
  , requiredGates    :: ![(GateName, DeclarationId)]
  , environments     :: ![(ProbeCommand, Observed EnvironmentId)]  -- ^ What each declared probe yields where the decision is made.
  , policy           :: !Policy
  , blockedBy        :: ![ChangeId]
  , invokerDeclared  :: !Bool
  , authority        :: !IntegrationAuthority
  }
  deriving stock (Eq, Ord, Show)
