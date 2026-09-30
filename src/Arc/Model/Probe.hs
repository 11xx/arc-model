{- | Reading the acceptance probes a patchset's brief declares.

A probe is discharged at the head when a failure is recorded at the brief's
base and a pass at the head. A brief whose base is the head, or that names
no base, cannot discharge a probe. The newest run for each phase at its
required revision decides, and both runs must name the brief and probe.
-}
module Arc.Model.Probe
    ( ProbeRefusal(..)
    , probeRefusalText
    , probeRefusals
    ) where

import Arc.Model.Declaration ( GateResult(..) )
import Arc.Model.Identifiers
import Arc.Model.Ledger.Brief ( Brief )
import Arc.Model.Ledger.Brief qualified as Brief
import Arc.Model.Ledger.Patchset ( Patchset )
import Arc.Model.Ledger.Patchset qualified as Patchset
import Arc.Model.Ledger.ProbeRun ( ProbePhase(..) )
import Arc.Model.Ledger.ProbeRun qualified as ProbeRun
import Arc.Model.Observed
import Arc.Model.State

import Data.Maybe ( mapMaybe )


-- | Why a declared probe is not discharged at the head.
data ProbeRefusal = ProbeCannotDischarge ProbeName
                  | ProbeNotDiscriminating ProbeName (Observed GateResult) (Observed GateResult)  -- ^ The baseline result, then the final one.
  deriving stock (Eq, Ord, Show)

probeRefusalText :: ProbeRefusal -> String
probeRefusalText = \case
  ProbeCannotDischarge (ProbeName name)
    -> "probe " <> name <> " has no base to fail at apart from the head"
  ProbeNotDiscriminating (ProbeName name) baseline final
    -> "probe " <> name <> " did not fail at the base and pass at the head (baseline "
    <> reading baseline <> ", final " <> reading final <> ")"
  where
    reading = \case
      Omitted           -> "not run"
      Observed GatePass -> "pass"
      Observed GateFail -> "fail"

-- C17
-- | Every probe of the patchset's brief that is not discharged at the
-- patchset's head, in the order the brief declares them.
probeRefusals :: ChangeState -> Patchset -> [ProbeRefusal]
probeRefusals state patchset = maybe [] refusalsOf (briefOf state patchset)
  where
    refusalsOf :: Brief -> [ProbeRefusal]
    refusalsOf brief = mapMaybe (refusal brief) brief.probes
    refusal brief name = case brief.base of
      Just base
        | base /= patchset.revision -> case (resultAt Baseline base, resultAt Final patchset.revision) of
            (Observed GateFail, Observed GatePass) -> Nothing
            (baseline, final)                      -> Just (ProbeNotDiscriminating name baseline final)
      _undischargeable -> Just (ProbeCannotDischarge name)
      where
        resultAt phase revision = maybe Omitted (Observed . (.result)) (newestProbeRun state brief.event name phase revision)
