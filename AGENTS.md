# arc-model

An independent semantic model of arc's integration authorization, and the
oracle that compares it with the arc binary. See `README.md` for what it
models and how to run it.

## Design authority

The design lives in the arc project journal, not in this repository:
`arc catchup` in the arc checkout for live state, and the feature request
`haskell-semantic-model-and-oracle` with its owning discussion
`agent-native-vcs` for the argument. A question that looks open is usually
settled there.

## Invariants

The model characterizes one arc revision, named by `comparisonRevision`. It
describes behaviour; it is not a port of `state.rs` or `status.rs`, and a
reader who compares it against the Rust source is checking the model, not
translating it.

The library is pure. It never reads the clock, the filesystem, Git, or an arc
ledger. Only the differential executable runs `arc`, and it runs the binary
already on `PATH` in a temporary repository of its own.

A mismatch between the model and arc is classified — a Rust defect, a model
defect, or an unsettled contract — never made to disappear. Neither side is
the oracle for the other.

Nothing here enters the arc build, its gates, or its releases, so no arc
change needs a Haskell toolchain.

## Toolchain

ghcup, GHC 9.12.x, GHC2024, cabal, `-Wall` as errors — incomplete patterns
included, since a non-exhaustive match over a refusal is a dropped ground
rather than a lint nit. The library depends on `base` and `containers` only.

Code presentation follows `~/code/haskell-style.md`.
