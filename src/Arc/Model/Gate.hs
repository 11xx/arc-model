{- | Reading a required gate.

Pass/fail, coverage, availability, and demonstrated falsification are four
separate readings of the same gate, kept apart because they answer four
different questions. Coverage asks whether the observation answers the
declaration, the tree, and the environment in force; a pass recorded for
another of any of the three is a result, never coverage. A run arc
observed on a dirty worktree answers for none of them unless a dirty-tree
waiver names exactly the revision it was recorded at.
-}
module Arc.Model.Gate
    ( GateCoverage(..)
    , EvidenceAvailability(..)
    , GateReading(..)
    , GateRefusal(..)
    , gateRefusalText
    , readGate
    , gateGreen
    ) where

import Arc.Model.Declaration
import Arc.Model.Identifiers
import Arc.Model.Ledger.Verification ( Verification, WorktreeState(..) )
import Arc.Model.Ledger.Verification qualified as Verification
import Arc.Model.Observed


-- | Whether the required declaration was evaluated, and against which tree
-- and environment.
data GateCoverage = Covered EventId
                  | NeverEvaluated
                  | EvaluatedOtherTree TreeId
                  | DeclarationMoved DeclarationId
                  | EvaluatedOtherEnvironment EnvironmentId EnvironmentId  -- ^ Recorded identity, then the one the probe yields here.
                  | EnvironmentUnrecorded                                  -- ^ The gate declares a probe and the evidence carries no identity.
                  | EnvironmentUnobserved                                  -- ^ The probe yielded no identity where the decision is made.
                  | EvaluatedDirtyTree                                     -- ^ The run read uncommitted changes, and no waiver names its revision.
                  | WorktreeUnrecorded                                     -- ^ The run recorded nothing about its worktree.
  deriving stock (Eq, Ord, Show)

-- | Whether evidence exists at all, and whether the record could be read.
data EvidenceAvailability = NotProduced
                          | Recorded ExecutionKind
                          | EvidenceUnreadable
  deriving stock (Eq, Ord, Show)

-- | Four independent readings of one required gate.
data GateReading = GateReading
  { gate         :: !GateName
  , result       :: !(Observed GateResult)    -- ^ Last result observed for this declaration, wherever it ran.
  , coverage     :: !GateCoverage             -- ^ Whether that observation answers the declaration, tree, and environment in force.
  , availability :: !EvidenceAvailability     -- ^ Whether any record exists, and whether it could be read.
  , falsified    :: !(Observed FailureLabel)  -- ^ The failure this gate was demonstrated to answer, when it was.
  }
  deriving stock (Eq, Ord, Show)

-- | Why a required gate does not count as green.
data GateRefusal = GateNotDeclared GateName
                 | GateNeverEvaluated GateName
                 | GateEvaluatedOtherTree GateName TreeId
                 | GateDeclarationChanged GateName
                 | GateFailed GateName EventId
                 | GateEvidenceUnreadable GateName
                 | GateEvaluatedOtherEnvironment GateName EnvironmentId EnvironmentId
                 | GateEnvironmentUnrecorded GateName
                 | GateEnvironmentUnobserved GateName
                 | GateEvaluatedDirtyTree GateName
                 | GateWorktreeUnrecorded GateName
  deriving stock (Eq, Ord, Show)

gateRefusalText :: GateRefusal -> String
gateRefusalText = \case
  GateNotDeclared (GateName name)    -> "gate " <> name <> " is required but not declared"
  GateNeverEvaluated (GateName name) -> "gate " <> name <> " has never been evaluated"
  GateFailed (GateName name) event   -> "gate " <> name <> " failed at event " <> show event
  GateEvaluatedOtherTree (GateName name) (TreeId tree)
    -> "gate " <> name <> " was evaluated at tree " <> tree <> ", not the evaluated tree"
  GateDeclarationChanged (GateName name)
    -> "gate " <> name <> " declaration changed; the declared check has not run"
  GateEvidenceUnreadable (GateName name)
    -> "gate " <> name <> " evidence could not be read; that is not a result"
  GateEvaluatedOtherEnvironment (GateName name) (EnvironmentId recorded) (EnvironmentId here)
    -> "gate " <> name <> " was evaluated in environment " <> recorded <> ", not " <> here
  GateEnvironmentUnrecorded (GateName name)
    -> "gate " <> name <> " evidence records no environment, so nothing says where it ran"
  GateEnvironmentUnobserved (GateName name)
    -> "gate " <> name <> " declares an environment probe that yielded no identity here"
  GateEvaluatedDirtyTree (GateName name)
    -> "gate " <> name <> " evidence was recorded on a dirty worktree, and no waiver covers its revision"
  GateWorktreeUnrecorded (GateName name)
    -> "gate " <> name <> " evidence records nothing about the worktree it ran in"

