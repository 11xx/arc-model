{- | The sandbox's self-check: the pure check refuses each way out of the
root and names it, a built environment passes, and the probe in a sealed
sandbox finds Git's global configuration inside the root. The probe runs
only after the pure check has passed on the same environment.
-}
module SandboxChecks ( sandboxChecks ) where

import Differential.Sandbox ( SelfCheckRefused(..) )
import Differential.Sandbox qualified as Sandbox
import Render

import Data.List ( isInfixOf, isPrefixOf )
import System.Directory ( canonicalizePath, getTemporaryDirectory, removePathForcibly )
import System.Environment ( getEnvironment )
import System.FilePath ( (</>) )
import System.Posix.Temp ( mkdtemp )


sandboxChecks :: IO [Check]
sandboxChecks = do
  probed <- probeCheck
  pure (pureChecks <> [probed])

-- | A root nothing is written under; the pure check never touches it.
fakeRoot :: FilePath
fakeRoot = "/nonexistent/arc-model-sandbox"

-- | An ambient environment carrying everything a sandbox must not inherit.
hostile :: [(String, String)]
hostile =
  [ ("PATH", "/usr/bin"), ("LANG", "C.UTF-8"), ("HOME", "/home/operator")
  , ("XDG_CONFIG_HOME", "/home/operator/.config"), ("XDG_DATA_HOME", "/home/operator/.local/share")
  , ("XDG_STATE_HOME", "/home/operator/.local/state"), ("XDG_CACHE_HOME", "/home/operator/.cache")
  , ("TMPDIR", "/var/tmp"), ("GIT_CONFIG_GLOBAL", "/home/operator/.gitconfig"), ("GIT_DIR", "/elsewhere")
  , ("CODEX_HOME", "/home/operator/.codex"), ("CARGO_HOME", "/home/operator/.cargo")
  , ("CLAUDE_CODE_SESSION_ID", "session"), ("ARC_ACTOR", "operator"), ("GITHUB_TOKEN", "secret")
  ]

pointed :: String -> FilePath -> [(String, String)]
pointed name path = [ (key, if key == name then path else value) | (key, value) <- Sandbox.mkEnvironment [] fakeRoot ]

-- | A refusal that names the variable.
refuses :: String -> [(String, String)] -> [String] -> Check
refuses label environment named = case Sandbox.offences fakeRoot environment of
  [] -> failCheck label "passed"
  found
    | all (\name -> any ((name <> " ") `isPrefixOf`) found || any ((name <> "=") `isPrefixOf`) found) named -> passCheck label ""
    | otherwise -> failCheck label (show found)

pureChecks :: [Check]
pureChecks =
  [ refuses "sandbox: XDG_CONFIG_HOME outside the root is refused" (pointed "XDG_CONFIG_HOME" "/home/operator/.config") ["XDG_CONFIG_HOME"]
  , refuses "sandbox: GIT_CONFIG_GLOBAL outside the root is refused" (pointed "GIT_CONFIG_GLOBAL" "/home/operator/.gitconfig") ["GIT_CONFIG_GLOBAL"]
  , refuses "sandbox: HOME outside the root is refused" (pointed "HOME" "/home/operator") ["HOME"]
  , refuses "sandbox: HOME climbing out of the root is refused" (pointed "HOME" (fakeRoot </> ".." </> "operator")) ["HOME"]
  , refuses "sandbox: an unset location is refused" [ pair | pair@(name, _) <- Sandbox.mkEnvironment [] fakeRoot, name /= "TMPDIR" ] ["TMPDIR"]
  , refuses "sandbox: forbidden variables are refused, each named"
      (Sandbox.mkEnvironment [] fakeRoot <> [("CODEX_HOME", "/x"), ("CARGO_HOME", "/y"), ("CLAUDE_CODE_SESSION_ID", "z")])
      ["CODEX_HOME", "CARGO_HOME", "CLAUDE_CODE_SESSION_ID"]
  , refuses "sandbox: a scenario variable cannot override a location" (Sandbox.mkEnvironment [] fakeRoot <> [("HOME", fakeRoot)]) ["HOME"]
  , expectEq "sandbox: a built environment passes the pure check" [] (Sandbox.offences fakeRoot built)
  , expectEq "sandbox: a built environment admits only the allowlist from the ambient one"
      [("PATH", "/usr/bin"), ("LANG", "C.UTF-8")]
      [ pair | pair@(name, _) <- built, name `elem` Sandbox.allowlist ]
  ]
  where
    built = Sandbox.mkEnvironment hostile fakeRoot

-- | Seal a real sandbox and report where the probe's global write landed.
-- The same environment passes the pure check before the probe may run.
probeCheck :: IO Check
probeCheck = do
  scratch <- getTemporaryDirectory
  given   <- mkdtemp (scratch </> "arc-model-spec-sandbox-")
  sandboxRoot <- canonicalizePath given
  ambient <- getEnvironment
  checked <- case Sandbox.offences sandboxRoot (Sandbox.mkEnvironment ambient sandboxRoot) of
    found@(_ : _) -> pure (failCheck label ("the pure check refused before the probe: " <> show found))
    []            -> Sandbox.seal sandboxRoot >>= \case
      Left (SelfCheckRefused found) -> pure (failCheck label (show found))
      Right sandbox
        | (sandboxRoot <> "/") `isPrefixOf` Sandbox.origin sandbox && ".gitconfig" `isInfixOf` Sandbox.origin sandbox
                    -> pure (passCheck label ("origin " <> Sandbox.origin sandbox))
        | otherwise -> pure (failCheck label ("origin " <> Sandbox.origin sandbox <> " outside " <> sandboxRoot))
  removePathForcibly sandboxRoot
  pure checked
  where
    label = "sandbox: the probe in a sealed sandbox reports an origin inside the root"
