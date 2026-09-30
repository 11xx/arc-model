# arc-model

An independent model of arc's authorization rules, checked against the arc binary.

[arc](https://github.com/11xx/arc) decides whether a change may integrate. It
checks for an approval bound to the exact patchset, independent review where
policy asks for it, required gates green at the exact tree, and no open finding
or hold. A wrong answer here merges unreviewed or failing work, and a test
suite written beside the implementation shares its blind spots.

arc-model states the rules on their own terms. [`CONTRACT.md`](CONTRACT.md)
writes them as numbered clauses, each taken from arc's own documentation — the
guide `arc` prints with no arguments and each command's `--help` — or decided
by the contract where that documentation is silent, and marked settled or
unsettled. A pure Haskell model, written without reference to arc's source,
implements those clauses. A differential then generates histories, replays
each one through the arc binary, and compares the answers.

No disagreement is repaired before it is classified: as a defect in arc, a
defect in the model, a question the contract leaves open, a difference in
encoding, or arc having changed since the revision the contract pins.
[`REPORT.md`](REPORT.md) records each one. The model has found a defect in arc
this way, since fixed: a newer gate run recorded under a different environment
hid an older pass at the same tree, so arc refused a change the contract
accepts.

The package also models the candidate protocol — alternative answers to one
brief, registered, evaluated, selected, and promoted — and the differential's
candidate channel compares it with `arc candidate`.

## Build

Needs cabal and GHC 9.12.2, which `cabal.project` pins.

```sh
cabal v2-build --enable-tests
cabal v2-test --test-show-details=direct
```

## Run the differential

The differential needs `git` and an `arc` binary on `PATH`:

```sh
cargo install --git https://github.com/11xx/arc --locked
cabal v2-run arc-model-differential -- --cases 200           # arc check against the model's refusals
cabal v2-run arc-model-differential -- --channel execution   # arc integrate --dry-run against execute
cabal v2-run arc-model-differential -- --channel coverage    # a real integration: authorization and audit coverage
cabal v2-run arc-model-differential -- --channel candidate   # arc candidate select, promote, and retire against the candidate model
```

Each history agrees, is skipped with a reason, or is a disagreement with its
class. A run fails only on a disagreement nobody has classified or a history
that failed to replay. The seed defaults to 20260907, so every run draws the
same histories; `--seed N` draws different ones, and `--arc PATH` replays them
against another binary.

The differential never touches your Git configuration or arc store. Every
process it starts gets an environment built from nothing, with its home,
configuration and temporary directories inside one scratch root.
`cabal v2-run arc-model-sandbox -- <command>` runs any other command in the
same environment, for replaying a recorded disagreement by hand.

## License

[Unlicense](UNLICENSE) — public domain.
