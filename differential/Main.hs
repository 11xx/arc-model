{- | The differential: the same histories through the model and through arc.

Named scenarios run first, then histories generated from the seed with the
spec's own generators, so a reader can reproduce any row from its index:
@generated-i@ draws the fields the decision rests on, and @check-time-i@
draws the same fields from the same seed and then the facts arc's check
reports beside them.

A run compares one channel. The decision channel compares 'refusals' with
@arc check@; the execution channel compares 'execute' with
@arc integrate --dry-run@ after the moves a scenario makes between the
decision and the integration; the coverage channel integrates for real,
records the scenario's audit, and compares 'historicalAuthorization' and
'coverageAfterIntegration' with what @arc show@, @arc findings --audit@,
and @arc query --debt@ report.

Every row is one of: agreed, skipped with the field the CLI cannot record,
adjudicated with its class and reason, disagreed, or failed to replay. The
run exits non-zero on a disagreement nobody has classified or on a replay
that broke, and on nothing else: a quiet run is evidence, not proof. Every
case runs in a sandbox of "Differential.Sandbox"; a sandbox whose self-check
refuses stops the run with exit 70 before anything runs in it.
-}
module Main ( main ) where

import Arc.Model
import Differential.Arc ( Answer, Outcome(..) )
import Differential.Arc qualified as Arc
import Differential.Compare
import Differential.Plan
import Differential.Sandbox ( SelfCheckRefused(..) )
import Generators
import Mutants ( Behaviour(..), Channel(..), Mutant(..), allMutants )

import Control.Exception ( handle )
import Control.Monad ( unless, when )
import Data.List ( intercalate )
import Data.Set qualified as Set
import System.Directory ( getTemporaryDirectory, removePathForcibly )
import System.Environment ( getArgs )
import System.Exit ( ExitCode(..), exitFailure, exitSuccess, exitWith )
import System.FilePath ( (</>) )
import System.IO ( hFlush, stdout )
import System.Posix.Temp ( mkdtemp )
import Test.QuickCheck.Gen ( unGen )
import Test.QuickCheck.Random ( mkQCGen )


-- | Which of the model's answers a run compares with arc.
data Compared = ComparedDecision
              | ComparedExecution
              | ComparedCoverage
  deriving stock (Eq, Show)

comparedText :: Compared -> String
comparedText = \case
  ComparedDecision  -> "decision"
  ComparedExecution -> "execution"
  ComparedCoverage  -> "coverage"

data Settings = Settings
  { seed           :: !Int
  , cases          :: !Int
  , checkTimeCases :: !Int
  , compared       :: !Compared
  , binary         :: !FilePath
  , mutant         :: !(Maybe String)
  , keep           :: !Bool
  , verbose        :: !Bool
  }

defaults :: Settings
defaults = Settings
  { seed           = 20260907
  , cases          = 60
  , checkTimeCases = 60
  , compared       = ComparedDecision
  , binary         = "arc"
  , mutant         = Nothing
  , keep           = False
  , verbose        = False
  }

usage :: String
usage = unlines
  [ "arc-model-differential [--channel decision|execution|coverage] [--seed N] [--cases N] [--check-time-cases N]"
  , "                       [--arc PATH] [--mutant NAME] [--keep] [--verbose]"
  , ""
  , "  --channel C   decision: refusals against arc check (default);"
  , "                execution: execute against arc integrate --dry-run;"
  , "                coverage: the recorded authorization and audit coverage against arc show, findings, and query"
  , "  --seed N      the generator seed (default 20260907)"
  , "  --cases N     generated histories after the named ones (default 60)"
  , "  --check-time-cases N"
  , "                generated histories that also draw check-time facts (default 60)"
  , "  --arc PATH    the arc binary to replay against (default: arc on PATH)"
  , "  --mutant NAME expect a permission wherever this deliberate fault of the channel permits, to show the comparison objects"
  , "  --keep        leave every sandbox on disk and print where"
  , "  --verbose     print each arc command as it runs"
  ]

