{- | Reading a required gate.

Pass/fail, coverage, availability, and demonstrated falsification are four
separate readings of the same gate, kept apart because they answer four
different questions.
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
import Arc.Model.Ledger.Verification ( Verification )
import Arc.Model.Ledger.Verification qualified as Verification
import Arc.Model.Observed


-- | Whether the required declaration was evaluated, and against which tree.
data GateCoverage = Covered EventId
                  | NeverEvaluated
                  | EvaluatedOtherTree TreeId
                  | DeclarationMoved DeclarationId
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
  , coverage     :: !GateCoverage             -- ^ Whether that observation answers the declaration and tree in force.
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

{- | Read one required gate from the recorded verifications. Coverage and
availability are decided by the newest record, so an unreadable newest
record leaves the gate refused rather than falling back to an older pass;
any older result is reported beside them as a result, never as coverage.
-}
readGate :: GateName -> Declaration -> TreeId -> [Verification] -> GateReading
readGate gate declaration tree verifications = GateReading
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
        | not v.readable  -> NeverEvaluated
        | v.shape /= shape -> DeclarationMoved declaration.declarationId
        | v.tree == tree   -> Covered v.event
        | otherwise        -> EvaluatedOtherTree v.tree
    availability = case newestRecord of
      Nothing -> NotProduced
      Just v
        | not v.readable -> EvidenceUnreadable
        | otherwise      -> Recorded v.execution

{- | Whether a required gate counts as green, and why not when it does not.
The first question is coverage, so a pass recorded elsewhere never stands
in for the declaration and tree in force.
-}
gateGreen :: GateName -> Maybe Declaration -> TreeId -> [Verification] -> Either GateRefusal GateReading
gateGreen gate Nothing _ _ = Left (GateNotDeclared gate)
gateGreen gate (Just declaration) tree verifications =
  case reading.coverage of
    Covered event -> case reading.result of
      Observed GatePass -> Right reading
      Observed GateFail -> Left (GateFailed gate event)
      Omitted           -> Left (GateEvidenceUnreadable gate)
    NeverEvaluated -> case reading.availability of
      EvidenceUnreadable -> Left (GateEvidenceUnreadable gate)
      _produced          -> Left (GateNeverEvaluated gate)
    EvaluatedOtherTree other -> Left (GateEvaluatedOtherTree gate other)
    DeclarationMoved _       -> Left (GateDeclarationChanged gate)
  where
    reading = readGate gate declaration tree verifications
