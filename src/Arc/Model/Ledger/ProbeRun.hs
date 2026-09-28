{- | One recorded run of an acceptance probe.

A run belongs to the brief that declared the probe and to a phase: the
baseline, run at the brief's base, or the final run at the head.
-}
module Arc.Model.Ledger.ProbeRun
    ( ProbePhase(..)
    , ProbeRun(..)
    ) where

import Arc.Model.Declaration ( GateResult )
import Arc.Model.Identifiers


data ProbePhase = Baseline
                | Final
  deriving stock (Eq, Ord, Show)

data ProbeRun = ProbeRun
  { event    :: !EventId
  , brief    :: !EventId     -- ^ The brief that declared the probe.
  , probe    :: !ProbeName
  , phase    :: !ProbePhase
  , revision :: !Revision    -- ^ The head the run was recorded at.
  , result   :: !GateResult
  }
  deriving stock (Eq, Ord, Show)
