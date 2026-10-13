{- | Routing's assessment of an auditor, as an audit kept it.

Arc keeps the assessment's independence, its qualifiers and route version,
and the identities it lists for the reviewer and for each author. It keeps no
tier, family or floor: only routing can say what a read is worth.
-}
module Arc.Model.Ledger.Assessment
    ( Independence(..)
    , Assessment(..)
    , AssessmentBinding(..)
    ) where

import Arc.Model.Identifiers

import Data.Set ( Set )


data Independence = Eligible
                  | Ineligible
  deriving stock (Eq, Ord, Show)

data Assessment = Assessment
  { independence       :: !Independence
  , reviewerIdentities :: !(Set ModelSlug)         -- ^ Every model string routing accepts for the reviewer.
  , reviewerEffort     :: !(Maybe Effort)
  , authors            :: ![Set ModelSlug]         -- ^ Each author's identities.
  , routeVersion       :: !(Maybe RouteVersion)
  }
  deriving stock (Eq, Ord, Show)

-- | What an audit keeps of how an assessment answers to it: whether the
-- assessment describes the auditor, and whether it covers the work.
data AssessmentBinding = Bound
                       | ModelUnrecorded                         -- ^ The audit recorded no model.
                       | IdentitiesUnstated                      -- ^ The assessment lists no identity for its reviewer.
                       | ModelMismatch
                       | EffortMismatch
                       | AuthorsUncovered !(Set ModelSlug)       -- ^ The models of the range the assessment's authors omit.
                       | AuthorsUnread                           -- ^ The range's @Implemented-by@ lines could not be established.
  deriving stock (Eq, Ord, Show)
