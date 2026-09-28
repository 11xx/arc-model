{- | The differential: the same histories through the model and through arc.

Named scenarios run first, then histories generated from the seed with the
spec's own generator, so a reader can reproduce any row from its index.
Every row is one of: agreed, skipped with the field the CLI cannot record,
adjudicated with its class and reason, disagreed, or failed to replay. The
run exits non-zero on a disagreement nobody has classified or on a replay
that broke, and on nothing else: a quiet run is evidence, not proof.
-}
module Main ( main ) where

import Arc.Model
import Differential.Arc ( Answer, Outcome(..) )
import Differential.Arc qualified as Arc
import Differential.Compare
import Differential.Plan
import Generators
import Mutants ( Behaviour(..), Channel(..), Mutant(..), allMutants )

import Control.Monad ( unless, when )
import Data.List ( intercalate )
import Data.Set qualified as Set
import System.Directory ( getTemporaryDirectory, removePathForcibly )
import System.Environment ( getArgs )
import System.Exit ( exitFailure, exitSuccess )
import System.FilePath ( (</>) )
import System.IO ( hFlush, stdout )
import System.Posix.Temp ( mkdtemp )
import Test.QuickCheck.Gen ( unGen )
import Test.QuickCheck.Random ( mkQCGen )


data Settings = Settings
  { seed    :: !Int
  , cases   :: !Int
  , binary  :: !FilePath
  , mutant  :: !(Maybe String)
  , keep    :: !Bool
  , verbose :: !Bool
  }

defaults :: Settings
defaults = Settings
  { seed    = 20260907
  , cases   = 60
  , binary  = "arc"
  , mutant  = Nothing
  , keep    = False
  , verbose = False
  }

usage :: String
usage = unlines
  [ "arc-model-differential [--seed N] [--cases N] [--arc PATH] [--mutant NAME] [--keep] [--verbose]"
  , ""
  , "  --seed N      the generator seed (default 20260907)"
  , "  --cases N     generated histories after the named ones (default 60)"
  , "  --arc PATH    the arc binary to replay against (default: arc on PATH)"
  , "  --mutant NAME expect a permission wherever this deliberate fault permits, to show the comparison objects"
  , "  --keep        leave every sandbox on disk and print where"
  , "  --verbose     print each arc command as it runs"
  ]

parseSettings :: [String] -> Either String Settings
parseSettings = go defaults
  where
    go settings = \case
      []                     -> Right settings
      "--seed" : value : rest -> go settings { seed = read value } rest
      "--cases" : value : rest -> go settings { cases = read value } rest
      "--arc" : value : rest -> go settings { binary = value } rest
      "--mutant" : value : rest -> go settings { mutant = Just value } rest
      "--keep" : rest        -> go settings { keep = True } rest
      "--verbose" : rest     -> go settings { verbose = True } rest
      other : _              -> Left ("unknown argument " <> other)

-- | How one scenario's comparison ended.
data Row = Row
  { label   :: !String
  , outcome :: !RowOutcome
  }

data RowOutcome = RowAgreed
                | RowSkipped Skip
                | RowAdjudicated Adjudication (Set.Set String) Answer
                | RowDisagreed (Set.Set String) Answer [Refusal]
                | RowFailed String

main :: IO ()
main = do
  settings <- either (\failure -> putStrLn failure >> putStr usage >> exitFailure) pure . parseSettings =<< getArgs
  oracle   <- expectedGrounds settings
  scratch  <- getTemporaryDirectory
  root     <- mkdtemp (scratch </> "arc-model-differential-")
  putStrLn ("arc-model differential: comparison revision " <> comparisonRevision)
  putStrLn ("seed " <> show settings.seed <> ", " <> show (length namedScenarios) <> " named + " <> show settings.cases <> " generated cases, arc = " <> settings.binary)
  maybe (pure ()) (\name -> putStrLn ("expecting the decisions of mutant " <> name)) settings.mutant
  putStrLn ""
  let generated = [ ("generated-" <> show index, unGen genAnyScenario (mkQCGen (settings.seed + index)) (index `mod` 40 + 1)) | index <- [0 .. settings.cases - 1] ]
  rows <- mapM (runCase settings oracle root) (zip [0 :: Int ..] (namedScenarios <> generated))
  putStrLn ""
  summarize rows
  if settings.keep
    then putStrLn ("sandboxes kept under " <> root)
    else removePathForcibly root
  if any objectionable rows then exitFailure else exitSuccess

