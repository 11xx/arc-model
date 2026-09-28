{- | The proposed candidate protocol: immutable registration, typed context
relations, evaluation applicability, explicit selection, and retention
roots.

This is a separate model from "Arc.Model". Nothing in arc implements it, so
it cannot be compared with an implementation; what it states is that the
rules are consistent, and which decisions remain open. The existing-
authorization model never imports it.
-}
module Arc.Candidate
    ( module Arc.Candidate.Basis
    , module Arc.Candidate.Context
    , module Arc.Candidate.Evaluation
    , module Arc.Candidate.Identifiers
    , module Arc.Candidate.Observations
    , module Arc.Candidate.Registration
    , module Arc.Candidate.Relation
    , module Arc.Candidate.Retention
    , module Arc.Candidate.Selection
    , module Arc.Candidate.State
    ) where

import Arc.Candidate.Basis
import Arc.Candidate.Context
import Arc.Candidate.Evaluation
import Arc.Candidate.Identifiers
import Arc.Candidate.Observations
import Arc.Candidate.Registration
import Arc.Candidate.Relation
import Arc.Candidate.Retention
import Arc.Candidate.Selection
import Arc.Candidate.State
