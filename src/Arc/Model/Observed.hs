{- | A fact the model may or may not have been told.

A fact that was not observed is 'Omitted'. It is not false, not passed, and
not failed: the model never promotes a missing observation into a result.
-}
module Arc.Model.Observed
    ( Observed(..)
    , observedToMaybe
    , newest
    ) where

import Data.Maybe ( listToMaybe )


data Observed a = Omitted
                | Observed a
  deriving stock (Eq, Ord, Show)

observedToMaybe :: Observed a -> Maybe a
observedToMaybe Omitted      = Nothing
observedToMaybe (Observed a) = Just a

-- | The newest of records kept in recording order, oldest first.
newest :: [a] -> Maybe a
newest = listToMaybe . reverse
