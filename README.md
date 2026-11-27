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
[`REPORT.md`](REPORT.md) records each one. Historical results cite each original
revision beside its rewritten id; a rewritten id names the same tree in a signed commit.
The model has found a defect in arc this way, since fixed: a newer gate run
recorded under a different environment
hid an older pass at the same tree, so arc refused a change the contract
accepts.

The comparison's captured guide, command help, executable identities, and
text differences are retained under [`evidence/repin`](evidence/repin).
Write execution requires an established actor and honors declared-actor
requirements from both the invoking checkout and the integration target;
readiness checks remain readable without an actor.
Execution computes readiness from the current history and observations; an
earlier refusal or permission does not constrain it. The execution channel
compares the dry run's JSON plan, including replay-relative revisions,
selected approval and gate evidence, declarations, policy and danger scope.
Authorship comes from the ledger, never from commit trailers: a reviewing
model counts as a second identity beside the actor, and a read under the
model the ledger records for the implementer is not independent of the work.
A debt
declared as `ineligible-review` is cleared only by an audit, or a verdict on
the shipped patchset, whose own routing assessment is eligible, bound to its
reader and covering the `Implemented-by` projection of the shipped range, and
a debt stands as declared, owed, discharged, or retired (when a guarded
integration ships a later patchset under an independent, non-denied approval).

Gate declarations select integration, publication or both. A project's write
confinement (layered from destination, operator, and change head for open
changes), optional `invariants` file, and validated gate trailers (`Witness:`,
`Change-size: interface`) are part of each gate's declaration identity, so a
pass under another confinement, invariant list, or trailer set does not answer
it. Evidence keeps its event, so a publication pass cannot authorize
integration. `Arc.Model.Budget` models bounded store-local gate budget
suspensions (up to 24h, integration-only, never lifting failures, declaration
errors, unmeasured runs, or publication, and excluding suspended runs from
work references, raise evidence, and base-pass seeds) and `[budget]`
enforcement keys. Delta selectors can offer reuse only from matching green
source evidence, with complete known selections and retained provenance.
`publicationEvidence` answers the local publication tier without requiring a
change or a review verdict. Selector execution, publication receipts, timing
measurement, and build preparation remain external effects.

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

To compare two builds case by case, add a baseline:

```sh
cabal v2-run arc-model-differential -- --arc "$ARC_BUILD" --baseline-arc "$BASELINE_BUILD" --channel execution
```

Both builds receive the same named and seeded cases in isolated sibling
sandboxes under one run directory. Replay-created identifiers are compared
through their symbolic coordinates. Each row reports whether the builds
agree and each build's separate classification against the model. In baseline
mode, equal observed answers pass even when both disagree with the model;
a difference between builds or a replay failure exits non-zero. Baselines
work on all four channels. `--help` and `-h` print the command guide.

The differential never touches your Git configuration or arc store. Every
process it starts gets an environment built from nothing, with its home,
configuration and temporary directories inside one scratch root.
`cabal v2-run arc-model-sandbox -- <command>` runs any other command in the
same environment, for replaying a recorded disagreement by hand.

## License

[Unlicense](UNLICENSE) — public domain.
