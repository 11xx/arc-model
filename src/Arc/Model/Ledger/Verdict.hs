{- | A reviewer's recorded conclusion about one patchset.

'assumed' records that the identity was derived rather than declared; an
assumed reviewer is not the second party independence needs.
-}
module Arc.Model.Ledger.Verdict
    ( VerdictKind(..)
    , VerdictRelation(..)
    , Verdict(..)
    , effectiveActor
    ) where

import Arc.Model.Identifiers

import Data.Maybe ( fromMaybe )


data VerdictKind = Approved
                 | ChangesRequested
                 | CommentOnly
  deriving stock (Eq, Ord, Show)

data VerdictRelation = Supersedes
                     | Corroborates
  deriving stock (Eq, Ord, Show)

data Verdict = Verdict
  { event       :: !EventId
  , patchset    :: !PatchsetId
  , kind        :: !VerdictKind
  , actor       :: !ActorId
  , onBehalfOf  :: !(Maybe ActorId)
  , assumed     :: !Bool
  , provisional :: !(Maybe String)
  , relation    :: !VerdictRelation
  , supersedes  :: !(Maybe EventId)
  }
  deriving stock (Eq, Ord, Show)

-- | The identity the verdict speaks for: the subject a lead recorded it on
-- behalf of, otherwise the recorder.
effectiveActor :: Verdict -> ActorId
effectiveActor verdict = fromMaybe verdict.actor verdict.onBehalfOf
