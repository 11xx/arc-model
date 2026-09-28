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
  not approved. A later audit never rewrites what an integration rested on,
  and a contributor's approving audit is not recorded where policy forbids
  self-approval.

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

The suite exits non-zero on any failed fixture, comparator check, property,
surviving mutant, or unreached generator feature. Its library dependencies
are `base` and `containers`; the test suite adds `QuickCheck`, and compiles
the differential's plan, driver, and comparator modules with their
dependencies so the comparator is checked without running arc. The package lives outside the
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
declarations (`--check-time-cases`).

A run compares one channel, named by `--channel` and on its summary line:

- `decision` (the default) — `refusals` against `arc check --json`;
- `execution` — `execute` against `arc integrate --dry-run`, after the moves a
  scenario makes between the decision and the integration: a commit on the
  target, an edit to the policy file the worktree reads, and integration
  authority offered to a paired replica. Six histories named for those moves
  run after the others on this channel;
- `coverage` — `historicalAuthorization` and `coverageAfterIntegration`
  against what `arc show --json`, `arc findings --audit`, and `arc query
  --debt` report after the same moves, a real `arc integrate`, and the
  scenario's `arc audit`. Eleven histories named for integrations and audits run
  after the others on this channel.

Each row is one of:

- `agreed` — the same blockers, or ready on both sides;
- `skipped` — a field the CLI cannot record, with the reason: unreadable
  evidence, evidence at another tree on a one-patchset history, a finding
  without a verdict, dirt on a run against the merge;
- `adjudicated` — a classified disagreement, with its class and reason;
- `DISAGREED` — a disagreement nobody has classified;
- `REPLAY FAILED` — an arc command the plan did not expect to be refused.

The run exits non-zero on the last two and on nothing else. `--mutant NAME`
names a fault of the channel compared and expects a permission wherever
that fault permits, so the run objects exactly where the fault would let
arc's refusal through; it is how a reader checks that the comparison can
fail at all. `--keep` leaves every sandbox on disk, `--verbose` prints each
arc command, `--seed`, `--cases`, and `--check-time-cases` select the
histories.

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
test/Comparator.hs                   the differential's adjudication rules, pinned to their exact answers
test/Render.hs                       the check harness
test/Main.hs                         spec driver: fixtures, comparator, properties, mutants, coverage
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

## The proposed candidate protocol

A second, separate model states the proposed semantics of candidate
registration, typed context relations, evaluation applicability, explicit
selection, and retention roots. Nothing in arc implements it, so there is
nothing to compare it with: what it shows is that the stated rules are
consistent, that its tests object to the named faults, and which decisions
remain open. It is the cabal component `arc-model:candidate`
(`Arc.Candidate.*`), which depends on the main library for identifiers and
`Observed` and nothing else; the main library cannot import it without a
dependency cycle cabal refuses.

### What it states

- **Registration is immutable.** A registration names its content tree, an
  immutable brief reference, its producers, its parents, and the episodes it
  cites. It names no change. A second registration of one identity is
  refused, so no later event alters one. Two registrations of one tree share
  storage and nothing else: no review, contributor set, brief, or selection
  authority.
- **Episodes and candidates are many-to-many.** An episode may produce none,
  one, or several candidates; a candidate may cite several episodes.
- **Relations are typed by who establishes them.** An observed read comes
  only from a tool's record with the coverage it recorded; a supply is the
  operation's record and no read; citing, relying on, and considering are
  attributed claims; an inference names its source. A declaration's citation
  must resolve to a recorded read or the declaration is refused.
- **References carry what was observed.** A context reference names a locator
  (a journal and complete artifact filename, or a repository, content
  identity, and path) and the version and coverage actually observed. It
  resolves through its version, so an amended artifact still resolves to the
  text that was read.
- **Evaluation consumes observations.** An evaluation record carries the
  outcome and environment the shell observed; the model runs nothing. An
  omitted outcome, environment, target, or coverage is unknown, never a pass.
- **Selection is explicit.** `evaluate` validates a named proposal — the
  chosen registration, destination, target, the evaluations and review relied
  on, the selector, and any repairs — and answers with every ground against
  it or the basis it rests on. It never chooses and never writes. A repair's
  author joins the contributors, so a lead who repairs is not the independent
  reviewer of what ships. `promote` re-checks the target; only an observed
  effect is recorded as a promotion.
- **Retention follows references.** Selections, promotions, and declared roots
  retain what they reach, and collecting it is refused. Episode expiry ends
  liveness and nothing else. A reached reference is at risk unless its
  provider reported it pinned.
- **Declarations do not decay into observations.** A declared reliance, a
  supply, or an inference is reported for what it is and never meets a read
  requirement.

### What it deliberately does not state

The open decisions of the owning design are parameters or unsupported cases,
never defaults. Evaluation reuse across registrations is an argument to
`evaluate` (`ReuseNever` or `ReuseOnMatchingCoordinates`) with no default;
a provider's durable-capture guarantee is an observation per referenced
version. Retention budgets for unreferenced history, canonical manifest
encoding, initial trace-mapping scope, and the production core language have
no representation: content no root reaches is reported as `NoRootReaches`,
which is not a permission to collect it. Who may select is not stated either;
the selector is recorded and constrained by nothing. The details are in
[REPORT.md](REPORT.md#the-proposed-candidate-protocol).

### Build and test

```sh
cabal v2-build --enable-tests
cabal v2-test candidate-spec --test-show-details=direct --test-options="--seed 20260907 --tests 300"
cabal v2-test --test-show-details=direct
```

The last runs both suites and is the package's test gate. The candidate
suite uses the spec suite's seed scheme: property `n` derives `seed + n *
13`, mutant checks `1000 + index * 31` and `2000 + index * 31`, the coverage
sampler `seed + index` over 4000 plans. It exits non-zero on any failed
fixture, property, surviving mutant, or unreached plan class.

A fixture is a `Plan` (`candidate-test/Plan.hs`) interpreted by `build` into
a ledger of two registrations under one brief, their episodes, the context
the chosen one read or only claimed, one evaluation, and one review, then
decided under the plan's reuse policy. Every field is a fixed coordinate, so
shrinking never leaves a reference dangling.

```
candidate/Arc/Candidate/Identifiers.hs   identifiers the protocol adds
candidate/Arc/Candidate/Context.hs       locators, observed versions and coverage, resolution
candidate/Arc/Candidate/Registration.hs  the immutable registration
candidate/Arc/Candidate/Relation.hs      supplies, reads, declarations, inferences, judgements
candidate/Arc/Candidate/Evaluation.hs    evaluation and review records, the reuse policy
candidate/Arc/Candidate/Observations.hs  what the model is told at decision time
candidate/Arc/Candidate/Basis.hs         proposals, requirements, bases, refusals
candidate/Arc/Candidate/State.hs         checked writes, replay, relation projection
candidate/Arc/Candidate/Selection.hs     evaluate, refusals, promote
candidate/Arc/Candidate/Retention.hs     roots, reachability, collection, capture risk
candidate-test/Plan.hs                   the plan, its generator, shrinking, and features
candidate-test/Mutants.hs                the seven deliberate faults
candidate-test/Fixtures.hs               unit fixtures
candidate-test/Main.hs                   the candidate spec driver
```
