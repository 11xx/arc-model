{- | One recorded gate evaluation.

'answers' names the failure a passing run was observed to answer, which is
what separates a gate shown able to fail from one that has only ever
passed. That distinction is advisory: it never blocks a merge.
'environment' is the identity the declared probe yielded where the run
happened; a run recorded with none says nothing about where it ran.
'worktree' is whether the checkout the run read held uncommitted changes:
a run on a dirty tree describes content no checkout of its revision
reproduces.
-}
module Arc.Model.Ledger.Verification
    ( WorktreeState(..)
    , Verification(..)
    ) where

import Arc.Model.Declaration ( DeclarationShape, ExecutionKind, GateResult )
import Arc.Model.Identifiers
import Arc.Model.Observed ( Observed )


data WorktreeState = CleanWorktree
                   | DirtyWorktree
  deriving stock (Eq, Ord, Show)

data Verification = Verification
  { event       :: !EventId
  , gate        :: !GateName
  , declaration :: !DeclarationId
  , shape       :: !DeclarationShape
  , revision    :: !Revision                 -- ^ The head the run was recorded at.
  , tree        :: !TreeId
  , result      :: !GateResult
  , execution   :: !ExecutionKind
  , answers     :: !(Maybe FailureLabel)
  , readable    :: !Bool
  , environment :: !(Maybe EnvironmentId)
  , worktree    :: !(Observed WorktreeState)  -- ^ Omitted where the run recorded nothing about it.
  }
  deriving stock (Eq, Ord, Show)
