# arc-model

An independent, pure Haskell model of arc's authorization semantics: what a
recorded history permits, what it refuses, and which facts a decision rests
on, and a differential that replays the same histories through the arc
binary and compares its answer with the model's. The model is a
characterization of behaviour, not a translation of the Rust implementation,
and neither it nor the differential is part of the Rust build, its gates, or
its releases.

The model characterizes arc at `26f6bdc051b9464bbe3d0c7026c564b14464904a`.
A revision is pinned so a reader compares against a fixed implementation
rather than a moving branch; the constant is exported as `comparisonRevision`.

## What it models

- **Ledger replay.** Patchsets, verdicts, findings and dispositions, gate
  verifications, dirty-tree waivers, briefs and their probe runs, debt
  declarations, post-integration audits, claim episodes, holds, and
  integration records fold into an immutable state. Replay decides nothing.
- **The integration decision.** The observed head against the recorded
  patchset head, or its absence where the branch is gone; how the head
  merges with its target, and the exact evaluated tree (the merge when the
  change is behind it); contributor identity and reviewer independence, a
  recorded approval or a waiver bound to the exact patchset, an external
  decision about exactly this head, open blocking findings, holds,
  dependencies, a gate declaration with its evidence, and the acceptance
  probes of the patchset's brief. Gate declarations two policy layers
  disagree on leave nothing to decide against, and are refused alone.
- **Every ground, not the first.** `evaluate` answers with every ground on
  which the integration is refused, in the model's priority order, or with
  the basis it would rest on; `decide` is the first ground or the basis.
- **Four separate gate readings.** Pass/fail, coverage (which declaration,
  tree, and environment an observation answers), availability (whether a
  record exists and could be read), and demonstrated falsification are
  distinct fields. An omitted observation is `Omitted`: never false, never
  successful. A gate that declares an environment probe is answered only by
  evidence carrying the identity the probe yields where the decision is made,
  and a run on a dirty worktree answers only under a waiver naming its
  revision.
- **Acceptance probes.** A probe a brief declares is discharged by a
  failure at the brief's base and a pass at the head; a failure and a pass
  at one revision contradict each other rather than discharge it.
- **Decisions made outside arc.** An external approval of exactly this head
  authorizes where no independent review is owed and never over a local
  refusal; an external change request or rejection stands over any approval
  and is not waivable.
- **Structured refusals and a decision basis.** A permission names the exact
  events, patchset, tree, target, and policy it relied on. A refusal names the
  facts that stood in the way.
- **Permission is not effect.** `execute` re-checks the basis against the
  observations and produces a plan, and a store that does not hold
  integration authority cannot act at all; only `recordIntegration` puts the
  effect in the ledger.
- **Coverage obligations.** A debt declares a missing read; a waiver binds to
  exactly one patchset; a refusing verdict is not waivable. An independent
  negative audit can fulfil the read and leave its findings open: fulfilled is
  not approved. A later audit never rewrites what an integration rested on.

## What it deliberately does not model

Deferred, with the deferral recorded here rather than implied:

- the proposed candidate/evaluation/selection protocol — a separate model;
- Git effects: how a merged tree is synthesized, whether it conflicts, that a
  merge commit's tree is the evaluated one, and the reset that follows a
  mismatch are outside a pure model, which takes the head, the target, how
  they merge, and the evaluated tree as observations;
- operating-system durability, locking, race, and crash-recovery behaviour;
- forks, worktrees, retention, bundles, and the journal.

