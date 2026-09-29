{- | Run one command in a fresh sandbox: the way a disagreement's replay
steps, or any other command that touches arc or Git for a scenario, is run
by hand.

> arc-model-sandbox [--keep] <command> [args...]

The root is created under the system temporary directory and sealed by
"Differential.Sandbox"; the command runs from the root with the sealed
environment, and the root is removed afterwards unless @--keep@, which
prints its path. The exit status is the command's, or 70 when the
self-check refuses.
-}
module Main ( main ) where

import Differential.Sandbox ( SelfCheckRefused(..) )
import Differential.Sandbox qualified as Sandbox

import Control.Exception ( finally )

import System.Directory ( getTemporaryDirectory, removePathForcibly )
import System.Environment ( getArgs )
import System.Exit ( ExitCode(..), exitWith )
import System.FilePath ( (</>) )
import System.IO ( hPutStr, hPutStrLn, stderr )
import System.Posix.Temp ( mkdtemp )
import System.Process ( CreateProcess(..), createProcess, waitForProcess )


main :: IO ()
main = getArgs >>= \case
  "--keep" : command : args -> replay True command args
  command : args
    | command /= "--keep"   -> replay False command args
  _usage                    -> hPutStr stderr usage >> exitWith (ExitFailure 64)

replay :: Bool -> FilePath -> [String] -> IO ()
replay keep command args = do
  scratch <- getTemporaryDirectory
  given   <- mkdtemp (scratch </> "arc-model-sandbox-")
  Sandbox.seal given >>= \case
    Left (SelfCheckRefused found) -> do
      hPutStrLn stderr "arc-model-sandbox: the self-check refused this sandbox:"
      mapM_ (hPutStrLn stderr . ("  " <>)) found
      removePathForcibly given
      exitWith (ExitFailure 70)
    Right sandbox -> do
      let sandboxRoot = Sandbox.root sandbox
      let run = do
            started           <- Sandbox.process sandbox sandboxRoot [] command args
            (_, _, _, handle) <- createProcess started { delegate_ctlc = True }
            waitForProcess handle
          done
            | keep      = hPutStrLn stderr ("arc-model-sandbox: kept " <> sandboxRoot)
            | otherwise = removePathForcibly sandboxRoot
      exitWith =<< (run `finally` done)

usage :: String
usage = unlines
  [ "usage: arc-model-sandbox [--keep] <command> [args...]"
  , ""
  , "Runs the command from a fresh, sealed sandbox root; run a script with"
  , "`bash <script>`. The root is removed afterwards unless --keep, which"
  , "prints its path. Exits with the command's status, or 70 when the"
  , "sandbox's self-check refuses."
  ]
