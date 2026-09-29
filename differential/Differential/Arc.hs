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
    , DryRun(..)
    , PostIntegration(..)
    , runPlan
    , runExecution
    , runCoverage
    , checkRefusedConflictingGates
    ) where

import Arc.Model ( DebtKind(..), ExternalKind(..), Policy, VerdictKind(..) )
import Arc.Model.Policy qualified as Policy
import Differential.Plan

import Control.Exception ( IOException, try )
import Control.Monad ( unless, when )
import Data.Aeson ( FromJSON, Value, eitherDecodeStrict' )
import Data.ByteString.Builder ( stringUtf8, toLazyByteString )
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
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
data Outcome a = Answered a
               | ReplayFailed String
  deriving stock (Eq, Show, Functor)

{- | What @arc integrate --dry-run@ said, and what @arc check@ reports in the
same world: the dry run's own output is prose, and its refusals are the
check's blockers with the check's exit code.
-}
data DryRun = DryRun
  { exit  :: !Int
  , after :: !Answer
  }
  deriving stock (Eq, Show)

-- | What arc records once the plan has tried to integrate and audit: the
-- authorization basis the closure names, by which of its slots are filled,
-- the newest audit's verdict, the audit findings left open, and whether
-- @arc query --debt@ lists the change as owing a review.
data PostIntegration = PostIntegration
  { integrated        :: !Bool
  , basis             :: !(Set String)
  , auditVerdict      :: !(Maybe String)
  , openAuditFindings :: !Int
  , owed              :: !Bool
  }
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

newtype ReplicaId = ReplicaId { repository_id :: String }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

data ShowOutput = ShowOutput
  { closure        :: Maybe ClosureRow
  , audit_verdicts :: Maybe [AuditRow]  -- ^ Absent where nothing was audited.
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

data ClosureRow = ClosureRow
  { outcome       :: String
  , authorization :: Maybe BasisRow
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

data BasisRow = BasisRow
  { verdict_event_id    :: Maybe String
  , external_verdict    :: Maybe Value
  , audit_debt_event_id :: Maybe String
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

newtype AuditRow = AuditRow { verdict :: String }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

newtype AuditFindingsOutput = AuditFindingsOutput { findings :: [AuditFindingRow] }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

newtype AuditFindingRow = AuditFindingRow { dispositions :: [Value] }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

newtype DebtRow = DebtRow { change_id :: String }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

-- the sandbox

data Sandbox = Sandbox
  { repo     :: !FilePath
  , peer     :: !FilePath  -- ^ A second repository, whose store stands in for a paired replica.
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

-- | The acceptance probe a brief declares: it fails on demand.
probesJson :: String
probesJson = "[{\"name\":\"accept\",\"command\":\"test -z \\\"$ACCEPT_FAIL\\\"\"}]"

-- | A second declaration of the required gate, in the operator's layer,
-- that disagrees with the project's on the command.
operatorGatesToml :: String
operatorGatesToml = unlines
  [ "[gates.build]"
  , "command = \"true\""
  ]

-- | The policy file, declaring these paths dangerous.
policyToml :: Policy -> [FilePath] -> String
policyToml policy dangerous = unlines
  [ "[policy]"
  , "forbid_self_approval = " <> bool policy.forbidSelfApproval
  , "require_declared_actor = " <> bool policy.requireDeclaredActor
  , ""
  , "[danger]"
  , "paths = [" <> commaList [ show path | path <- dangerous ] <> "]"
  ]
  where
    bool value = if value then "true" else "false"

-- | Run one plan in a fresh sandbox under the given directory and ask
-- arc for its answer.
runPlan :: Options -> FilePath -> Plan -> IO (Outcome Answer)
runPlan options root planned = do
  sandbox <- mkSandbox options root planned.policy
  outcome <- try (runSteps options sandbox planned.steps) :: IO (Either IOException ())
  case outcome of
    Left failure -> pure (ReplayFailed (show failure))
    Right ()     -> check options sandbox (checkDir sandbox planned) planned.probeAtCheck

{- | Run one plan in a fresh sandbox, ask arc for its decision, make the
plan's moves, and ask @arc integrate --dry-run@ what an integration would
do now, then @arc check@ why.
-}
runExecution :: Options -> FilePath -> Plan -> IO (Outcome DryRun)
runExecution options root planned = do
  sandbox <- mkSandbox options root planned.policy
  let dir = checkDir sandbox planned
  outcome <- try (runSteps options sandbox planned.steps) :: IO (Either IOException ())
  case outcome of
    Left failure -> pure (ReplayFailed (show failure))
    Right ()     -> check options sandbox dir planned.probeAtCheck >>= \case
      ReplayFailed failure -> pure (ReplayFailed failure)
      Answered _           -> do
        moved <- try (runSteps options sandbox planned.execution) :: IO (Either IOException ())
        case moved of
          Left failure -> pure (ReplayFailed (show failure))
          Right ()     -> do
            (code, _, _) <- arc options sandbox dir (Declared "author") probeEnv ["integrate", changeSlug, "--dry-run"] ""
            fmap (DryRun (exitNumber code)) <$> check options sandbox dir planned.probeAtCheck
  where
    probeEnv = [ ("PROBE_ENV", identity) | Just identity <- [planned.probeAtCheck] ]
    exitNumber = \case
      ExitSuccess      -> 0
      ExitFailure code -> code

{- | Run one plan in a fresh sandbox, ask arc for its decision, make the
plan's moves, integrate for real, record the plan's audits, and read back
what arc recorded. An integration or audit arc refuses is part of the
answer, not a broken replay.
-}
runCoverage :: Options -> FilePath -> Plan -> IO (Outcome PostIntegration)
runCoverage options root planned = do
  sandbox <- mkSandbox options root planned.policy
  let dir = checkDir sandbox planned
  outcome <- try (runSteps options sandbox (planned.steps)) :: IO (Either IOException ())
  case outcome of
    Left failure -> pure (ReplayFailed (show failure))
    Right ()     -> check options sandbox dir planned.probeAtCheck >>= \case
      ReplayFailed failure -> pure (ReplayFailed failure)
      Answered _           -> do
        acted <- try (runSteps options sandbox planned.execution) :: IO (Either IOException ())
        case acted of
          Left failure -> pure (ReplayFailed (show failure))
          Right ()     -> do
            _ <- arc options sandbox dir (Declared "author") probeEnv ["integrate", changeSlug] ""
            audited <- try (runSteps options sandbox planned.audits) :: IO (Either IOException ())
            either (pure . ReplayFailed . show) (const (recorded options sandbox)) audited
  where
    probeEnv = [ ("PROBE_ENV", identity) | Just identity <- [planned.probeAtCheck] ]

-- | Read what arc recorded about the change after its integration.
recorded :: Options -> Sandbox -> IO (Outcome PostIntegration)
recorded options sandbox = do
  (_, shown, _)  <- arc options sandbox sandbox.repo (Declared "author") [] ["show", changeSlug, "--json"] ""
  (_, audits, _) <- arc options sandbox sandbox.repo (Declared "author") [] ["findings", changeSlug, "--audit", "--format", "json"] ""
  (_, owing, _)  <- arc options sandbox sandbox.repo (Declared "author") [] ["query", "--debt", "--json"] ""
  pure $ case (decoded shown, decoded audits, decoded owing) of
    (Right (ShowOutput closure auditRows), Right (AuditFindingsOutput findingRows), Right debtRows) -> Answered PostIntegration
      { integrated        = maybe False ((== "integrated") . (.outcome)) closure
      , basis             = maybe Set.empty slots (closure >>= (.authorization))
      , auditVerdict      = (.verdict) <$> listToMaybe (reverse (concat auditRows))
      , openAuditFindings = length [ () | AuditFindingRow [] <- findingRows ]
      , owed              = not (null (debtRows :: [DebtRow]))
      }
    (Left failure, _, _) -> ReplayFailed ("show JSON: " <> failure)
    (_, Left failure, _) -> ReplayFailed ("findings JSON: " <> failure)
    (_, _, Left failure) -> ReplayFailed ("query JSON: " <> failure)
  where
    decoded :: FromJSON a => String -> Either String a
    decoded = eitherDecodeStrict' . utf8
    slots basisRow = Set.fromList $ concat
      [ [ "verdict"  | Just _ <- [basisRow.verdict_event_id] ]
      , [ "debt"     | Just _ <- [basisRow.audit_debt_event_id] ]
      , [ "external" | Just _ <- [basisRow.external_verdict] ]
      ]

-- | Where the decision is asked: the change's worktree, or the main checkout
-- once the branch is gone.
checkDir :: Sandbox -> Plan -> FilePath
checkDir sandbox planned = if planned.inWorktree then sandbox.worktree else sandbox.repo

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
      sandbox = Sandbox { repo = repo, peer = root </> "peer", home = home, worktree = home </> ".worktrees" </> ("repo-" <> changeSlug), baseEnv = baseEnv }
  writeFile (repo </> ".arc" </> "gates.toml") gatesToml
  writeFile (repo </> ".arc" </> "policy.toml") (policyToml policy ["danger.txt"])
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
      Revert ->
        git sandbox wt ["revert", "--no-edit", "HEAD"]
      Snapshot contributors ->
        expect =<< arc options sandbox wt author [] (["snapshot", changeSlug] <> [ "--contributors=" <> commaList contributors | not (null contributors) ]) ""
      Verify run -> do
        -- a failing gate makes verify exit non-zero after recording the
        -- evidence, which is the run the plan asked for, and so does a run
        -- against the merge whose probe yields nothing
        when run.dirty (appendFile (wt </> "README.md") "uncommitted\n")
        let target = if run.against then ["--against", "master"] else ["--gate", "build"]
        (if run.fails || run.against then allowRefusal else expect) =<< arc options sandbox wt author (gateEnv run) (["verify", changeSlug] <> target) ""
        when run.dirty (git sandbox wt ["checkout", "--", "README.md"])
      WaiveDirty ->
        expect =<< arc options sandbox wt author [] ["verify", changeSlug, "--command", "true", "--waive-dirty", "generated output"] ""
      AdvanceTarget -> do
        writeFile (sandbox.repo </> "target.txt") "target\n"
        git sandbox sandbox.repo ["add", "target.txt"]
        git sandbox sandbox.repo ["commit", "-q", "-m", "the target moves"]
      ConflictTarget file -> do
        writeFile (sandbox.repo </> file) "target\n"
        git sandbox sandbox.repo ["add", file]
        git sandbox sandbox.repo ["commit", "-q", "-m", "the target adds " <> file]
      Brief -> do
        (_, base, _) <- gitOut sandbox wt ["rev-parse", "HEAD"]
        expect =<< arc options sandbox wt author [] ["brief", changeSlug, "--body-file", "-", "--base", trim base, "--probes-json", probesJson] "contract\n"
      ProbeBaseline fails ->
        allowRefusal =<< arc options sandbox wt author (acceptEnv fails) ["verify", changeSlug, "--probe", "accept", "--probe-phase", "baseline"] ""
      ProbeFinal fails ->
        allowRefusal =<< arc options sandbox wt author (acceptEnv fails) ["verify", changeSlug, "--probe", "accept", "--probe-phase", "final"] ""
      DeleteBranch -> do
        git sandbox sandbox.repo ["worktree", "remove", "--force", wt]
        git sandbox sandbox.repo ["branch", "-D", "arc/" <> changeSlug]
      Iterate ->
        expect =<< arc options sandbox wt author [] ["iterating", changeSlug] ""
      ConflictDeclarations -> do
        createDirectoryIfMissing True (sandbox.repo </> ".git" </> "arc")
        writeFile (sandbox.repo </> ".git" </> "arc" </> "operator-policy.toml") operatorGatesToml
      MoveTarget -> do
        writeFile (sandbox.repo </> "target-after.txt") "after\n"
        git sandbox sandbox.repo ["add", "target-after.txt"]
        git sandbox sandbox.repo ["commit", "-q", "-m", "the target moves after the decision"]
      MovePolicy policy file ->
        -- the file the change edits is dangerous exactly when the policy
        -- requires independence, as the plan's own policy has danger.txt
        writeFile (wt </> ".arc" </> "policy.toml") (policyToml policy [ if policy.independentVerdictRequired then file else "untouched.txt" ])
      Audit kind independent ->
        -- arc refuses an audit of a change that did not integrate, which is
        -- the answer when the plan's integration was refused
        allowRefusal =<< arc options sandbox sandbox.repo (Declared (if independent then "other" else "author")) []
          (["audit", changeSlug, "--verdict", verdictFlag kind, "--body", "audit"] <> [ "--findings-json" | kind == ChangesRequested ] <> [ "-" | kind == ChangesRequested ])
          (if kind == ChangesRequested then "[{\"summary\":\"audit\",\"body\":\"raised\",\"severity\":\"major\",\"blocking\":true}]" else "")
      -- the store is one for every checkout, so the pairing is made from the
      -- main checkout, which outlives a deleted branch
      WithholdAuthority -> do
        createDirectoryIfMissing True sandbox.peer
        git sandbox sandbox.peer ["init", "-q", "-b", "master"]
        git sandbox sandbox.peer ["commit", "-q", "--allow-empty", "-m", "peer"]
        (_, listed, _) <- arc options sandbox sandbox.peer author [] ["replica", "id", "--json"] ""
        peerId <- case eitherDecodeStrict' (utf8 listed) of
          Right (ReplicaId found) -> pure found
          Left failure            -> ioError (userError ("replica id JSON: " <> failure))
        expect =<< arc options sandbox sandbox.repo author [] ["replica", "init", "here"] ""
        expect =<< arc options sandbox sandbox.repo author [] ["replica", "pair", "elsewhere", "--repository-id", peerId] ""
        expect =<< arc options sandbox sandbox.repo author [] ["replica", "authority", "offer", "--to", "elsewhere"] ""
      Review identity kind ->
        -- a verdict nobody declared is refused where policy requires a
        -- declared actor; the plan asks anyway, because the model records it
        allowRefusal =<< arc options sandbox wt identity [] (["review", changeSlug, "--verdict", verdictFlag kind, "--body", "review"] <> causeFlag kind) ""
      Finding identity ->
        expect =<< arc options sandbox wt identity [] ["review", changeSlug, "--verdict", "comment-only", "--findings-json", "-"]
          "[{\"summary\":\"finding\",\"body\":\"raised\",\"severity\":\"major\",\"blocking\":true}]"
      ResolveFinding -> do
        (_, listed, _) <- arc options sandbox wt author [] ["findings", changeSlug, "--format", "json"] ""
        identifier <- case eitherDecodeStrict' (utf8 listed) of
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
    acceptEnv fails = [ ("ACCEPT_FAIL", "1") | fails ]
    expect (code, _, err) = unless (code == ExitSuccess) (ioError (userError ("arc refused: " <> trim err)))
    allowRefusal (code, _, err) = when (options.verbose && code /= ExitSuccess) (putStrLn ("  (refused as the plan allows: " <> trim err <> ")"))

{- | Ask arc for its decision from the given checkout. A check arc refuses
outright answers no blockers; the one such refusal a plan produces, a
conflicting gate declaration, is recorded under
'checkRefusedConflictingGates' so it can be compared, and any other is a
replay that broke.
-}
check :: Options -> Sandbox -> FilePath -> Maybe String -> IO (Outcome Answer)
check options sandbox dir probe = do
  (_, out, err) <- arc options sandbox dir (Declared "author") [ ("PROBE_ENV", identity) | Just identity <- [probe] ] ["check", changeSlug, "--json"] ""
  pure $ case eitherDecodeStrict' (utf8 out) of
    Right (CheckOutput isReady found) -> Answered Answer { ready = isReady, blockers = Set.fromList (map (.blocker) found) }
    Left failure
      | "error: conflicting gate declarations" `isPrefixOf` err -> Answered Answer { ready = False, blockers = Set.singleton checkRefusedConflictingGates }
      | otherwise -> ReplayFailed ("check JSON: " <> failure <> "; stderr: " <> trim err)

-- | The name the differential gives arc's refusal to check at all under
-- conflicting gate declarations. It is not one of arc's blockers.
checkRefusedConflictingGates :: String
checkRefusedConflictingGates = "check-refused:conflicting-gate-declarations"


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

-- | A process's output as the UTF-8 it was printed in; arc prints more than
-- ASCII.
utf8 :: String -> BS.ByteString
utf8 = BL.toStrict . toLazyByteString . stringUtf8

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