The full list, including the fields the model collapses, is in
[REPORT.md](REPORT.md#known-unsupported-semantics).

## Build and test

```sh
cabal v2-build --enable-tests
cabal v2-test spec --test-show-details=direct
cabal v2-run arc-model-differential -- --cases 200
```

The suite exits non-zero on any failed fixture, property, surviving mutant, or
unreached generator feature. Its library dependencies are `base` and
`containers`; the test suite adds `QuickCheck`. The package lives outside the
arc repository and is named by none of its gates, so no arc change needs a
Haskell toolchain to build. The differential needs `git` and an `arc` binary
on `PATH` (or `--arc PATH`); it is not one of this package's gates either,
because a gate that needs the implementation would make every change here
depend on the thing the model challenges.

## The differential

`arc-model-differential` builds each history in a repository and home of its
own under a scratch root in the temporary directory (`TMPDIR` when set),
records it through arc's own commands, asks `arc check --json`, and compares
the blockers with the model's grounds mapped onto arc's vocabulary (the
mapping is in `Differential.Compare`, and REPORT states it). Forty-two named
histories run first, then two generated families, so any row is
reproducible from its index: `generated-i` draws the fields the decision
rests on (`--cases`), and `check-time-i` draws the same fields from the same
seed and then the facts arc's check reports beside them — dirty evidence, a
target that moved, acceptance probes, a missing branch, conflicting gate
declarations (`--check-time-cases`). Each row is one of:

- `agreed` — the same blockers, or ready on both sides;
- `skipped` — a field the CLI cannot record, with the reason: unreadable
  evidence, evidence at another tree on a one-patchset history, a finding
  without a verdict, dirt on a run against the merge;
- `adjudicated` — a classified disagreement, with its class and reason;
- `DISAGREED` — a disagreement nobody has classified;
- `REPLAY FAILED` — an arc command the plan did not expect to be refused.

The run exits non-zero on the last two and on nothing else. `--mutant NAME`
expects a permission wherever that deliberate fault permits, so the run
objects exactly where the fault would let arc's refusal through; it is how a
reader checks that the comparison can fail at all. `--keep` leaves every
sandbox on disk, `--verbose` prints each arc command, `--seed`, `--cases`,
and `--check-time-cases` select the histories.

A quiet run is supporting evidence, not proof of equivalence: it says every
replayed history agreed, over the fields the CLI can express.

## Deterministic seeds and replay

The run is deterministic from one seed. Defaults: seed `20260907`, 300 cases
per property. Property `n` derives seed `seed + n * 13`; mutant checks use
`1000 + index * 31` and `2000 + index * 31`; the coverage sampler uses
`seed + index`.

```sh
cabal v2-test spec --test-show-details=direct --test-options="--seed 20260907 --tests 300"
```

A failure prints the shrunk counterexample and the replay line. Re-running the
same command with the same seed and test count reproduces every case; a
different seed is a different sample, not a different suite. Shrinking is
structural: a candidate that would leave a debt reference dangling is filtered
out, so a counterexample always retains the references its events need.

## Fixture format

A fixture is a Haskell `Scenario` interpreted by `build` into a ledger plus
observations. Fields (`Scenario`):

| field | meaning |
| --- | --- |
| `patchsets` | number of patchsets, `rev1..revN` / `tree1..treeN` |
| `verdictOnFirst` | bind the verdict to `ps-01` rather than the latest |
| `reviewer` | `Nothing`, or `ActorIndependent`, `ActorContributor`, `ActorAssumed` |
| `verdict` | `Approved`, `ChangesRequested`, `CommentOnly` |
| `provisional` | record the approval as provisional |
| `extraContributor` | add a third contributor to every patchset |
| `externalVerdict` | `Nothing`, or an `ExternalApproved`, `ExternalChangesRequested`, or `ExternalRejected` decision about the latest head |
| `debt` | `(patchset index, declared kind)` or `Nothing` |
| `gateMode` | `EvidenceCovered`, `EvidenceFailing`, `EvidenceOtherTree`, `EvidenceShapeMoved`, `EvidenceOtherEnvironment`, `EvidenceUnrecordedEnvironment`, `EvidenceProbeFailed`, `EvidenceRecordUnreadable`, `EvidenceOmitted` |
| `blockingFinding` / `resolveFinding` | record an open or resolved blocking finding |
| `headMoved` | the observed head is not the patchset head |
| `policy` | `dangerPolicy`, `openPolicy`, or `requireDeclaredPolicy` |
| `targetAfter` / `policyAfter` | the execution observation moves the target or policy |
| `authorityWithheld` | the store lacks integration authority when it executes |
| `audit` | `(verdict, independent)` recorded after integration |
| `episodeExpired` | record a claim and expire it |
| `worktree` | `WorktreeClean`, `WorktreeDirty`, `WorktreeDirtyWaived` (a waiver at the evidence's revision), or `WorktreeDirtyWaivedElsewhere` (a waiver at the change's base) |
| `targetMode` | `TargetContained`, `TargetBehind` (the gate ran at the head only), `TargetBehindEvaluated` (the gate ran against the merge), or `TargetConflicting` |
| `probe` | `ProbeNone`, or a brief declaring one probe: `ProbeDischarged`, `ProbeBaselinePassed`, `ProbeFinalMissing`, `ProbeFinalFailed`, `ProbeUndischargeable` (based at the head) |
| `branchMissing` | the change's branch is gone when the decision is asked |
| `conflictingGates` | a second policy layer declares the required gate differently |

`mutations scenario` returns the one-invalidating-transition set: gate
omitted/failed/elsewhere/shape-moved/other-environment/environment-unrecorded/
probe-failed/unreadable, head moved, target moved, policy moved, authority
withheld, external verdict refused, finding opened, verdict refused, review
bound to a stale patchset, reviewer made a contributor, waiver expired,
evidence dirty, merge unevaluated, target conflicting, probe baseline
passed, branch missing, and gates conflicting. `featureOf` classifies a
built scenario so the coverage sampler can prove each required class was
reached. `genDecisionScenario` draws the fields the decision rests on with
every check-time field at its default; `genAnyScenario` draws the same
fields from the same seed and then the check-time ones, so extending a
history never changes the rest of it.

## Layout

```
src/Arc/Model/Identifiers.hs         distinct identifier types
src/Arc/Model/Observed.hs            Observed, and the newest of a recording-ordered list
src/Arc/Model/Declaration.hs         gate declarations and the vocabulary of one run
src/Arc/Model/Gate.hs                the four readings of a required gate, and what makes it green
src/Arc/Model/Probe.hs               whether a brief's acceptance probes are discharged at the head
src/Arc/Model/Policy.hs              the declared integration policy
src/Arc/Model/Observations.hs        everything the model is told at decision time
src/Arc/Model/Ledger/*.hs            one module per ledger record: patchset, verdict, external
                                     verdict, finding, disposition, verification, dirty-tree
                                     waiver, brief, probe run, debt, audit, claim, integration
src/Arc/Model/Ledger.hs              the event sum over those records
src/Arc/Model/State.hs               replay and the derived queries
src/Arc/Model/Basis.hs               decision bases, structured refusals
src/Arc/Model/Decision.hs            evaluate, decide, execute, recordIntegration
src/Arc/Model/Coverage.hs            debt kinds, review obligation, coverage projection
src/Arc/Model/Discharge.hs           post-integration audit gating and discharges
scenarios/Scenario.hs                the scenario plan, the named histories, generators and shrinking
scenarios/Generators.hs              building a scenario, mutations, features
scenarios/Mutants.hs                 the eighteen deliberate faults
test/Fixtures.hs                     unit fixtures
test/Render.hs                       the check harness
test/Main.hs                         spec driver: fixtures, properties, mutants, coverage
differential/Differential/Plan.hs    a scenario as arc commands, or the reason it has none
differential/Differential/Arc.hs     running a plan against the arc binary in a sandbox
differential/Differential/Compare.hs the grounds-to-blockers mapping and adjudication
differential/Main.hs                 the differential driver
```

Every record carries bare field names read with dot syntax, and a record that
is ever updated owns its module so an update can name it
(`verdict { Verdict.actor = who }`); `AGENTS.md` names the dialect.

[REPORT.md](REPORT.md) separates what the types enforce, what the runtime
checks, and what the model leaves unsettled.
