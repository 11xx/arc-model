-- | The check harness: the shape of the spec suite's, over candidate
-- answers.
module Render
    ( Check(..)
    , passCheck
    , failCheck
    , expectEq
    , expectTrue
    , expectPermitted
    , expectRefusedWith
    , counterexampleText
    ) where

import Arc.Candidate

import Data.List.NonEmpty ( NonEmpty )


data Check = Check
  { name   :: !String
  , passed :: !Bool
  , detail :: !String
  }

passCheck :: String -> String -> Check
passCheck name detail = Check { name = name, passed = True, detail = detail }

failCheck :: String -> String -> Check
failCheck name detail = Check { name = name, passed = False, detail = detail }

expectEq :: (Eq a, Show a) => String -> a -> a -> Check
expectEq name expected actual
  | expected == actual = passCheck name ""
  | otherwise          = failCheck name ("expected " <> oneLine (show expected) <> ", got " <> oneLine (show actual))

expectTrue :: String -> String -> Bool -> Check
expectTrue name detail condition
  | condition = passCheck name ""
  | otherwise = failCheck name detail

expectPermitted :: String -> Either (NonEmpty Refusal) SelectionBasis -> Check
expectPermitted name = \case
  Right _       -> passCheck name ""
  Left refused  -> failCheck name ("refused: " <> oneLine (show refused))

-- | Refused, and on exactly the expected grounds.
expectRefusedWith :: String -> [Refusal] -> Either (NonEmpty Refusal) SelectionBasis -> Check
expectRefusedWith name expected = \case
  Left refused
    | foldr (:) [] refused == expected -> passCheck name (unwords (map refusalTag expected))
    | otherwise                        -> failCheck name ("refused on " <> oneLine (show refused) <> ", expected " <> oneLine (show expected))
  Right basis -> failCheck name ("permitted on " <> oneLine (show basis))

counterexampleText :: String -> String
counterexampleText = take 1600 . oneLine

oneLine :: String -> String
oneLine = unwords . words
