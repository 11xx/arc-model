-- | The tiny test harness and its rendering helpers.
module Render
    ( Check(..)
    , passCheck
    , failCheck
    , expectEq
    , expectTrue
    , expectPermittedWith
    , expectRefusedWith
    , counterexampleText
    ) where

import Arc.Model


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

expectPermittedWith :: String -> Authorization -> Decision -> Check
expectPermittedWith name expected = \case
  Permitted basis
    | basis.authorization == expected -> passCheck name ""
    | otherwise -> failCheck name ("permitted on " <> oneLine (show basis.authorization) <> ", expected " <> oneLine (show expected))
  Refused refusal -> failCheck name ("refused: " <> refusalText refusal)

expectRefusedWith :: String -> String -> Decision -> Check
expectRefusedWith name expectedTag = \case
  Refused refusal
    | refusalTag refusal == expectedTag -> passCheck name (refusalTag refusal)
    | otherwise                         -> failCheck name ("refused as " <> refusalTag refusal <> ", expected " <> expectedTag)
  Permitted basis -> failCheck name ("permitted on " <> oneLine (show basis.authorization))

counterexampleText :: String -> String
counterexampleText = take 1600 . oneLine

oneLine :: String -> String
oneLine = unwords . words
