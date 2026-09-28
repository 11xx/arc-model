{- | Permission for evidence recorded on a dirty worktree to count.

A waiver names the head it was declared at and covers evidence recorded at
exactly that revision. The ledger keeps every declaration; only the newest
is in force, so a later waiver at another revision ends an earlier one.
-}
module Arc.Model.Ledger.DirtyTreeWaiver ( DirtyTreeWaiver(..) ) where

import Arc.Model.Identifiers


data DirtyTreeWaiver = DirtyTreeWaiver
  { event    :: !EventId
  , revision :: !Revision  -- ^ The head it was declared at, and the only revision it covers.
  }
  deriving stock (Eq, Ord, Show)
