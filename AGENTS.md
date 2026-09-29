# arc-model

An independent semantic model of arc's integration authorization, and the
oracle that compares it with the arc binary. See `README.md` for what it
models and how to run it.

## Design authority

The settled design is what `README.md` and `REPORT.md` state. A question
those two leave open is open, and `REPORT.md` records it among its unsettled
design and open decisions.

## Invariants

The model characterizes one arc revision, named by `comparisonRevision`. It
describes behaviour; it is not a port of arc's implementation.

The model is derived independently of the Rust:

- Model-side work — `src/`, `candidate/`, `scenarios/`, `test/`,
  `candidate-test/` — derives its rules from `CONTRACT.md` and arc's public
  documentation (its README, `docs/`, the guide `arc` prints, and each
  command's `--help`), never from arc's source.
- Only the differential's encoding, `differential/`, reads arc's behaviour,
  and arc's Rust source is read only there.
- A task on the model names no Rust file or line, and never requires the
  model to agree with arc. A rule the contract does not settle is settled in
  `CONTRACT.md` first, from the documentation, or left unsettled with its
  readings.

The library is pure. It never reads the clock, the filesystem, Git, or an arc
ledger. Only the differential executable runs `arc`, and it runs the binary
already on `PATH` in a temporary repository of its own.

Every process that runs `arc` or `git` for a scenario, a replay, or the
reproduction of a disagreement runs inside `Differential.Sandbox`: through
the differential, or by hand through
`cabal v2-run arc-model-sandbox -- [--keep] <command> [args…]`. The sandbox
builds its environment from nothing and refuses to run anything until its
self-check passes. Nobody builds a sandbox environment by hand, sets `HOME`
for one, or runs `git config --global` outside it.

A mismatch between the model and arc is classified — a Rust defect, a model
defect, or an unsettled contract — never made to disappear. Neither side is
the oracle for the other. A mismatch between the model and `CONTRACT.md` is
recorded in `REPORT.md` and adjudicated the same way, not closed by editing
either side to match.

Nothing here enters the arc build, its gates, or its releases, so no arc
change needs a Haskell toolchain.

## Toolchain

ghcup, GHC 9.12.x, GHC2024, cabal, `-Wall` as errors — incomplete patterns
included, since a non-exhaustive match over a refusal is a dropped ground
rather than a lint nit. The library depends on `base` and `containers` only.

Code presentation, including the record dialect, follows
`~/code/haskell-style.md`.
