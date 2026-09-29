{-# LANGUAGE DeriveAnyClass #-}
{- | The one place a sandbox environment is built.

A sandbox is a root directory and an environment made from nothing: a few
ambient variables that carry no location ('allowlist'), every location Git
or arc reads pointed inside the root ('locations'), and fixed settings that
keep Git from reading system configuration or opening an editor ('fixed').
No other ambient variable reaches a sandboxed process.

A 'Sandbox' exists only once its self-check has passed. The pure check
('offences') runs first, over the environment as built; only when it finds
nothing does the probe write a nonce to Git's global configuration and read
back the file it landed in, which has to lie inside the root. Every process
started through 'readProcess' or 'process' has its final environment checked
again before it is spawned.
-}
module Differential.Sandbox
    ( Sandbox
    , SelfCheckRefused(..)
    , allowlist
    , locations
    , fixed
    , scenarioNames
    , mkEnvironment
    , offences
    , seal
    , root
    , origin
    , process
    , readProcess
    ) where

import Control.Exception ( Exception, IOException, throwIO, try )
import Control.Monad ( forM_, unless )
import Data.List ( isPrefixOf, nub, stripPrefix, (\\) )
import GHC.Clock ( getMonotonicTimeNSec )
import System.Directory ( canonicalizePath, createDirectoryIfMissing )
import System.Environment ( getEnvironment )
import System.Exit ( ExitCode(..) )
import System.FilePath ( isAbsolute, normalise, splitDirectories, (</>) )
import System.Posix.Files ( setFileMode )
import System.Process ( CreateProcess(..), proc, readCreateProcessWithExitCode )


-- | A root whose environment passed the self-check.
data Sandbox = Sandbox
  { root   :: !FilePath
  , env    :: ![(String, String)]
  , origin :: !FilePath  -- ^ The file the probe's global write landed in.
  }

-- | Why a sandbox refused to run anything, one line per offence.
newtype SelfCheckRefused = SelfCheckRefused [String]
  deriving stock (Show)
  deriving anyclass (Exception)

-- | The ambient variables a sandbox admits. None names a location Git or
-- arc reads configuration or state from.
allowlist :: [String]
allowlist = ["PATH", "LANG", "LC_ALL", "LC_CTYPE", "TZ"]

-- | Every location a sandboxed process may read or write, under the root.
locations :: FilePath -> [(String, FilePath)]
locations sandboxRoot =
  [ ("HOME",              home)
  , ("XDG_CONFIG_HOME",   home </> ".config")
  , ("XDG_DATA_HOME",     home </> ".local" </> "share")
  , ("XDG_STATE_HOME",    home </> ".local" </> "state")
  , ("XDG_CACHE_HOME",    home </> ".cache")
  , ("XDG_RUNTIME_DIR",   sandboxRoot </> "run")
  , ("TMPDIR",            sandboxRoot </> "tmp")
  , ("GIT_CONFIG_GLOBAL", home </> ".gitconfig")
  , ("ARC_SANDBOX",       home)
  ]
  where
    home = sandboxRoot </> "home"

-- | Settings every sandbox carries: no system Git configuration, no editor,
-- and the fixture's harness session in place of whatever runs the sandbox.
fixed :: [(String, String)]
fixed =
  [ ("GIT_CONFIG_NOSYSTEM", "1")
  , ("GIT_EDITOR",          "true")
  , ("GIT_SEQUENCE_EDITOR", "true")
  , ("ARC_HARNESS",         "test")
  , ("ARC_SESSION",         "session-a")
  ]

-- | The variables a scenario may add to one command: none is inherited, and
-- none names a location.
scenarioNames :: [String]
scenarioNames = ["ARC_ACTOR", "GATE_FAIL", "PROBE_ENV", "ACCEPT_FAIL"]

-- | The environment of a sandbox at the given root, from the ambient one.
mkEnvironment :: [(String, String)] -> FilePath -> [(String, String)]
mkEnvironment ambient sandboxRoot
  =  [ pair | pair@(name, _) <- ambient, name `elem` allowlist ]
  <> locations sandboxRoot
  <> fixed

{- | Everything wrong with an environment for a sandbox at the given root:
a variable nobody admitted, a variable set twice, a location that is unset
or lies outside the root, and a fixed setting with another value. An empty
list is a pass.
-}
offences :: FilePath -> [(String, String)] -> [String]
offences sandboxRoot environment = concat
  [ [ "the root " <> sandboxRoot <> " is not an absolute, normal path" | not (absoluteNormal sandboxRoot) ]
  , [ name <> " is forbidden" | name <- nub names, name `notElem` admitted ]
  , [ name <> " is set more than once" | name <- nub (names \\ nub names) ]
  , [ located name (lookup name environment) | (name, _) <- locations sandboxRoot, not (inRoot (lookup name environment)) ]
  , [ name <> " is not " <> value | (name, value) <- fixed, lookup name environment /= Just value ]
  ]
  where
    names    = map fst environment
    admitted = allowlist <> map fst (locations sandboxRoot) <> map fst fixed <> scenarioNames
    inRoot   = maybe False (inside sandboxRoot)
    located name = \case
      Nothing   -> name <> " is unset"
      Just path -> name <> "=" <> path <> " lies outside " <> sandboxRoot

-- | Whether a path lies at or under the root, read without the filesystem:
-- both absolute, neither climbing with @..@.
inside :: FilePath -> FilePath -> Bool
inside sandboxRoot path
  =  absoluteNormal sandboxRoot
  && isAbsolute path
  && ".." `notElem` splitDirectories path
  && splitDirectories (normalise sandboxRoot) `isPrefixOf` splitDirectories (normalise path)

absoluteNormal :: FilePath -> Bool
absoluteNormal path = isAbsolute path && ".." `notElem` splitDirectories path

{- | Seal the given directory as a sandbox: lay out its locations, build its
environment, check it, and only then probe Git's global configuration from
inside it. A refusal starts nothing further.
-}
seal :: FilePath -> IO (Either SelfCheckRefused Sandbox)
seal given = do
  sandboxRoot <- canonicalizePath given
  ambient     <- getEnvironment
  let environment = mkEnvironment ambient sandboxRoot
  case offences sandboxRoot environment of
    found@(_ : _) -> pure (Left (SelfCheckRefused found))
    []            -> do
      forM_ (locations sandboxRoot) $ \(name, path) ->
        unless (name == "GIT_CONFIG_GLOBAL") (createDirectoryIfMissing True path)
      setFileMode (sandboxRoot </> "run") 0o700
      probe sandboxRoot environment

{- | Write a nonce to Git's global configuration and read back where it
landed. Git reports the file as @file:<path>@, which has to lie inside the
root, beside the nonce itself. The key is removed again either way, and a
Git that cannot be started is a refusal too.
-}
probe :: FilePath -> [(String, String)] -> IO (Either SelfCheckRefused Sandbox)
probe sandboxRoot environment = either unstarted pure =<< try (probeWith sandboxRoot environment)
  where
    unstarted :: IOException -> IO (Either SelfCheckRefused Sandbox)
    unstarted failure = pure (Left (SelfCheckRefused ["probe: git could not run: " <> show failure]))

probeWith :: FilePath -> [(String, String)] -> IO (Either SelfCheckRefused Sandbox)
probeWith sandboxRoot environment = do
  nonce <- show <$> getMonotonicTimeNSec
  (wrote, _, wroteErr) <- git ["config", "--global", probeKey, nonce]
  (_, shown, shownErr) <- git ["config", "--global", "--show-origin", "--get", probeKey]
  _                    <- git ["config", "--global", "--unset", probeKey]
  let refuse detail = pure (Left (SelfCheckRefused ["probe: " <> detail]))
  case (wrote, readOrigin shown) of
    (ExitFailure _, _) -> refuse ("git config --global failed: " <> trimEnd wroteErr)
    (ExitSuccess, Just (path, value))
      | value /= nonce                -> refuse ("read back " <> value <> ", not the nonce " <> nonce)
      | not (inside sandboxRoot path) -> refuse ("the global configuration " <> path <> " lies outside " <> sandboxRoot)
      | otherwise                     -> pure (Right Sandbox { root = sandboxRoot, env = environment, origin = path })
    (ExitSuccess, Nothing) -> refuse ("no origin in " <> show shown <> " " <> trimEnd shownErr)
  where
    probeKey = "arc-model.sandbox-probe"
    readOrigin shown = case break (== '\t') (trimEnd shown) of
      (scope, '\t' : value) -> (, value) <$> stripPrefix "file:" scope
      _unreadable           -> Nothing
    git args = readCreateProcessWithExitCode (proc "git" args) { cwd = Just sandboxRoot, env = Just environment } ""

{- | The process to start in the sandbox, from a directory inside its root,
with the scenario's variables added. The final environment is checked again,
and a refusal is thrown rather than started.
-}
process :: Sandbox -> FilePath -> [(String, String)] -> FilePath -> [String] -> IO CreateProcess
process sandbox dir extra command args = do
  let environment = sandbox.env <> extra
      found       = offences sandbox.root environment
                 <> [ "the working directory " <> dir <> " lies outside " <> sandbox.root | not (inside sandbox.root dir) ]
  unless (null found) (throwIO (SelfCheckRefused found))
  pure (proc command args) { cwd = Just dir, env = Just environment }

-- | Run a command in the sandbox and collect its exit, output, and errors.
readProcess :: Sandbox -> FilePath -> [(String, String)] -> FilePath -> [String] -> String -> IO (ExitCode, String, String)
readProcess sandbox dir extra command args input = do
  started <- process sandbox dir extra command args
  readCreateProcessWithExitCode started input

root :: Sandbox -> FilePath
root sandbox = sandbox.root

origin :: Sandbox -> FilePath
origin sandbox = sandbox.origin

trimEnd :: String -> String
trimEnd = reverse . dropWhile (`elem` ("\n\r " :: String)) . reverse