parseSettings :: [String] -> Either String Settings
parseSettings = go defaults
  where
    go settings = \case
      []                                  -> Right settings
      "--channel" : "decision" : rest     -> go settings { compared = ComparedDecision } rest
      "--channel" : "execution" : rest    -> go settings { compared = ComparedExecution } rest
      "--channel" : "coverage" : rest     -> go settings { compared = ComparedCoverage } rest
      "--seed" : value : rest             -> go settings { seed = read value } rest
      "--cases" : value : rest            -> go settings { cases = read value } rest
      "--check-time-cases" : value : rest -> go settings { checkTimeCases = read value } rest
      "--arc" : value : rest              -> go settings { binary = value } rest
      "--mutant" : value : rest           -> go settings { mutant = Just value } rest
      "--keep" : rest                     -> go settings { keep = True } rest
      "--verbose" : rest                  -> go settings { verbose = True } rest
      other : _                           -> Left ("unknown argument " <> other)

-- | What the comparison expects of a built scenario, on each channel.
data Oracle = Oracle
  { grounds    :: !(Built -> [Refusal])
  , execution  :: !(Built -> Either Refusal ExecutionPlan)
  , historical :: !(Built -> Maybe Authorization)
  , coverage   :: !(Built -> CoverageAfterIntegration)
  }

-- | How one scenario's comparison ended. Expected and actual answers are
-- kept rendered, since each channel has answers of its own shape.
data Row = Row
  { label   :: !String
  , outcome :: !RowOutcome
  }

data RowOutcome = RowAgreed
                | RowSkipped Skip
                | RowAdjudicated Adjudication String String
                | RowDisagreed String String
                | RowFailed String

main :: IO ()
main = do
  settings <- either (\failure -> putStrLn failure >> putStr usage >> exitFailure) pure . parseSettings =<< getArgs
  oracle   <- oracleFor settings
  scratch  <- getTemporaryDirectory
  root     <- mkdtemp (scratch </> "arc-model-differential-")
  putStrLn ("arc-model differential: comparison revision " <> comparisonRevision)
  putStrLn ("channel " <> comparedText settings.compared <> ", seed " <> show settings.seed <> ", " <> show (length namedScenarios + length (channelScenarios settings.compared)) <> " named + " <> show settings.cases <> " generated + " <> show settings.checkTimeCases <> " check-time cases, arc = " <> settings.binary)
  maybe (pure ()) (\name -> putStrLn ("expecting the answers of mutant " <> name)) settings.mutant
  putStrLn ""
  let draw generator index = unGen generator (mkQCGen (settings.seed + index)) (index `mod` 40 + 1)
      generated = [ ("generated-" <> show index, draw genDecisionScenario index) | index <- [0 .. settings.cases - 1] ]
      checkTime = [ ("check-time-" <> show index, draw genAnyScenario index) | index <- [0 .. settings.checkTimeCases - 1] ]
      named = namedScenarios <> channelScenarios settings.compared
  rows <- handle (refused root) (mapM (runCase settings oracle root) (zip [0 :: Int ..] (named <> generated <> checkTime)))
  putStrLn ""
  summarize settings.compared rows
  if settings.keep
    then putStrLn ("sandboxes kept under " <> root)
    else removePathForcibly root
  if any objectionable rows then exitFailure else exitSuccess

-- | Stop the run on a sandbox whose self-check refused, keeping the scratch
-- root for inspection.
refused :: FilePath -> SelfCheckRefused -> IO a
refused root (SelfCheckRefused found) = do
  putStrLn ""
  putStrLn ("the sandbox self-check refused; nothing ran in it, scratch kept under " <> root)
  mapM_ (putStrLn . ("  " <>)) found
  exitWith (ExitFailure 70)

-- | The histories named for one channel, run after the shared ones.
channelScenarios :: Compared -> [(String, Scenario)]
channelScenarios = \case
  ComparedDecision  -> []
  ComparedExecution -> namedExecutionScenarios
  ComparedCoverage  -> namedCoverageScenarios