{- | Read one required gate from the recorded verifications, given the
identity the declaration's probe yields where the decision is made and the
revision the dirty-tree waiver in force names. Coverage and availability
are decided by the newest record, so an unreadable newest record leaves the
gate refused rather than falling back to an older pass; any older result is
reported beside them as a result, never as coverage.
-}
readGate :: GateName -> Declaration -> TreeId -> Observed EnvironmentId -> Maybe Revision -> [Verification] -> GateReading
readGate gate declaration tree here waived verifications = GateReading
  { gate         = gate
  , result       = maybe Omitted (Observed . (.result)) newestReadable
  , coverage     = coverage
  , availability = availability
  , falsified    = case newest atTree of
      Just v  -> maybe Omitted Observed v.answers
      Nothing -> Omitted
  }
  where
    matching       = [ v | v <- verifications, v.gate == gate, v.declaration == declaration.declarationId ]
    shape          = declarationShape declaration
    newestRecord   = newest matching
    newestReadable = newest (filter (.readable) matching)
    atTree         = [ v | v <- matching, v.shape == shape, v.tree == tree ]
    coverage = case newestRecord of
      Nothing -> NeverEvaluated
      Just v
        | not v.readable   -> NeverEvaluated
        | v.shape /= shape -> DeclarationMoved declaration.declarationId
        | v.tree /= tree   -> EvaluatedOtherTree v.tree
        | otherwise        -> worktreeCoverage v
    -- evidence somebody attests to carries no worktree of arc's observing;
    -- a run arc observed counts on a clean tree, or on a dirty one whose
    -- revision the waiver in force names
    worktreeCoverage v = case (v.execution, v.worktree) of
      (Attested, _)                        -> environmentCoverage v
      (RanLocally, Observed CleanWorktree) -> environmentCoverage v
      (RanLocally, Observed DirtyWorktree)
        | waived == Just v.revision        -> environmentCoverage v
        | otherwise                        -> EvaluatedDirtyTree
      (RanLocally, Omitted)                -> WorktreeUnrecorded
    -- a gate without a probe takes evidence from anywhere; one with a probe
    -- takes only evidence whose recorded identity is the one observed here
    environmentCoverage v = case declaration.environment of
      Nothing -> Covered v.event
      Just _  -> case (v.environment, here) of
        (Nothing, _)                  -> EnvironmentUnrecorded
        (Just _, Omitted)             -> EnvironmentUnobserved
        (Just recorded, Observed now)
          | recorded == now -> Covered v.event
          | otherwise       -> EvaluatedOtherEnvironment recorded now
    availability = case newestRecord of
      Nothing -> NotProduced
      Just v
        | not v.readable -> EvidenceUnreadable
        | otherwise      -> Recorded v.execution

{- | Whether a required gate counts as green, and why not when it does not.
The first question is coverage, so a pass recorded elsewhere never stands
in for the declaration, tree, and environment in force.
-}
gateGreen :: GateName -> Maybe Declaration -> TreeId -> Observed EnvironmentId -> Maybe Revision -> [Verification] -> Either GateRefusal GateReading
gateGreen gate Nothing _ _ _ _ = Left (GateNotDeclared gate)
gateGreen gate (Just declaration) tree here waived verifications =
  case reading.coverage of
    Covered event -> case reading.result of
      Observed GatePass -> Right reading
      Observed GateFail -> Left (GateFailed gate event)
      Omitted           -> Left (GateEvidenceUnreadable gate)
    NeverEvaluated -> case reading.availability of
      EvidenceUnreadable -> Left (GateEvidenceUnreadable gate)
      _produced          -> Left (GateNeverEvaluated gate)
    EvaluatedOtherTree other             -> Left (GateEvaluatedOtherTree gate other)
    DeclarationMoved _                   -> Left (GateDeclarationChanged gate)
    EvaluatedOtherEnvironment recorded now -> Left (GateEvaluatedOtherEnvironment gate recorded now)
    EnvironmentUnrecorded                -> Left (GateEnvironmentUnrecorded gate)
    EnvironmentUnobserved                -> Left (GateEnvironmentUnobserved gate)
    EvaluatedDirtyTree                   -> Left (GateEvaluatedDirtyTree gate)
    WorktreeUnrecorded                   -> Left (GateWorktreeUnrecorded gate)
  where
    reading = readGate gate declaration tree here waived verifications
