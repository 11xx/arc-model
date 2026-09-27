{- | An independent semantic model of arc's authorization.

This package characterizes the semantics of an existing arc revision. It
is not a port of the Rust implementation, and it is not a production
dependency: nothing in the Rust build or its gates reads it.

The proposed candidate\/evaluation\/selection protocol is out of scope.
The single-slot waiver query this model reproduces and a multi-obligation
representation are different semantics, and this package does not claim
differential compatibility with either.
-}
module Arc.Model
    ( module Arc.Model.Identifiers
    , module Arc.Model.Observed
    , module Arc.Model.Declaration
    , module Arc.Model.Gate
    , module Arc.Model.Policy
    , module Arc.Model.Observations
    , module Arc.Model.Ledger
    , module Arc.Model.State
    , module Arc.Model.Basis
    , module Arc.Model.Decision
    , module Arc.Model.Coverage
    , module Arc.Model.Discharge
    , comparisonRevision
    ) where

import Arc.Model.Basis
import Arc.Model.Coverage
import Arc.Model.Decision
import Arc.Model.Declaration
import Arc.Model.Discharge
import Arc.Model.Gate
import Arc.Model.Identifiers
import Arc.Model.Ledger
import Arc.Model.Observations
import Arc.Model.Observed
import Arc.Model.Policy
import Arc.Model.State


{- | The arc revision whose authorization semantics this model
characterizes. The model describes behaviour, not a commit graph: a
revision is pinned so a reader can compare against a fixed implementation
rather than a moving branch.
-}
comparisonRevision :: String
comparisonRevision = "26f6bdc051b9464bbe3d0c7026c564b14464904a"
