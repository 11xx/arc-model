# arc-model

`CONTRACT.md` and `REPORT.md` are the design authority. A question they leave
open stays open, recorded in `REPORT.md`.

## Invariants

- The model is a clean room. Its rules come from `CONTRACT.md` and arc's public
  documentation (the guide, `--help`, README) at the pinned comparison
  revision, never from arc's source (it shouldn't become a Rust translation, or
  it'll lose its oracle/model utility). Only the differential's encoding,
  `differential/`, reads arc's Rust.
- A brief for model work names no Rust file or line and never asks the model
  to agree with arc. A rule the contract does not settle is settled in
  `CONTRACT.md` first, from the documentation, or left unsettled with its
  readings.
- A mismatch, model against arc or model against `CONTRACT.md`, is classified
  and recorded in `REPORT.md`, never closed by editing either side to match.
  Neither side is the oracle for the other.
- The library is pure (no clock, filesystem, Git, or arc ledger) and depends
  on `base` and `containers` only.
- Every `arc` or `git` process for a scenario, replay, or reproduction runs in
  the sandbox, through the differential or `arc-model-sandbox`. Never build
  such an environment by hand, set `HOME` for one, or run
  `git config --global` outside it.
- Every test suite and executable imports the `heap-cap` stanza.
- Nothing here enters arc's build, gates, or releases.

Haskell presentation, records included, follows `~/code/haskell-style.md`.
