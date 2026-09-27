{- | Everything the model is told about the world at decision time.

The evaluated tree is explicit because a change behind its target evaluates
the merge, not its own head, and only Git can say what that tree is.
-}
module Arc.Model.Observations ( Observations(..) ) where

import Arc.Model.Declaration ( Declaration )
import Arc.Model.Identifiers
import Arc.Model.Policy ( Policy )


data Observations = Observations
  { change          :: !ChangeId
  , head            :: !Revision
  , targetBranch    :: !TargetBranch
  , target          :: !Revision
  , evaluatedTree   :: !TreeId
  , declarations    :: ![Declaration]
  , requiredGates   :: ![(GateName, DeclarationId)]
  , policy          :: !Policy
  , blockedBy       :: ![ChangeId]
  , invokerDeclared :: !Bool
  }
  deriving stock (Eq, Ord, Show)
