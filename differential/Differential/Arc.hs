{-# LANGUAGE DeriveAnyClass #-}
{- | Running a plan against the arc binary.

Every case gets a repository and a home of its own under one scratch root,
so arc's ledger, worktrees, and configuration never touch the operator's.
The binary is the one on @PATH@ unless the caller names another; the driver
adds nothing arc does not do on its own.
-}
module Differential.Arc
    ( Options(..)
    , Answer(..)
    , Outcome(..)
    , runPlan
    ) where

import Arc.Model ( DebtKind(..), ExternalKind(..), Policy, VerdictKind(..) )
import Arc.Model.Policy qualified as Policy
import Differential.Plan

import Control.Exception ( IOException, try )
import Control.Monad ( unless, when )
import Data.Aeson ( FromJSON, eitherDecodeStrict' )
import Data.ByteString.Char8 qualified as BS
import Data.List ( isPrefixOf )
import Data.Maybe ( listToMaybe )
import Data.Set ( Set )
import Data.Set qualified as Set
import GHC.Generics ( Generic )
import System.Directory ( createDirectoryIfMissing )
import System.Environment ( getEnvironment )
import System.Exit ( ExitCode(..) )
import System.FilePath ( (</>) )
import System.Process ( CreateProcess(..), proc, readCreateProcessWithExitCode )


data Options = Options
  { arcBinary :: !FilePath
  , verbose   :: !Bool
  }

-- | What @arc check --json@ said.
data Answer = Answer
  { ready    :: !Bool
  , blockers :: !(Set String)
  }
  deriving stock (Eq, Show)

-- | How a replay ended: with arc's answer, or with a command arc refused
-- that the plan did not expect it to.
data Outcome = Answered Answer
             | ReplayFailed String
  deriving stock (Eq, Show)

-- json shapes

data CheckOutput = CheckOutput
  { ready    :: Bool
  , blockers :: [CheckBlocker]
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

newtype CheckBlocker = CheckBlocker { blocker :: String }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

newtype FindingsOutput = FindingsOutput { findings :: [FindingRow] }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

newtype FindingRow = FindingRow { id :: String }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

-- the sandbox

data Sandbox = Sandbox
  { repo     :: !FilePath
  , home     :: !FilePath
  , worktree :: !FilePath
  , baseEnv  :: ![(String, String)]
  }

changeSlug :: String
changeSlug = "work"

-- | The gate every case declares: it fails on demand, and its probe prints
-- the environment it is told to, or fails when told nothing.
gatesToml :: String
gatesToml = unlines
  [ "[gates.build]"
  , "command = \"test -z \\\"$GATE_FAIL\\\"\""
  , "environment = \"test -n \\\"$PROBE_ENV\\\" && echo $PROBE_ENV\""
  ]

policyToml :: Policy -> String
policyToml policy = unlines
  [ "[policy]"
  , "forbid_self_approval = " <> bool policy.forbidSelfApproval
  , "require_declared_actor = " <> bool policy.requireDeclaredActor
  , ""
  , "[danger]"
  , "paths = [\"danger.txt\"]"
  ]
  where
    bool value = if value then "true" else "false"

-- | Run one plan in a fresh sandbox under the given directory and ask
-- arc for its answer.
runPlan :: Options -> FilePath -> Plan -> IO Outcome
runPlan options root planned = do
  sandbox <- mkSandbox options root planned.policy
  outcome <- try (runSteps options sandbox planned.steps) :: IO (Either IOException ())
  case outcome of
    Left failure -> pure (ReplayFailed (show failure))
    Right ()     -> check options sandbox planned.probeAtCheck

mkSandbox :: Options -> FilePath -> Policy -> IO Sandbox
mkSandbox options root policy = do
  let repo = root </> "repo"
      home = root </> "home"
  createDirectoryIfMissing True (repo </> ".arc")
  createDirectoryIfMissing True home
  ambient <- getEnvironment
  let baseEnv =
        [ ("HOME", home), ("ARC_SANDBOX", home), ("ARC_HARNESS", "test"), ("ARC_SESSION", "session-a")
        , ("GIT_EDITOR", "true"), ("GIT_SEQUENCE_EDITOR", "true")
        ]
        <> [ pair | pair@(key, _) <- ambient, not (inherited key) ]
      sandbox = Sandbox { repo = repo, home = home, worktree = home </> ".worktrees" </> ("repo-" <> changeSlug), baseEnv = baseEnv }
  writeFile (repo </> ".arc" </> "gates.toml") gatesToml
  writeFile (repo </> ".arc" </> "policy.toml") (policyToml policy)
  writeFile (repo </> "README.md") "differential fixture\n"
  git sandbox repo ["init", "-q", "-b", "master"]
  git sandbox repo ["config", "user.name", "Tester"]
  git sandbox repo ["config", "user.email", "tester@example.invalid"]
  git sandbox repo ["config", "commit.gpgsign", "false"]
  git sandbox repo ["add", "."]
  git sandbox repo ["commit", "-q", "-m", "init"]
  _ <- arc options sandbox repo (Declared "author") [] ["begin", changeSlug] ""
  pure sandbox
  where
    -- the harness this runs under exports its own session; the binary under
    -- test must not detect the runner instead of the fixture
    inherited key = key `elem`
      [ "HOME", "ARC_SANDBOX", "ARC_HARNESS", "ARC_SESSION", "ARC_ACTOR", "ARC_ROLE", "ARC_MODEL"
      , "ARC_ON_BEHALF_OF", "ARC_DATA_DIR", "ARC_DATA_ROOT", "ARC_WORKTREES_DIR", "AI_HOME"
      , "GIT_EDITOR", "GIT_SEQUENCE_EDITOR", "GATE_FAIL", "PROBE_ENV"
      , "CLAUDE_SESSION_ID", "CLAUDE_CODE_SESSION_ID", "CODEX_THREAD_ID", "OPENCODE_SESSION"
      , "OPENCODE_TERMINAL", "PI_SESSION_ID", "PI_SESSION_FILE", "PI_MODEL", "PI_REASONING_LEVEL"
      ]
      || "CLAUDE" `isPrefixOf` key

runSteps :: Options -> Sandbox -> [Step] -> IO ()
runSteps options sandbox = mapM_ step
  where
    wt        = sandbox.worktree
    author    = Declared "author"
    step = \case
      Commit file -> do
        appendFile (wt </> file) "work\n"
        git sandbox wt ["add", file]
        git sandbox wt ["commit", "-q", "-m", "edit " <> file]
      Snapshot contributors ->
        expect =<< arc options sandbox wt author [] (["snapshot", changeSlug] <> [ "--contributors=" <> commaList contributors | not (null contributors) ]) ""
      Verify run ->
        -- a failing gate makes verify exit non-zero after recording the
        -- evidence, which is the run the plan asked for
        (if run.fails then allowRefusal else expect) =<< arc options sandbox wt author (gateEnv run) ["verify", changeSlug, "--gate", "build"] ""
      Review identity kind ->
        -- a verdict nobody declared is refused where policy requires a
        -- declared actor; the plan asks anyway, because the model records it
        allowRefusal =<< arc options sandbox wt identity [] (["review", changeSlug, "--verdict", verdictFlag kind, "--body", "review"] <> causeFlag kind) ""
      Finding identity ->
        expect =<< arc options sandbox wt identity [] ["review", changeSlug, "--verdict", "comment-only", "--findings-json", "-"]
          "[{\"summary\":\"finding\",\"body\":\"raised\",\"severity\":\"major\",\"blocking\":true}]"
      ResolveFinding -> do
        (_, listed, _) <- arc options sandbox wt author [] ["findings", changeSlug, "--format", "json"] ""
        identifier <- case eitherDecodeStrict' (BS.pack listed) of
          Right (FindingsOutput rows) | Just row <- listToMaybe rows -> pure row.id
          Right _                                                    -> ioError (userError "no finding to resolve")
          Left failure                                               -> ioError (userError ("findings JSON: " <> failure))
        expect =<< arc options sandbox wt (Declared "other") [] ["resolve", changeSlug, identifier, "--status", "resolved", "--evidence", "repaired"] ""
      Debt kind ->
        expect =<< arc options sandbox wt author [] (["debt", changeSlug, "--reason", "coverage"] <> [ "--kind=" <> debtKindFlag k | Just k <- [kind] ]) ""
      External kind -> do
        (_, revision, _) <- gitOut sandbox wt ["rev-parse", "HEAD"]
        expect =<< arc options sandbox wt author []
          [ "external", "verdict", changeSlug, "--verdict", externalFlag kind
          , "--decided-by", "upstream", "--reference", "upstream/1", "--revision", trim revision
          ] ""
      CommitUnrecorded -> do
        appendFile (wt </> "later.txt") "later\n"
        git sandbox wt ["add", "later.txt"]
        git sandbox wt ["commit", "-q", "-m", "after the last snapshot"]
      EditGates -> do
        declared <- readFile (wt </> ".arc" </> "gates.toml")
        length declared `seq` writeFile (wt </> ".arc" </> "gates.toml") (replaceOnce "test -z" "test  -z" declared)
    gateEnv run = [ ("GATE_FAIL", "1") | run.fails ] <> [ ("PROBE_ENV", identity) | Just identity <- [run.probeYields] ]
    expect (code, _, err) = unless (code == ExitSuccess) (ioError (userError ("arc refused: " <> trim err)))
    allowRefusal (code, _, err) = when (options.verbose && code /= ExitSuccess) (putStrLn ("  (refused as the plan allows: " <> trim err <> ")"))

check :: Options -> Sandbox -> Maybe String -> IO Outcome
check options sandbox probe = do
  (_, out, err) <- arc options sandbox sandbox.worktree (Declared "author") [ ("PROBE_ENV", identity) | Just identity <- [probe] ] ["check", changeSlug, "--json"] ""
  pure $ case eitherDecodeStrict' (BS.pack out) of
    Right (CheckOutput isReady found) -> Answered Answer { ready = isReady, blockers = Set.fromList (map (.blocker) found) }
    Left failure                      -> ReplayFailed ("check JSON: " <> failure <> "; stderr: " <> trim err)

-- processes

arc :: Options -> Sandbox -> FilePath -> Identity -> [(String, String)] -> [String] -> String -> IO (ExitCode, String, String)
arc options sandbox dir identity extra args input = do
  when options.verbose (putStrLn ("  $ arc " <> unwords args))
  let env = sandbox.baseEnv <> extra <> [ ("ARC_ACTOR", actor) | Declared actor <- [identity] ]
  readCreateProcessWithExitCode (proc options.arcBinary args) { cwd = Just dir, env = Just env } input

git :: Sandbox -> FilePath -> [String] -> IO ()
git sandbox dir args = do
  (code, _, err) <- gitOut sandbox dir args
  unless (code == ExitSuccess) (ioError (userError ("git " <> unwords args <> ": " <> trim err)))

gitOut :: Sandbox -> FilePath -> [String] -> IO (ExitCode, String, String)
gitOut sandbox dir args = readCreateProcessWithExitCode (proc "git" args) { cwd = Just dir, env = Just sandbox.baseEnv } ""

-- flags and small strings

verdictFlag :: VerdictKind -> String
verdictFlag = \case
  Approved         -> "approved"
  ChangesRequested -> "changes-requested"
  CommentOnly      -> "comment-only"

causeFlag :: VerdictKind -> [String]
causeFlag = \case
  ChangesRequested -> ["--cause", "executor"]
  _uncaused        -> []

externalFlag :: ExternalKind -> String
externalFlag = \case
  ExternalApproved         -> "approved"
  ExternalChangesRequested -> "changes-requested"
  ExternalRejected         -> "rejected"

debtKindFlag :: DebtKind -> String
debtKindFlag = \case
  NothingRead           -> "nothing-read"
  MergeResolutionUnread -> "merge-resolution-unread"
  RepairUnread          -> "repair-unread"
  ContributorOnly       -> "contributor-only"
  IndependentReview     -> "independent-review"

commaList :: [String] -> String
commaList = foldr1 (\item rest -> item <> "," <> rest)

trim :: String -> String
trim = unwords . words

replaceOnce :: String -> String -> String -> String
replaceOnce needle replacement haystack = case breakOn haystack of
  Just (before, after) -> before <> replacement <> after
  Nothing              -> haystack
  where
    breakOn text
      | needle `isPrefixOf` text = Just ("", drop (length needle) text)
      | otherwise = case text of
          []     -> Nothing
          c : cs -> do
            (before, after) <- breakOn cs
            pure (c : before, after)
