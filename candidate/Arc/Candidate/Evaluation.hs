{- | Evaluation and review records, built from supplied observations.

The model runs nothing. An evaluation record carries what the shell
observed of one execution — its outcome and the environment it ran in —
and either may be 'Omitted'. An omitted outcome is unknown, never a pass.

Whether an evaluation recorded for one registration may answer for another
is an open policy. 'ReusePolicy' names the choices the model can state;
every function that needs an answer takes one, and none is a default.
-}
module Arc.Candidate.Evaluation
    ( Outcome(..)
    , EvaluationRecord(..)
    , ReviewKind(..)
    , ReviewRecord(..)
    , ReusePolicy(..)
    ) where

import Arc.Candidate.Identifiers
import Arc.Model.Identifiers ( ActorId, DeclarationId, EnvironmentId, GateName, TreeId )
import Arc.Model.Observed ( Observed )


data Outcome = Passed
             | Failed
  deriving stock (Eq, Ord, Show)

-- | One gate execution on one registration's content, as observed.
data EvaluationRecord = EvaluationRecord
  { evaluationId :: !EvaluationId
  , candidate    :: !CandidateId
  , tree         :: !TreeId
  , gate         :: !GateName
  , declaration  :: !DeclarationId
  , environment  :: !(Observed EnvironmentId)
  , outcome      :: !(Observed Outcome)
  , evaluator    :: !ActorId
  }
  deriving stock (Eq, Ord, Show)

data ReviewKind = Approves
                | RequestsChanges
  deriving stock (Eq, Ord, Show)

-- | A review of one registration's content at one tree. Review authority
-- belongs to the registration it names and never to its tree.
data ReviewRecord = ReviewRecord
  { reviewId  :: !ReviewId
  , candidate :: !CandidateId
  , tree      :: !TreeId
  , reviewer  :: !ActorId
  , kind      :: !ReviewKind
  }
  deriving stock (Eq, Ord, Show)

{- | The open policy for reusing an evaluation across registrations.

'ReuseNever': only an evaluation recorded for the chosen registration
answers for it. 'ReuseOnMatchingCoordinates': an evaluation recorded for
another registration answers when its tree, declaration, and recorded
environment all match the ones in force; an unrecorded environment matches
nothing.
-}
data ReusePolicy = ReuseNever
                 | ReuseOnMatchingCoordinates
  deriving stock (Eq, Ord, Show, Enum, Bounded)