{- | The answers the comparison expects: the model's, or, under a mutant of
the channel compared, a permission wherever the fault permits. A fault that
refuses is compared as the model would be, so the only rows that can object
are the ones where the fault permits what arc refuses: the counterexample
the probe exists to show.
-}
oracleFor :: Settings -> IO Oracle
oracleFor settings = case settings.mutant of
  Nothing   -> pure model
  Just name -> case [ m | m <- allMutants, m.name == name ] of
    found : _
      | found.channel == ChannelDecision, settings.compared == ComparedDecision -> pure Oracle
          { grounds    = \built -> case found.run built of
              BehaviourDecision (Right _) -> []
              _refused                        -> model.grounds built
          , execution  = model.execution
          , historical = model.historical
          , coverage   = model.coverage
          }
      | found.channel == ChannelExecution, settings.compared == ComparedExecution -> pure Oracle
          { grounds    = model.grounds
          , execution  = \built -> case found.run built of
              BehaviourExecution (Right acted) -> Right acted
              _refused                         -> model.execution built
          , historical = model.historical
          , coverage   = model.coverage
          }
      -- a fault of what shipped or of its coverage is expected as it is:
      -- there is no permission to expect in its place
      | found.channel `elem` [ChannelHistorical, ChannelCoverage], settings.compared == ComparedCoverage -> pure Oracle
          { grounds    = model.grounds
          , execution  = model.execution
          , historical = \built -> case found.run built of
              BehaviourHistorical authorization -> authorization
              _otherChannel                     -> model.historical built
          , coverage   = \built -> case found.run built of
              BehaviourCoverage projected -> projected
              _otherChannel               -> model.coverage built
          }
      | otherwise -> putStrLn ("mutant " <> name <> " does not fault the " <> comparedText settings.compared <> " channel") >> exitFailure
    [] -> putStrLn ("no mutant named " <> name <> "; the spec's mutants are " <> intercalate ", " (map (.name) allMutants)) >> exitFailure
  where
    model = Oracle
      { grounds    = \built -> refusals built.observation built.state
      , execution  = (.execution)
      , historical = \built -> historicalAuthorization built.finalState
      , coverage   = \built -> coverageAfterIntegration built.finalState
      }

runCase :: Settings -> Oracle -> FilePath -> (Int, (String, Scenario)) -> IO Row
runCase settings oracle root (index, (label, scenario)) = do
  putStr ("[" <> show index <> "] " <> label <> " ")
  hFlush stdout
  row <- Row label <$> case (plan scenario, settings.compared) of
    (Left skip, _) -> pure (RowSkipped skip)
    (Right steps, ComparedDecision) -> do
      when settings.verbose (putStrLn "" >> print scenario)
      let wanted = expected (oracle.grounds built)
      outcome <- Arc.runPlan options dir steps
      pure $ case outcome of
        ReplayFailed failure -> RowFailed failure
        Answered answer      -> case compareAnswer scenario wanted answer of
          Agreed                   -> RowAgreed
          Adjudicated adjudication -> RowAdjudicated adjudication (setText wanted) (answerText answer)
          Disagreed                -> RowDisagreed (setText wanted <> " from " <> show (map refusalTag (oracle.grounds built))) (answerText answer)
    (Right steps, ComparedExecution) -> do
      when settings.verbose (putStrLn "" >> print scenario)
      let wanted = expectedExecution built (oracle.execution built)
      outcome <- Arc.runExecution options dir steps
      pure $ case outcome of
        ReplayFailed failure -> RowFailed failure
        Answered dry         -> case compareExecution scenario built wanted dry of
          Agreed                   -> RowAgreed
          Adjudicated adjudication -> RowAdjudicated adjudication (executionText wanted) (dryRunText dry)
          Disagreed                -> RowDisagreed (executionText wanted) (dryRunText dry)
    (Right steps, ComparedCoverage) -> do
      when settings.verbose (putStrLn "" >> print scenario)
      let wanted = expectedCoverage (oracle.historical built) (oracle.coverage built)
      outcome <- Arc.runCoverage options dir steps
      pure $ case outcome of
        ReplayFailed failure -> RowFailed failure
        Answered found       -> case compareCoverage scenario built wanted found of
          Agreed                   -> RowAgreed
          Adjudicated adjudication -> RowAdjudicated adjudication (recordedText wanted) (recordedText found)
          Disagreed                -> RowDisagreed (recordedText wanted) (recordedText found)
  putStrLn (describe row.outcome)
  unless (agreeable row.outcome) (print scenario)
  pure row
  where
    built   = build scenario
    dir     = root </> ("case-" <> show index)
    options = Arc.Options { arcBinary = settings.binary, verbose = settings.verbose }

