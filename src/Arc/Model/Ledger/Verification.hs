{- | One recorded gate evaluation.

'answers' names the failure a passing run was observed to answer, which is
what separates a gate shown able to fail from one that has only ever
passed. That distinction is advisory: it never blocks a merge.
'environment' is the identity the declared probe yielded where the run
happened; a run recorded with none says nothing about where it ran.
-}
module Arc.Model.Ledger.Verification ( Verification(..) ) where

import Arc.Model.Declaration ( DeclarationShape, ExecutionKind, GateResult )
import Arc.Model.Identifiers


data Verification = Verification
  { event       :: !EventId
  , gate        :: !GateName
  , declaration :: !DeclarationId
  , shape       :: !DeclarationShape
  , tree        :: !TreeId
  , result      :: !GateResult
  , execution   :: !ExecutionKind
  , answers     :: !(Maybe FailureLabel)
  , readable    :: !Bool
  , environment :: !(Maybe EnvironmentId)
  }
  deriving stock (Eq, Ord, Show)
