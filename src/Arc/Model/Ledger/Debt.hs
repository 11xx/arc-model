{- | A recorded coverage obligation.

A debt with 'patchset' bound waives exactly that patchset; one recorded
after integration carries no patchset and waives nothing.
-}
module Arc.Model.Ledger.Debt
    ( DebtKind(..)
    , Debt(..)
    ) where

import Arc.Model.Identifiers


-- | What a debt declaration says was missing. The kind is the weight: a
-- label the caller may declare, otherwise derived from the ledger.
data DebtKind = NothingRead
              | MergeResolutionUnread
              | RepairUnread
              | ContributorOnly
              | IndependentReview
  deriving stock (Eq, Ord, Show)

data Debt = Debt
  { debtId       :: !DebtId
  , event        :: !EventId
  , patchset     :: !(Maybe PatchsetId)
  , declaredKind :: !(Maybe DebtKind)
  , reason       :: !String
  , actor        :: !ActorId
  }
  deriving stock (Eq, Ord, Show)