describe :: RowOutcome -> String
describe = \case
  RowAgreed                              -> "agreed"
  RowSkipped skip                        -> "skipped: " <> skipText skip
  RowAdjudicated adjudication wanted got -> "adjudicated " <> kindText adjudication.kind <> ": expected " <> wanted <> ", arc " <> got <> " — " <> adjudication.reason
  RowDisagreed wanted got                -> "DISAGREED: expected " <> wanted <> ", arc " <> got
  RowFailed failure                      -> "REPLAY FAILED: " <> failure

setText :: Set.Set String -> String
setText found
  | Set.null found = "{ready}"
  | otherwise      = "{" <> intercalate ", " (Set.toList found) <> "}"

answerText :: Answer -> String
answerText answer
  | answer.ready = "{ready}"
  | otherwise    = setText answer.blockers

dryRunText :: Arc.DryRun -> String
dryRunText dry = case dry.exit of
  0    -> "{would integrate}"
  17   -> "{exit 17}"
  code -> "{exit " <> show code <> ", refused " <> unwords (Set.toList dry.after.blockers) <> "}"

agreeable :: RowOutcome -> Bool
agreeable = \case
  RowAgreed         -> True
  RowSkipped _      -> True
  RowAdjudicated {} -> True
  _objectionable    -> False

objectionable :: Row -> Bool
objectionable row = not (agreeable row.outcome)

summarize :: Compared -> [Row] -> IO ()
summarize channel rows = do
  let count predicate = length (filter (predicate . (.outcome)) rows)
      agreed      = count (\case RowAgreed -> True; _other -> False)
      skipped     = count (\case RowSkipped _ -> True; _other -> False)
      adjudicated = count (\case RowAdjudicated {} -> True; _other -> False)
      disagreed   = count (\case RowDisagreed {} -> True; _other -> False)
      failed      = count (\case RowFailed _ -> True; _other -> False)
  putStrLn ("channel " <> comparedText channel <> ": " <> show (length rows) <> " cases: " <> show agreed <> " agreed, " <> show adjudicated <> " adjudicated, " <> show skipped <> " skipped, " <> show disagreed <> " disagreed, " <> show failed <> " failed to replay")
  mapM_ (\row -> putStrLn ("  " <> row.label <> ": " <> describe row.outcome)) (filter objectionable rows)
  let adjudications = [ adjudication | row <- rows, RowAdjudicated adjudication _ _ <- [row.outcome] ]
  unless (null adjudications) $
    mapM_ (\reason -> putStrLn ("  adjudicated " <> show (length (filter ((== reason) . (.reason)) adjudications)) <> ": " <> reason)) (Set.toList (Set.fromList (map (.reason) adjudications)))
  let skips = [ skip | row <- rows, RowSkipped skip <- [row.outcome] ]
  unless (null skips) $
    mapM_ (\skip -> putStrLn ("  skipped " <> show (length (filter (== skip) skips)) <> ": " <> skipText skip)) (Set.toList (Set.fromList skips))
  when (disagreed + failed == 0) $ putStrLn "a quiet run is supporting evidence, not proof of equivalence"