{- | The grounds the comparison expects: the model's, or, under a mutant,
nothing wherever the fault permits. A fault that refuses on other grounds
is compared as the model would be, so the only rows that can object are
the ones where the fault permits what arc refuses: the counterexample the
probe exists to show.
-}
expectedGrounds :: Settings -> IO (Built -> [Refusal])
expectedGrounds settings = case settings.mutant of
  Nothing   -> pure (\built -> refusals built.observation built.state)
  Just name -> case [ m | m <- allMutants, m.name == name ] of
    found : _
      | found.channel == ChannelDecision -> pure $ \built -> case found.run built of
          BehaviourDecision (Permitted _) -> []
          _refused                        -> refusals built.observation built.state
      | otherwise -> putStrLn ("mutant " <> name <> " does not fault the decision channel") >> exitFailure
    [] -> putStrLn ("no mutant named " <> name <> "; the spec's mutants are " <> intercalate ", " (map (.name) allMutants)) >> exitFailure

runCase :: Settings -> (Built -> [Refusal]) -> FilePath -> (Int, (String, Scenario)) -> IO Row
runCase settings oracle root (index, (label, scenario)) = do
  putStr ("[" <> show index <> "] " <> label <> " ")
  hFlush stdout
  row <- case plan scenario of
    Left skip -> pure (Row label (RowSkipped skip))
    Right steps -> do
      let built  = build scenario
          wanted = expected (oracle built)
          dir    = root </> ("case-" <> show index)
      when settings.verbose (putStrLn "" >> print scenario)
      outcome <- Arc.runPlan Arc.Options { arcBinary = settings.binary, verbose = settings.verbose } dir steps
      pure . Row label $ case outcome of
        ReplayFailed failure -> RowFailed failure
        Answered answer      -> case compareAnswer scenario wanted answer of
          Agreed                   -> RowAgreed
          Adjudicated adjudication -> RowAdjudicated adjudication wanted answer
          Disagreed                -> RowDisagreed wanted answer (oracle built)
  putStrLn (describe row.outcome)
  unless (agreeable row.outcome) (print scenario)
  pure row

describe :: RowOutcome -> String
describe = \case
  RowAgreed                              -> "agreed"
  RowSkipped skip                        -> "skipped: " <> skipText skip
  RowAdjudicated adjudication wanted got -> "adjudicated " <> kindText adjudication.kind <> ": expected " <> setText wanted <> ", arc " <> answerText got <> " — " <> adjudication.reason
  RowDisagreed wanted got grounds        -> "DISAGREED: expected " <> setText wanted <> " from " <> show (map refusalTag grounds) <> ", arc " <> answerText got
  RowFailed failure                      -> "REPLAY FAILED: " <> failure

setText :: Set.Set String -> String
setText found
  | Set.null found = "{ready}"
  | otherwise      = "{" <> intercalate ", " (Set.toList found) <> "}"

answerText :: Answer -> String
answerText answer
  | answer.ready = "{ready}"
  | otherwise    = setText answer.blockers

agreeable :: RowOutcome -> Bool
agreeable = \case
  RowAgreed        -> True
  RowSkipped _     -> True
  RowAdjudicated {} -> True
  _objectionable   -> False

objectionable :: Row -> Bool
objectionable row = not (agreeable row.outcome)

summarize :: [Row] -> IO ()
summarize rows = do
  let count predicate = length (filter (predicate . (.outcome)) rows)
      agreed      = count (\case RowAgreed -> True; _other -> False)
      skipped     = count (\case RowSkipped _ -> True; _other -> False)
      adjudicated = count (\case RowAdjudicated {} -> True; _other -> False)
      disagreed   = count (\case RowDisagreed {} -> True; _other -> False)
      failed      = count (\case RowFailed _ -> True; _other -> False)
  putStrLn (show (length rows) <> " cases: " <> show agreed <> " agreed, " <> show adjudicated <> " adjudicated, " <> show skipped <> " skipped, " <> show disagreed <> " disagreed, " <> show failed <> " failed to replay")
  mapM_ (\row -> putStrLn ("  " <> row.label <> ": " <> describe row.outcome)) (filter objectionable rows)
  let skips = [ skip | row <- rows, RowSkipped skip <- [row.outcome] ]
  unless (null skips) $
    mapM_ (\skip -> putStrLn ("  skipped " <> show (length (filter (== skip) skips)) <> ": " <> skipText skip)) (Set.toList (Set.fromList skips))
  when (disagreed + failed == 0) $ putStrLn "a quiet run is supporting evidence, not proof of equivalence"
