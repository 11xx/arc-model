{- | A recorded coverage obligation.

A debt with 'patchset' bound waives exactly that patchset; one recorded
after integration carries no patchset and waives nothing.
-}
module Arc.Model.Ledger.Debt
    ( DebtKind(..)
    , Qualifier(..)
    , AssessmentSource(..)
    , IneligibleRead(..)
    , Debt(..)
    ) where

import Arc.Model.Identifiers

import Data.Set ( Set )


-- | What a debt declaration says was missing. The kind is the weight: a
-- label the caller may declare, otherwise derived from the ledger.
data DebtKind = NothingRead
              | MergeResolutionUnread
              | RepairUnread
              | ContributorOnly
              | IneligibleReview
              | IndependentReview
  deriving stock (Eq, Ord, Show)

-- | Why routing does not count a read: the closed set an
-- @ineligible-review@ debt draws from.
data Qualifier = SameModel
               | SameFamily
               | BelowFloor
               | FloorUnknown
               | ReviewerUnseated
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | Whether the qualifiers came from an assessment file, or were named by
-- hand and corroborated by nothing.
data AssessmentSource = Assessed
                      | DeclaredByHand
  deriving stock (Eq, Ord, Show)

-- | What an @ineligible-review@ debt records beside its kind.
data IneligibleRead = IneligibleRead
  { read         :: !EventId           -- ^ The verdict event of the read that did not count.
  , qualifiers   :: !(Set Qualifier)
  , source       :: !AssessmentSource
  , routeVersion :: !(Maybe RouteVersion)
  }
  deriving stock (Eq, Ord, Show)

data Debt = Debt
  { debtId              :: !DebtId
  , event               :: !EventId
  , patchset            :: !(Maybe PatchsetId)
  , declaredKind        :: !(Maybe DebtKind)
  , reason              :: !String
  , actor               :: !ActorId
  , ineligible          :: !(Maybe IneligibleRead)
  , trailerImplementers :: !(Maybe (Set ModelSlug))  -- ^ The @Implemented-by@ models of the patchset's range, read when the debt was declared; absent where the range was not read.
  }
  deriving stock (Eq, Ord, Show)
