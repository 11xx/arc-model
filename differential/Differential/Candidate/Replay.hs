{-# LANGUAGE DeriveAnyClass #-}
{- | Replaying a candidate encoding through the arc binary, and reading back
arc's answers in the channel's vocabulary.

Every case runs in a sandbox of its own, sealed by "Differential.Sandbox".
The repository holds the fixture — a gate that fails on demand and whose
probe prints the environment it is told to, the reuse policy, and the
brief's file — and two changes, the destination and a second change whose
brief is another contract. The commands run in the encoding's order; a
command the model records and arc refuses is a replay that broke, except
where the channel compares the refusal: the selection, the promotion, the
probe registration, and each retirement.
-}
module Differential.Candidate.Replay
    ( Coordinates(..)
    , Written(..)
    , Basis(..)
    , Selected(..)
    , Promoted(..)
    , Collected(..)
    , Found(..)
    , replay
    ) where

import Arc.Candidate ( Capture(..), CandidateId(..), DeclaredKind(..), EpisodeId(..), EvaluationId(..), Extent(..), Judgement(..), JudgementKind(..), Registration(..), ReusePolicy(..), ToolRecordId(..) )
import Arc.Model.Identifiers ( ActorId(..), DeclarationId(..), EnvironmentId(..), TreeId(..) )
import Arc.Model.Observed ( Observed(..) )
import Differential.Arc ( Options(..), Outcome(..) )
import Differential.Candidate.Encoding
import Differential.Sandbox qualified as Sandbox

import Control.Exception ( IOException, throwIO, try )
import Control.Monad ( foldM, unless, when )
import Data.Aeson ( FromJSON, eitherDecodeStrict' )
import Data.ByteString qualified as BS
import Data.ByteString.Builder ( stringUtf8, toLazyByteString )
import Data.ByteString.Lazy qualified as BL
import Data.Char ( isAsciiLower )
import Data.IORef ( newIORef, readIORef, writeIORef )
import Data.List ( isInfixOf, isPrefixOf, stripPrefix )
import Data.Map.Strict ( Map )
import Data.Map.Strict qualified as Map
import Data.Maybe ( fromMaybe, listToMaybe, mapMaybe )
import Data.Set ( Set )
import Data.Set qualified as Set
import GHC.Generics ( Generic )
import System.Directory ( createDirectoryIfMissing )
import System.Exit ( ExitCode(..) )
import System.FilePath ( (</>) )


-- | What the model's symbolic coordinates are in one replay.
data Coordinates = Coordinates
  { destination :: !String                  -- ^ The destination change's id.
  , base        :: !String                  -- ^ The revision the brief is based on, which holds its file.
  , trees       :: !(Map TreeId String)
  , evaluations :: !(Map EvaluationId String)
  , targetNow   :: !String                  -- ^ The target's head when the selection is asked.
  , proposed    :: !String                  -- ^ The target the proposal names.
  }
  deriving stock (Eq, Show)

-- | A registration write: recorded, or refused with arc's code.
data Written = WriteAccepted
             | WriteRefused !String
  deriving stock (Eq, Ord, Show)

{- | A recorded selection's basis. An evaluation is its gate, its event, and
the registration it was recorded for; a read is its requirement, the
requirement's extent, and the tool record meeting it.
-}
data Basis = Basis
  { destination  :: !String
  , target       :: !String
  , tree         :: !String
  , evaluations  :: !(Set (String, String, String))
  , reads        :: !(Set (String, String, String))
  , reuse        :: !String
  , contributors :: !(Set String)
  , selector     :: !String
  }
  deriving stock (Eq, Ord, Show)

data Selected = SelectRefused !(Set String)
              | SelectRecorded !Basis
  deriving stock (Eq, Ord, Show)

-- | What became of a selection's promotion.
data Promoted = NothingSelected
              | PromotedAs !String !Bool         -- ^ The destination patchset, and whether the retention ref holds the promoted commit.
              | Unpromoted !(Maybe String)       -- ^ Standing without a promotion, and the code a retried promotion refused with.
  deriving stock (Eq, Ord, Show)

data Collected = Retired
               | RetireRefused
  deriving stock (Eq, Ord, Show)

data Found = Found
  { probe      :: !(Maybe Written)
  , selection  :: !Selected
  , promotion  :: !Promoted
  , collection :: ![(CandidateId, Collected)]
  }
  deriving stock (Eq, Show)

-- json shapes

newtype Shown = Shown { candidates :: [ShownCandidate] }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

data ShownCandidate = ShownCandidate
  { tree       :: String
  , selections :: [ShownSelection]
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

data ShownSelection = ShownSelection
  { event_id     :: String
  , destination  :: String
  , status       :: String
  , patchset_id  :: Maybe String
  , revision     :: Maybe String
  , target       :: String
  , reuse        :: String
  , evaluations  :: [ShownEvaluation]
  , reads        :: [ShownRead]
  , contributors :: [String]
  , selector     :: String
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

data ShownEvaluation = ShownEvaluation
  { gate         :: String
  , event_id     :: String
  , candidate_id :: String
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

data ShownRead = ShownRead
  { requirement :: ShownRequirement
  , record      :: String
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

data ShownRequirement = ShownRequirement
  { path     :: Maybe String
  , revision :: Maybe String
  , extent   :: ShownExtent
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

data ShownExtent = ShownExtent
  { kind :: String
  , from :: Maybe Int
  , to   :: Maybe Int
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

newtype Status = Status { claim :: Maybe StatusClaim }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

newtype StatusClaim = StatusClaim { claim_id :: String }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

newtype StatusChange = StatusChange { change_id :: String }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

-- the sandbox

data Sandbox = Sandbox
  { repo     :: !FilePath
  , worktree :: !FilePath  -- ^ The destination's checkout.
  , sealed   :: !Sandbox.Sandbox
  }

-- | The declaration's gate command: it fails on demand and names the
-- declaration, so two declarations are two commands.
gateCommand :: DeclarationId -> String
gateCommand (DeclarationId name) = "test -z \"$GATE_FAIL\" && : " <> name

gatesToml :: Bool -> DeclarationId -> String
gatesToml probeDeclared declared = unlines $
  [ "[gates.build]"
  , "command = " <> show (gateCommand declared)
  ]
  <> [ "environment = \"test -n \\\"$PROBE_ENV\\\" && echo $PROBE_ENV\"" | probeDeclared ]

policyToml :: ReusePolicy -> String
policyToml policy = unlines
  [ "[candidates]"
  , "evaluation_reuse = " <> show (reuseText policy)
  ]
  where
    reuseText = \case
      ReuseNever                 -> "never" :: String
      ReuseOnMatchingCoordinates -> "matching-coordinates"

-- | The brief's file: thirty lines, so a read of the first twenty is partial.
contractText :: String
contractText = unlines (map show [1 .. 30 :: Int])

-- | Replay one encoding in a fresh sandbox under the given directory.
replay :: Options -> FilePath -> Encoding -> IO (Outcome (Coordinates, Found))
replay options root encoding = do
  outcome <- try (replayIn options root encoding) :: IO (Either IOException (Coordinates, Found))
  pure (either (ReplayFailed . show) Answered outcome)

replayIn :: Options -> FilePath -> Encoding -> IO (Coordinates, Found)
replayIn options root encoding = do
  createDirectoryIfMissing True root
  sealed <- either throwIO pure =<< Sandbox.seal root
  let sandboxRoot = Sandbox.root sealed
      repo        = sandboxRoot </> "repo"
      sandbox     = Sandbox { repo = repo, worktree = sandboxRoot </> "home" </> ".worktrees" </> ("repo-" <> destinationSlug), sealed = sealed }
      run         = arc options sandbox
  -- the fixture
  createDirectoryIfMissing True (repo </> ".arc")
  writeFile (repo </> ".arc" </> "gates.toml") (gatesToml encoding.probeDeclared encoding.declaration)
  writeFile (repo </> ".arc" </> "policy.toml") (policyToml encoding.reuse)
  writeFile (repo </> contractFile) contractText
  writeFile (repo </> "README.md") "differential fixture\n"
  git sandbox repo ["init", "-q", "-b", "master"]
  git sandbox repo ["config", "user.name", "Tester"]
  git sandbox repo ["config", "user.email", "tester@example.invalid"]
  git sandbox repo ["config", "commit.gpgsign", "false"]
  git sandbox repo ["add", "."]
  git sandbox repo ["commit", "-q", "-m", "init"]
  baseRevision <- revParse sandbox "HEAD"
  expect =<< run repo lead [] ["begin", destinationSlug] ""
  expect =<< run repo lead [] ["begin", otherSlug] ""
  expect =<< run repo lead [] (["brief", destinationSlug, "--body-file", "-", "--base", baseRevision] <> concat [ ["--must-read", requirementLocator baseRevision extent] | extent <- encoding.mustRead ]) "the contract\n"
  expect =<< run repo lead [] ["brief", otherSlug, "--body-file", "-", "--base", baseRevision] "another contract\n"
  destinationId <- changeId options sandbox destinationSlug
  treeIds <- Map.fromList <$> mapM (\t -> (t,) <$> mkTree sandbox t) encoding.trees
  declared <- newIORef encoding.declaration
  let declare wanted = do
        current <- readIORef declared
        unless (current == wanted) $ do
          writeFile (repo </> ".arc" </> "gates.toml") (gatesToml encoding.probeDeclared wanted)
          git sandbox repo ["commit", "-q", "-m", "declare the gate as it is consumed", "--", ".arc/gates.toml"]
          writeIORef declared wanted
      treeOf t = fromMaybe (unTree t) (Map.lookup t treeIds)
  -- the model's events
  (claims, evaluated) <- foldM (command options sandbox baseRevision treeOf declare) (Map.empty, Map.empty) encoding.commands
  -- the selection
  declare encoding.declaration
  now <- revParse sandbox "master"
  when encoding.targetStale $ do
    writeFile (repo </> "stale.txt") "the target moves past the proposal\n"
    git sandbox repo ["add", "stale.txt"]
    git sandbox repo ["commit", "-q", "-m", "the target moves past the proposal"]
  let proposedTarget = now
  current <- revParse sandbox "master"
  let dirty = encoding.promoting /= PromoteAtSelection
  when dirty (appendFile (sandbox.worktree </> "README.md") "uncommitted\n")
  (_, selectOut, selectErr) <- run repo encoding.selector (environmentOf encoding.environment)
    ( ["candidate", "select", "--chosen", unCandidate encoding.chosen, "--into", destinationSlug, "--target", proposedTarget, "--rationale", "the plan's choice"]
      <> concat [ ["--evaluation", Map.findWithDefault (unEvaluation e) e evaluated] | e <- encoding.evaluations ]
    ) ""
  when dirty (git sandbox sandbox.worktree ["checkout", "--", "README.md"])
  recorded <- selectionOf options sandbox encoding.chosen
  retried <- case recorded of
    Just (_, shown) | encoding.promoting == StandDownThenMoveTarget -> do
      writeFile (repo </> "after.txt") "the target moves after the decision\n"
      git sandbox repo ["add", "after.txt"]
      git sandbox repo ["commit", "-q", "-m", "the target moves after the decision"]
      (_, out, err) <- run repo encoding.selector [] ["candidate", "promote", shown.event_id] ""
      pure (listToMaybe (codes (unwarned (out <> "\n" <> err))))
    _unretried -> pure Nothing
  settled <- selectionOf options sandbox encoding.chosen
  promotion <- case settled of
    Nothing -> pure NothingSelected
    Just (_, shown)
      | shown.status == "promoted" -> do
          held <- gitOut sandbox repo ["rev-parse", "--verify", "-q", "refs/arc/candidate-promotion/" <> unCandidate encoding.chosen <> "/" <> shown.event_id]
          pure (PromotedAs (fromMaybe "" shown.patchset_id) (Just (trim (snd3 held)) == shown.revision))
      | otherwise -> pure (Unpromoted retried)
  let selection = case settled of
        Just (chosenTree, shown) -> SelectRecorded (basisOf chosenTree shown)
        Nothing                  -> SelectRefused (Set.fromList (refusalLines (selectOut <> "\n" <> selectErr) <> codes (errors selectErr)))
  -- the probe registration
  probed <- case encoding.probe of
    Nothing                 -> pure Nothing
    Just (briefOf, written) -> do
      (code, _, err) <- run repo lead [] (registerArgs treeOf (\e -> Map.findWithDefault (unEpisode e) e claims) briefOf written) ""
      pure . Just $ case code of
        ExitSuccess -> WriteAccepted
        _refused    -> WriteRefused (fromMaybe (trim err) (listToMaybe (codes (errors err))))
  -- collection
  let retiring = [ c | c <- encoding.retire, probeKept probed c ]
      probeKept found c = case (encoding.probe, found) of
        (Just (_, written), Just (WriteRefused _)) -> c /= written.candidateId
        _kept                                      -> True
  collected <- mapM (\c -> (c,) <$> retire options sandbox c) retiring
  pure
    ( Coordinates
        { destination = destinationId
        , base        = baseRevision
        , trees       = treeIds
        , evaluations = evaluated
        , targetNow   = current
        , proposed    = proposedTarget
        }
    , Found
        { probe      = probed
        , selection  = selection
        , promotion  = promotion
        , collection = collected
        }
    )
  where
    snd3 (_, b, _) = b

-- | Run one of the model's events. A command arc refuses breaks the replay:
-- the model recorded the event.
command :: Options -> Sandbox -> String -> (TreeId -> String) -> (DeclarationId -> IO ())
        -> (Map EpisodeId String, Map EvaluationId String) -> Command -> IO (Map EpisodeId String, Map EvaluationId String)
command options sandbox baseRevision treeOf declare (claims, evaluated) = \case
  Claim episode -> do
    let actor = ActorId (unEpisode episode)
    expect =<< run actor [] ["claim", destinationSlug] ""
    (_, out, _) <- run actor [] ["status", destinationSlug, "--json"] ""
    claimed <- case eitherDecodeStrict' (utf8 out) of
      Right (Status (Just (StatusClaim identifier))) -> pure identifier
      Right _                                        -> ioError (userError "status names no claim")
      Left failure                                   -> ioError (userError ("status JSON: " <> failure))
    expect =<< run actor [] ["release-claim", destinationSlug] ""
    pure (Map.insert episode claimed claims, evaluated)
  Register briefOf written -> do
    expect =<< run lead [] (registerArgs treeOf episodeOf briefOf written) ""
    pure (claims, evaluated)
  ReadContext subject episode toolRecord coverage -> do
    digest <- contentDigest coverage
    expect =<< run (ActorId (unEpisode episode)) []
      ( [ "context", "read", "--subject", unCandidate subject, "--episode", episodeOf episode
        , "--record", unRecord toolRecord, "--path", contractFile, "--digest", digest, "--at", baseRevision ]
        <> case coverage of
             CoversWhole         -> ["--whole"]
             CoversLines from to -> ["--lines", show from <> "-" <> show to]
             CoversUnknown       -> []
      ) ""
    pure (claims, evaluated)
  Declare subject kind declarant citation -> do
    expect =<< run declarant []
      ( ["context", "declare", "--subject", unCandidate subject, kindFlag kind, "--path", contractFile, "--at", baseRevision]
        <> concat [ ["--citation", unRecord cited] | Just cited <- [citation] ]
      ) ""
    pure (claims, evaluated)
  CaptureReport toolRecord guarantee -> do
    expect =<< run lead [] ["context", "capture", "--record", unRecord toolRecord, captureFlag guarantee] ""
    pure (claims, evaluated)
  Judge judgement -> do
    expect =<< run judgement.declarant []
      ( ["candidate", "judge", unCandidate judgement.candidate, "--reason", "the plan's judgement"]
        <> case judgement.kind of
             RejectedAlternative -> ["--rejected"]
             SupersededBy other  -> ["--superseded-by", unCandidate other]
      ) ""
    pure (claims, evaluated)
  DeclareGate declared -> do
    declare declared
    pure (claims, evaluated)
  -- a failing gate exits non-zero after recording its evaluation
  Evaluate evaluation candidate evaluator environment fails -> do
    (_, out, err) <- run evaluator (environmentOf environment <> [ ("GATE_FAIL", "1") | fails ]) ["candidate", "verify", unCandidate candidate] ""
    case mapMaybe (stripPrefix "evaluation: ") (lines out) of
      event : _ -> pure (claims, Map.insert evaluation (trim event) evaluated)
      []        -> ioError (userError ("verify recorded no evaluation: " <> trim err))
  where
    run = arc options sandbox sandbox.repo
    episodeOf e = Map.findWithDefault (unEpisode e) e claims
    contentDigest coverage = do
      let window = case coverage of
            CoversLines from to -> "sed -n '" <> show from <> "," <> show to <> "p' " <> contractFile
            _whole              -> "cat " <> contractFile
      (code, out, err) <- Sandbox.readProcess sandbox.sealed sandbox.repo [] "sh" ["-c", window <> " | sha256sum"] ""
      unless (code == ExitSuccess) (ioError (userError ("sha256sum: " <> trim err)))
      pure ("sha256:" <> takeWhile (/= ' ') out)
    kindFlag = \case
      Cites     -> "--cites"
      ReliesOn  -> "--relies-on"
      Considers -> "--considers"
    captureFlag = \case
      Pinned   -> "--pinned"
      Unpinned -> "--unpinned"

registerArgs :: (TreeId -> String) -> (EpisodeId -> String) -> BriefOf -> Registration -> [String]
registerArgs treeOf episodeOf briefOf written = concat
  [ ["candidate", "register", "--id", unCandidate written.candidateId, "--tree", treeOf written.tree, "--brief", briefSlug]
  , concat [ ["--producer", producer] | ActorId producer <- Set.toList written.producers ]
  , concat [ ["--parent", unCandidate parent] | parent <- written.parents ]
  , concat [ ["--adopts", unCandidate adopted] | adopted <- written.adopts ]
  , concat [ ["--episode", episodeOf episode] | episode <- written.episodes ]
  ]
  where
    briefSlug = case briefOf of
      DestinationBrief -> destinationSlug
      OtherBrief       -> otherSlug

-- | The one selection recorded for the chosen registration, with the
-- registration's tree, if there is one.
selectionOf :: Options -> Sandbox -> CandidateId -> IO (Maybe (String, ShownSelection))
selectionOf options sandbox chosen = do
  (code, out, err) <- arc options sandbox sandbox.repo lead [] ["candidate", "show", unCandidate chosen, "--json"] ""
  case (code, eitherDecodeStrict' (utf8 out)) of
    (ExitSuccess, Right (Shown [shown])) -> case shown.selections of
      []        -> pure Nothing
      [single]  -> pure (Just (shown.tree, single))
      _several  -> ioError (userError "more than one selection names the chosen registration")
    (ExitSuccess, Right _) -> ioError (userError "candidate show named no single candidate")
    (ExitSuccess, Left failure) -> ioError (userError ("candidate JSON: " <> failure))
    (_, _) | "unknown-candidate" `isInfixOf` err -> pure Nothing
    (_, _) -> ioError (userError ("candidate show: " <> trim err))

basisOf :: String -> ShownSelection -> Basis
basisOf chosenTree shown = Basis
  { destination  = shown.destination
  , target       = shown.target
  , tree         = chosenTree
  , evaluations  = Set.fromList [ (e.gate, e.event_id, e.candidate_id) | e <- shown.evaluations ]
  , reads        = Set.fromList [ (requirementText r.requirement, extentText r.requirement.extent, r.record) | r <- shown.reads ]
  , reuse        = shown.reuse
  , contributors = Set.fromList shown.contributors
  , selector     = shown.selector
  }
  where
    requirementText r = fromMaybe "" r.path <> "@" <> fromMaybe "" r.revision
    extentText e = case (e.from, e.to) of
      (Just first, Just final) -> e.kind <> " " <> show first <> "-" <> show final
      _whole                   -> e.kind

-- | Retire one registration: permitted, or refused because a root reaches it.
retire :: Options -> Sandbox -> CandidateId -> IO Collected
retire options sandbox candidate = do
  (code, _, err) <- arc options sandbox sandbox.repo lead [] ["candidate", "retire", unCandidate candidate] ""
  case code of
    ExitSuccess -> pure Retired
    _refused
      | "rooted-candidate" `isInfixOf` err -> pure RetireRefused
      | otherwise                          -> ioError (userError ("candidate retire: " <> trim err))

changeId :: Options -> Sandbox -> String -> IO String
changeId options sandbox slug = do
  (_, out, _) <- arc options sandbox sandbox.repo lead [] ["status", slug, "--json"] ""
  case eitherDecodeStrict' (utf8 out) of
    Right (StatusChange identifier) -> pure identifier
    Left failure                    -> ioError (userError ("status JSON: " <> failure))

-- | A tree holding the fixture as committed and one file naming the tree.
mkTree :: Sandbox -> TreeId -> IO String
mkTree sandbox (TreeId name) = do
  writeFile (sandbox.repo </> "tree.txt") (name <> "\n")
  git sandbox sandbox.repo ["add", "tree.txt"]
  (_, out, _) <- gitOut sandbox sandbox.repo ["write-tree"]
  git sandbox sandbox.repo ["rm", "-q", "--cached", "tree.txt"]
  git sandbox sandbox.repo ["clean", "-q", "-f", "tree.txt"]
  pure (trim out)

-- | The codes that lead lines of the form @<code>: …@, a code being
-- lowercase words joined by hyphens.
codes :: String -> [String]
codes = mapMaybe code . lines
  where
    code line = case break (== ':') line of
      (word, ':' : _) | isCode word -> Just word
      _other                        -> Nothing
    isCode word = not (null word) && all (\c -> isAsciiLower c || c == '-') word && not ("-" `isPrefixOf` word)

-- | The error lines of a command's diagnostics, without their @error: @;
-- warnings are not refusals.
errors :: String -> String
errors = unlines . mapMaybe (stripPrefix "error: ") . lines

-- | A command's output without its warnings, and without the @error: @ of
-- its error lines.
unwarned :: String -> String
unwarned = unlines . map (\line -> fromMaybe line (stripPrefix "error: " line)) . filter (not . ("warning:" `isPrefixOf`)) . lines

-- | The codes of a refused selection: one line per ground after the
-- @selection refused:@ line.
refusalLines :: String -> [String]
refusalLines out = case break ("selection refused:" `isPrefixOf`) (lines out) of
  (_before, _header : grounds) -> codes (unlines grounds)
  (_before, [])                -> []

requirementLocator :: String -> Extent -> String
requirementLocator revision = \case
  Whole        -> revision <> ":" <> contractFile
  Lines from to -> revision <> ":" <> contractFile <> ":" <> show from <> "-" <> show to

environmentOf :: Observed EnvironmentId -> [(String, String)]
environmentOf = \case
  Observed (EnvironmentId identity) -> [("PROBE_ENV", identity)]
  Omitted                           -> []

-- | Who records what the model attributes to nobody in particular.
lead :: ActorId
lead = ActorId "lead"

-- processes

arc :: Options -> Sandbox -> FilePath -> ActorId -> [(String, String)] -> [String] -> String -> IO (ExitCode, String, String)
arc options sandbox dir (ActorId actor) extra args input = do
  when options.verbose (putStrLn ("  $ arc " <> unwords args))
  Sandbox.readProcess sandbox.sealed dir (extra <> [("ARC_ACTOR", actor)]) options.arcBinary args input

git :: Sandbox -> FilePath -> [String] -> IO ()
git sandbox dir args = do
  (code, _, err) <- gitOut sandbox dir args
  unless (code == ExitSuccess) (ioError (userError ("git " <> unwords args <> ": " <> trim err)))

gitOut :: Sandbox -> FilePath -> [String] -> IO (ExitCode, String, String)
gitOut sandbox dir args = Sandbox.readProcess sandbox.sealed dir [] "git" args ""

revParse :: Sandbox -> String -> IO String
revParse sandbox revision = do
  (code, out, err) <- gitOut sandbox sandbox.repo ["rev-parse", revision]
  unless (code == ExitSuccess) (ioError (userError ("git rev-parse " <> revision <> ": " <> trim err)))
  pure (trim out)

expect :: (ExitCode, String, String) -> IO ()
expect (code, _, err) = unless (code == ExitSuccess) (ioError (userError ("arc refused: " <> trim err)))

unCandidate :: CandidateId -> String
unCandidate (CandidateId name) = name

unEpisode :: EpisodeId -> String
unEpisode (EpisodeId name) = name

unEvaluation :: EvaluationId -> String
unEvaluation (EvaluationId name) = name

unRecord :: ToolRecordId -> String
unRecord (ToolRecordId name) = name

unTree :: TreeId -> String
unTree (TreeId name) = name

utf8 :: String -> BS.ByteString
utf8 = BL.toStrict . toLazyByteString . stringUtf8

trim :: String -> String
trim = unwords . words
