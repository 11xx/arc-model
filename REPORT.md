# arc-model report

What the types enforce, what the runtime checks, and what the model leaves
unsettled. The suite that produces the evidence below is run with:

```sh
cabal v2-test spec --test-show-details=direct --test-options="--seed 20260907 --tests 300"
```

## Structural type invariants

These hold by construction; no test can observe them violated, and no
counterexample can be generated for them.

- **Distinct identifiers.** `ChangeId`, `PatchsetId`, `Revision`, `TreeId`,
  `ActorId`, `GateName`, `DeclarationId`, `EventId`, `FindingId`, `DebtId`,
  `ClaimId`, `HoldId`, `FailureLabel`, `ProbeCommand`, `EnvironmentId`, and
  `ProbeName` are separate types. A revision cannot be compared with a tree, a patchset cannot
  be passed where an event is wanted, and an environment identity cannot be
  mistaken for the probe that yields it.
- **Observation is total.** `Observed a = Omitted | Observed a`. There is no
  default, no `Bool`, and no exception path from a missing observation to a
  result: a gate reading can be `Omitted` in every one of its four fields, and
  a probe that yields nothing where the decision is made is `Omitted`, never
  an identity. The observed head is `Observed` too: a change whose branch is
  gone has no head, not a head nobody compares.
- **Four gate readings are four fields.** `GateReading` carries the result,
  the coverage (`Covered` / `NeverEvaluated` / `EvaluatedOtherTree` /
  `DeclarationMoved` / `EvaluatedOtherEnvironment` / `EnvironmentUnrecorded`
  / `EnvironmentUnobserved` / `EvaluatedDirtyTree` / `WorktreeUnrecorded`),
  the availability (`NotProduced` / `Recorded
  execution` / `EvidenceUnreadable`), and the demonstrated falsification
  separately. `gateGreen` reads coverage first, so a pass recorded elsewhere —
  another tree, another declaration, another environment — cannot stand in
  for the ones in force.
- **A basis exists exactly when no ground stands.** `evaluate :: Observations
  -> ChangeState -> Either (NonEmpty Refusal) DecisionBasis`: the left side
  is never empty, the right side exists only when the list would be, and
  `decide` and `refusals` are projections of one value rather than two
  readings that could disagree.
- **A refusal is structured.** `Refusal` is a sum whose payloads are the
  facts that stood in the way; `Refusal` has no free-text constructor, and
  `refusalText` is a rendering, not the carrier.
- **A permission carries its basis.** `Decision = Permitted DecisionBasis |
  Refused Refusal`. `DecisionBasis` names the patchset, head, tree, target,
  policy, authorization, one covered evaluation per required gate, each
  prerequisite's closure, and the finding and hold vectors that had to be
  empty.
- **Permission and effect are different values.** `execute :: Observations ->
  ChangeState -> Decision -> Either Refusal ExecutionPlan` checks the store's
  authority to act, computes readiness again, and rebuilds the basis, and
  plans only where it equals the recorded one; `recordIntegration` is the only function
  that appends an `IntegrationRecord`. A `Decision` alone cannot record
  anything.
- **Authorization is a four-way sum.** `AuthorizedByVerdict`,
  `AuthorizedByWaiver`, `AuthorizedByVerdictUnderWaiver`, and
  `AuthorizedByExternalVerdict` are distinct, so "a waiver authorized this"
  cannot be confused with "a waiver was recorded", and a decision arc
  witnessed cannot be confused with one it was told about.
- **Obligation, outcome, and history are separate types.**
  `CoverageAfterIntegration` carries `read`, `verdict`, `approved`,
  `openFindings`, and `authorization` independently.
  `historicalAuthorization` is a projection of the newest
  `IntegrationRecord`; no function writes over a recorded basis.
- **Reference integrity under shrinking.** A scenario's references are
  positional; `shrinkScenario` filters out any candidate whose debt reference
  would exceed its patchset count, so every counterexample carries the
  references its events need.
- **The waiver query is single-slot.** All debt declarations are retained as
  ledger facts, while `newestWaiver` reads exactly one — the newest bound to
  the latest patchset — which is the semantics of the production reducer.

## Runtime validation

### Unit fixtures

`test/Fixtures.hs` pins the exact answer for each required case:

| fixture | what it anchors |
| --- | --- |
| `waiver-expiry` | a debt waives `ps-01` and not `ps-02` |
| `debt-beside-refusal` | a changes-requested verdict with an open finding is not permitted; the debt is in no basis; the refusal stands without the finding |
| `under-debt` | integration under a waiver, then a negative audit: the read is fulfilled, the findings stay open, the basis is untouched, fulfilled is not approved |
| `debt-kind` | nothing read, contributor-only verdicts, and an approval followed by an unread patchset each derive their kind; a declared kind wins; a comment followed by an unread patchset owes independent review |
| `repair-review` | an approved first patchset plus an unread repair is a stale approval and an `OwedReview RepairUnread` |
| `unknown` / `elsewhere` / `changed` / `unreadable` / `failed` | omitted, other-tree, shape-moved, unreadable, and failing gate evidence each produce their own reading and refusal |
| `environment` | evidence from another environment, evidence recording none, and a probe that fails here are each their own coverage and refusal; a gate without a probe takes evidence from anywhere |
| `falsified` | any passing run under the key that names a failure makes the gate discriminating; a failing run's label and a pass at another tree do not |
| `keyed` | a newer run at another tree, under another declaration, or in another environment neither answers nor hides the pass at the evaluated tree; an earlier revision with the same tree answers; with nothing under the key, the newest record says why |
| `equal-tree` | equal trees with different contributor and obligation scopes decide differently; a waiver rescues the contributor; an unused debt is not named |
| `external` | an external approval authorizes where no independent review is owed and is refused as `no-approval` where one is; beside a local approval the witnessed verdict is named; a change request stands over a local approval and over a waiver; a local refusal stands over an external approval; a rejection stands; an external approval is no independent read |
| `episode` | an expired claim ends liveness, not the retained debt and evidence; the waiver still applies |
| `debt-unused` | a debt recorded beside an approval that stood anyway authorized nothing |
| `stale` / `target-moved` / `policy-moved` | a moved head refuses; a target or policy that moves between decision and execution stands the action down, and a moved target names the new merge as a moved tree and the readiness it refuses |
| `rebuilt` | a finding, a hold, a refusing verdict, a failing run, or a newer pass recorded after the decision stands the execution down; an unchanged history plans and records nothing |
| `authority` | a check does not consult replica authority: the decision permits and the execution stands down |
| `prerequisites` | a permission and the integration it records name each prerequisite's closure; an open prerequisite refuses |
| `undeclared-actor` | under `require_declared_actor` a check does not refuse an undeclared invoker; execution refuses it, and a declared one executes |
| `every-ground` | a history refused on an open finding and a failing gate reports both grounds, in the model's presentation order; the decision is the first |
| `permission-not-effect` | permission alone records no integration; recording lands the basis |
| `audit` | an open change refuses an audit; an approving audit needs a declared independent identity; a negative audit is open to anyone; a contributor's approving audit is not recorded where self-approval is forbidden, and is recorded elsewhere |
| `provisional` | a provisional approval gates like any other |
| `dirty` | a run on a dirty worktree is not coverage and its result stands beside it; a waiver at its revision counts it, one at another revision does not; a run recording nothing about its worktree is refused; attested evidence carries no worktree |
| `merged-tree` / `needs-rebase` | a merge nobody ran a gate on is refused beside the gate; an evaluated merge permits on the merge's tree; a head that does not merge owes a rebase and nothing else |
| `probes` | a discharged probe permits; a pass at the base, a missing or failing final run, and a base that is the head are each their own probe refusal |
| `branch-missing` | a missing branch refuses without a moved head beside it, and refuses execution |
| `conflicting-gates` | declarations two layers disagree on are the only ground, over a finding and a failing gate |
| `question-a` | an older pass at tree A and a newer failing run at tree B, evaluated at A (a latest patchset that reverts to A): the basis names the pass at A (C14) |
| `question-b` | two waivers for different patchsets: each applies to its own patchset, and the latest one's authorizes (C7) |
| `question-c` | an iterating change with no approval is refused as iterating; whether the missing approval stands beside it is C11's open reading, and is not asserted |
| `demonstration` | the model refuses a contributor reviewer; the deliberate fault permits |

### Comparator checks

`test/Comparator.hs` pins every adjudication rule of the differential
(policy motion, external beside local, and the undeclared reviewer on the
coverage channel; policy motion and authority at execution on the
execution channel; an iterating change without approval on the decision
and execution channels; and, on every channel, the two readings a history
is compared again under, arc's movement since the pin and a newer run
hiding an older pass) to its exact answer, and changes each other field of
that answer in turn — whether it integrated, the basis slots, the audit
verdict, the open audit findings, the owed review, the readiness and
blockers of the check beside a dry run — expecting each change to be left
a disagreement. A plan agrees with a dry run that would integrate only where
the check beside it is ready and names no blocker. 52 checks; a rule that accepted an unrelated field would
fail here without a run against arc.

### Properties

Thirteen properties run over generated scenarios; seeds and case counts are
recorded in the README.

| property | statement |
| --- | --- |
| integratable permits | every history the generator marks integratable permits |
| mutation flips | each one-invalid-transition mutation of an integratable history either refuses or stands down at execution |
| basis grounded | every fact in a permitted basis is present in the ledger and observations; an external authorization names an approval of exactly the basis head; the prerequisite closures are the observed ones; the consumed finding and hold vectors were empty |
| unknown never permits | omitted, unreadable, other-tree, shape-moved, other-environment, environment-unrecorded, and probe-failed evidence never permit where no further run could answer instead |
| moved basis stands down | a target or policy moved between decision and execution produces `RefusedBasisMoved`, never a reused basis, unless authority is withheld, which is refused first |
| waiver exact | a named waiver is bound to the basis patchset and is the newest for it |
| refusal stands | a changes-requested or comment-only verdict on the current patchset is never permitted |
| read needs a reader | a fulfilled read implies a declared, non-contributor reader recorded on the shipped revision |
| debt unused | a debt bound to an approved patchset is reported as recorded debt, not as an authorization input |
| negative audit does not approve | a negative audit that fulfils the read leaves the approval flag false unless an independent approving answer exists |
| decision is the first ground | `decide` permits exactly when `refusals` is empty and otherwise refuses on its first element |
| grounds are facts | every ground `refusals` returns names a fact the history and observations hold, checked constructor by constructor, a probe refusal against the probe runs themselves; execution-only refusals never appear |
| check-time facts refuse | unwaived dirty evidence, a merge nobody evaluated, a head that does not merge, a probe left undischarged, a missing branch, and conflicting declarations never permit |

### Mutants

Eighteen deliberate faults; each must be killed, and each divergence must be of
the predicted class. A decision is compared as `evaluate` answers it, every
standing ground or the basis, not as the first ground `decide` projects.
Distinguishing a different refusal from a permission is deliberate: dropping
one ground of a refusal is a real fault even when another ground answers, and
even when another ground would be listed first.

| fault | channel | predicted divergence | killed (seed 20260907) |
| --- | --- | --- | --- |
| contributor identity ignored | decision | permits, different refusal, different basis | 32 tests, 8 shrinks |
| gate matched by name | decision | permits, different refusal | 1 test, 10 shrinks |
| unknown treated as success | decision | permits, different refusal | 1 test, 9 shrinks |
| authorization reused after its basis moved | execution | permits, different refusal | 9 tests, 7 shrinks |
| fulfilled implies approved | coverage | different value | 13 tests, 2 shrinks |
| latest debt applied to every patchset | decision | permits, different refusal | 1 test, 10 shrinks |
| debt clears a refusing verdict | decision | permits, different refusal | 9 tests, 8 shrinks |
| later audit rewrites the integration basis | historical | different value | 3 tests, 5 shrinks |
| unreadable evidence counts as review | decision | permits, different refusal | 7 tests, 6 shrinks |
| external approval counts as independent review | decision | permits, different refusal, different basis | 9 tests, 10 shrinks |
| environment ignored | decision | permits, different refusal | 9 tests, 9 shrinks |
| authority ignored | execution | permits, different refusal | 72 tests, 9 shrinks |
| dirty evidence counts | decision | permits, different refusal | 1 test, 12 shrinks |
| merge read as the head | decision | permits, refuses, different refusal, different basis | 4 tests, 11 shrinks |
| rebase ignored | decision | permits, different refusal | 1 test, 10 shrinks |
| a final probe pass suffices | decision | permits, different refusal | 2 tests, 9 shrinks |
| missing branch read as the head | decision | permits, different refusal | 3 tests, 10 shrinks |
| first gate declaration wins | decision | permits, different refusal | 4 tests, 9 shrinks |

A surviving mutant is reported as a failure; the suite exits non-zero. The
reason a mutant may legitimately exhibit more than one class is the fault
itself: a ground dropped from a refusal surfaces as a permission when nothing
else stands in the way, and as a different refusal when something does. The
external-approval fault also surfaces as a different basis: where an external
approval already authorizes, the fault names a witnessed verdict instead. The
merge-as-head fault also refuses: evidence recorded against the merge does
not answer for the head's tree it reads instead; and where a further run at
the head does answer for that tree, it permits on a basis naming it.

### Demonstrated counterexample

The smallest demonstration is the unit fixture, not a shrunk random case. The
history is one patchset authored by `author`, with `author` also recording an
approving verdict:

- model: `Refused (RefusedSelfApproval (EventId 2) (ActorId "author")
  (fromList [ActorId "author"]))`;
- `contributor-identity-ignored` mutant: `Permitted`, because it drops the
  contributor comparison from the independence rule.

The mutant's property also finds its own smallest random counterexample (32
tests, 8 shrinks): a one-patchset history approved by its own author, under
a policy that requires independence. Both are
reported by the suite; neither is committed as a golden string, because the
fixture pins the behaviour and the shrunk case pins the shrinker.

### Generator coverage

The coverage sampler generates 4000 scenarios and fails if any required class
is never reached. At seed `20260907` the counts are: permitted 121, waived
43, externally authorized 7, external refused 127, self-approval refused
58, gates refused 209, gate failed 23, environment refused 52, verdict
stands 426, head moved 527, target moved 21, policy moved 27, authority
withheld 19, debt unused 36, unknown observation 521, audit fulfilled read
37, audit negative not approved 3, episode expired 1945, equal-tree
contributor variation 2026, dirty refused 389, dirty waived 13, merged tree
unevaluated 503, merge evaluated 9, needs rebase 367, probes refused 1298,
probe discharged 41, branch missing 377, conflicting gates 309, several
verdicts 715, several debts 504, waiver per patchset 10, older evidence
answers 48, evidence inherited 29, iterating 410, repair-unread derived
330. The classes the first ground names count a history once it is refused
on that ground; the check-time classes, iterating, and the classes of the
widened history count every ground, so a history refused first on another
is still counted. A class with a count of zero is reported by name, so the
suite cannot pass on trivial histories. The check-time facts refuse often,
which is why permitted histories are rarer than the decision fields alone
would make them; the audit and permission classes draw from the
integratable generator in the properties and mutants that need them.

A history holds several verdicts, debts, and gate runs, can return its
latest patchset to an earlier tree, and can declare itself iterating. Each
is drawn at a low weight, so most histories stay as small as before, and
the rare shape the contract names — an older pass at the tree the latest
patchset returns to, with a newer run at the tree between — is drawn on
purpose rather than left to independent draws that would reach it too
rarely to count: `older evidence answers` and `evidence inherited` are the
classes that reach it.

## Differential

`arc-model-differential` replays histories through the arc binary and
compares `arc check --json` with the model's grounds. The comparison is over
sets, because arc reports every blocker and `refusals` returns every ground.
`generated-i` rows draw the fields the decision rests on; `check-time-i`
rows draw the same fields from the same seed and then the check-time facts,
so a check-time row differs from its generated twin only in those facts.

### The mapping

Arc's vocabulary is coarser than the model's. The model claims its grounds
appear in arc's answer as follows; the claim is what the run tests.

| model ground | arc blockers |
| --- | --- |
| `closed`, `iterating`, `blocked-by`, `hold-active` | the same, by name |
| `conflicting-declarations` | none: arc refuses to check at all (`error: conflicting gate declarations`), and the differential records that refusal as `check-refused:conflicting-gate-declarations` |
| `branch-missing` | `branch-missing`, `no-valid-approval`, and `gates-not-green`: with no head, approval validity and gate lookup have nothing to bind to |
| `head-moved` | `no-valid-approval` and `gates-not-green`: arc binds approval validity and gate lookup to the head |
| `needs-rebase`, `merged-tree-unevaluated` | the same, by name |
| `blocking-findings` | `blocking-findings` |
| `verdict-stands`, `external-verdict-stands`, `stale-approval`, `self-approval`, `no-approval`, `contested-verdict` | `no-valid-approval` |
| `gates` | `gates-not-green`, including evidence on a dirty worktree |
| `acceptance-probes` | `acceptance-probes-not-green` |

### The encoding

Each scenario field is a command: a patchset is a commit and `arc snapshot`
(with `--contributors` for the extra contributor); a verdict is `arc review`
by `reviewer`, by `author`, or by nobody so that arc assumes the harness
identity; a finding is a blocking finding on a comment-only review by
`other` that the scenario's verdict then supersedes; each debt is `arc debt`
on the patchset it names, in the order the scenario lists them; an external decision is `arc external verdict` at the
current head; gate evidence is `arc verify` under an environment that makes
the declared gate fail or its probe print a chosen identity, or print
nothing so the evidence records none; a changed declaration is an
uncommitted edit of `gates.toml`; a further run is a clean `arc verify` at
the head of the patchset it names, after that patchset's own run; a latest
patchset that returns to an earlier tree is `git revert` of the commit
before it; an iterating change is `arc iterating`; a moved head is a commit
after the last snapshot. The model records gate runs in the order the plan
makes them, patchset by patchset, so the newest run is the same run on both
sides. The decision is asked with the probe printing the local identity,
or nothing when the scenario fails it. Policy is written to
`.arc/policy.toml` and the change edits the declared dangerous path exactly
when independent review is required.

The check-time facts are commands too. Dirty evidence is `arc verify` with
an uncommitted edit in the worktree, removed after the run; a dirty-tree
waiver is `arc verify --command true --waive-dirty`, declared right after
the dirty run to name its revision, or before the first commit to name the
change's base (the ad hoc run it records is no gate evidence, and the model
records nothing for it). A target that moved is a commit on `master` before
the first patchset; the gate then runs at the head, or with `arc verify
--against master` when the scenario evaluates the merge. A conflicting
target is a commit on `master` adding the file the change adds, made just
before the decision. A probe is `arc brief --probes-json` declaring one probe
whose command fails on demand, based at the worktree's head before the first
commit, with its baseline run there and its final run at the last patchset;
a probe that cannot be discharged is based at the last commit, with both
runs at that one revision. A missing branch is the worktree removed and the
branch deleted, and the decision is then asked from the main checkout. A
conflicting declaration is the same gate declared with another command in
the operator's layer, `<git-common-dir>/arc/operator-policy.toml`.

Four fields have no command, and a scenario using one is skipped with the
reason rather than approximated: unreadable evidence, evidence at another
tree when there is no earlier patchset to record it at, a finding on a
history with no verdict, since arc records findings only with one, and dirt
on a run against the merge, since `verify --against` runs in a clean
checkout of its own and records none.

Four scenario fields do not reach the decision: a target or policy moved
before execution, withheld authority, and a post-integration audit. The
decision channel does not replay them; the execution channel replays the
first three, and the coverage channel all four.

A rejection of the head is recorded by arc's command together with the
closure it causes; the scenario builder records both events, as arc does.

### The sandbox

Every replay runs in a sandbox of `Differential.Sandbox`, the differential's
and a replay by hand through `arc-model-sandbox` alike. Its environment is
built from nothing: `PATH`, `LANG`, `LC_ALL`, `LC_CTYPE`, and `TZ` are the
only ambient variables admitted; `HOME`, the XDG directories, `TMPDIR`,
`GIT_CONFIG_GLOBAL`, and `ARC_SANDBOX` point inside the sandbox's root; Git
reads no system configuration and opens no editor. Before anything runs,
a self-check refuses a location outside the root, an unset one, and any
variable nobody admitted, naming each; only once that passes does a probe
write a nonce with `git config --global` and require the file it lands in
to lie inside the root. Each command's final environment is checked again
before it starts. A refusal stops the run with exit 70, so no replay reads
or writes the operator's configuration.

### Results at the comparison revision

Seed `20260907`, `--cases 200 --check-time-cases 200`: 442 cases, 398
agreed, 44 skipped, 0 adjudicated, 0 disagreed, 0 failed to replay.

| rows | cases | agreed | skipped |
| --- | --- | --- | --- |
| the 29 decision histories named first | 29 | 29 | 0 |
| `generated-0` .. `generated-199` | 200 | 181 | 19: 10 unreadable evidence, 4 other-tree on one patchset, 5 finding without verdict |
| the 13 check-time histories named after them | 13 | 13 | 0 |
| `check-time-0` .. `check-time-199` | 200 | 175 | 25: the same 19, and 6 dirt on a run against the merge |

The generated rows hold every check-time fact at its default, so their
histories are the decision generator's alone. Of the 200 check-time rows, 165 carry at least one check-time fact: 55 dirty
evidence runs (21 unwaived, 14 waived at their revision, 20 waived at the
base), 69 moved targets (22 unevaluated, 27 evaluated, 20 conflicting), 115
briefs (49 discharged, 16 baseline passed, 12 final missing, 13 final
failed, 25 undischargeable), 22 missing branches, and 19 conflicting
declarations. No disagreement class is on record;
`Differential.Compare.adjudicate` is where one is named, with the scenario
shape and blocker sets it applies to, when a run produces one.

### The comparison can object

`--mutant NAME` expects a permission wherever the named fault permits and
the model's grounds elsewhere, so a run objects exactly where the fault
would let arc's refusal through. At seed `20260907` with 40 generated cases:

| fault | rows that object | what arc refused |
| --- | --- | --- |
| contributor identity ignored | `contributor-reviewer`, one generated | `no-valid-approval` |
| environment ignored | `gate-other-environment`, `gate-environment-unrecorded`, `gate-probe-failed`, two generated | `gates-not-green` |
| external approval counts as independent review | `external-approved-danger` | `no-valid-approval` |
| unknown treated as success | every gate history but `gate-covered`, plus generated | `gates-not-green` |

For the check-time faults, at seed `20260907` with `--cases 0
--check-time-cases 40`:

| fault | rows that object | what arc refused |
| --- | --- | --- |
| dirty evidence counts | `gate-dirty`, `gate-dirty-waived-elsewhere` | `gates-not-green` |
| merge read as the head | `target-behind` | `merged-tree-unevaluated`, `gates-not-green` |
| rebase ignored | `target-conflicting` | `needs-rebase` |
| a final probe pass suffices | `probe-baseline-passed`, `probe-undischargeable` | `acceptance-probes-not-green` |
| missing branch read as the head | `branch-missing` | `branch-missing`, `no-valid-approval`, `gates-not-green` |
| first gate declaration wins | `conflicting-gates` | the check itself |

No generated row objects under these faults at 40 cases: a fault permits
only where every other fact would, and a generated history carrying one
check-time fact rarely clears the rest.

Each run exits non-zero. The first row of the first table is the
demonstrated counterexample against the arc binary: one patchset by `author`
approved by `author` under a policy that requires independence, which the
fault permits and arc refuses.

### The execution channel

`--channel execution` compares `execute` with `arc integrate --dry-run`.
arc keeps no decision to re-check at integration: it refuses a store that
does not hold integration authority with exit 17, then evaluates readiness
again, and a dry run reports what that evaluation answers without writing.
So the model's execution maps onto a dry run as follows:

| `execute` | a dry run |
| --- | --- |
| a plan | exit 0, would integrate, with `arc check` in the same world ready and naming no blocker |
| `authority-withheld` | exit 17 |
| any other refusal: the decision's own, `basis-moved`, `branch-missing`, `conflicting-declarations` | a non-zero exit other than 17, with `arc check` in the same world reporting the blockers the model's grounds name under the execution-time observations |

A basis that moved is where the two answer differently in kind. The model
computes readiness again and names what moved against the rebuilt basis,
with the grounds where readiness now refuses; arc names the blockers its
fresh evaluation finds. The mapping claims the two
refuse together and that arc's blockers are the model's own grounds under
the moved observations: a target that moved leaves the head behind a merge
nobody evaluated, so `merged-tree-unevaluated` and `gates-not-green`.

The moves are commands made after `arc check` answers: a target moved is a
commit on `master`; a policy moved is the worktree's `.arc/policy.toml`
rewritten, uncommitted, to the other policy, with the file the change edits
declared dangerous exactly when the new policy requires independence;
withheld authority is the store paired with a second repository's store
through `arc replica init`, `pair`, and `authority offer`, which relinquishes
it. The dry run and the second check run where the decision was asked. A
policy moved on a history whose branch is gone is skipped: the only
checkout left is the target's, and integrate refuses a target checkout with
tracked changes before it reads readiness.

What a dry run cannot answer: a moved head or patchset at execution (no
scenario field moves them), and the facts the model names beside a refusal;
the comparison is over exit codes and blockers. What it answers that the
model does not state: the target checkout's own dirt, and contribution mode.

Two disagreement classes are on record, both `unsettled`, both the points
of the same name under "Unsettled design":

- **Authority at execution.** A refused decision in a store without
  authority: arc answers exit 17, since it refuses the store before reading
  readiness; the model's `execute` answers a refused decision with its
  refusal. Both refuse; which refusal answers first is the contract. The
  rule applies only where the check beside the dry run refuses on exactly
  the blockers the model's grounds name.
- **Policy motion.** A policy moved between the decision and the
  integration, where the model's own grounds under the new policy are none:
  arc decides again under that policy and would integrate; the model acts
  only on the decision made before the policy moved, and stands down. The
  rule applies only where the check beside the dry run is ready and names
  no blocker.

`--mutant authority-ignored` objects on `execute-authority-withheld`, and
`--mutant authorization-reused-after-basis-moved` on
`execute-target-moved`, `execute-policy-tightened`,
`execute-authority-withheld`, and `execute-target-and-authority`; each run
exits non-zero.

At seed `20260907`, `--channel execution --cases 200 --check-time-cases
200`: 448 cases, 339 agreed, 62 adjudicated, 47 skipped, 0 disagreed, 0
failed to replay.

| rows | cases | agreed | adjudicated | skipped |
| --- | --- | --- | --- | --- |
| the 42 histories named for the decision | 42 | 42 | 0 | 0 |
| the 6 histories named for execution | 6 | 4 | 2: 1 authority, 1 policy | 0 |
| `generated-0` .. `generated-199` | 200 | 150 | 31: 27 authority, 4 policy | 19, as on the decision channel |
| `check-time-0` .. `check-time-199` | 200 | 143 | 29: 28 authority, 1 policy | 28: the decision channel's 25, and 3 policy moved without a worktree |

### The coverage channel

`--channel coverage` replays the history and the execution moves, runs
`arc integrate` for real, records the scenario's audit with `arc audit` (by
`other`, or by `author` when the audit is not independent, with one blocking
finding when it asks for changes), and reads back what arc recorded. The
model's side is `historicalAuthorization` and `coverageAfterIntegration` of
the history the scenario builds, integration and audit included.

| model | arc |
| --- | --- |
| an integration recorded | `closure.outcome` is `integrated` in `arc show --json` |
| `AuthorizedByVerdict` | the closure's authorization names `verdict_event_id` |
| `AuthorizedByWaiver` | it names `audit_debt_event_id` |
| `AuthorizedByVerdictUnderWaiver` | it names both |
| `AuthorizedByExternalVerdict` | it names `external_verdict` |
| the coverage's audit verdict | the newest of `audit_verdicts` |
| the coverage's open findings | the audit findings of `arc findings --audit --format json` with no disposition |
| a debt authorized the merge and no read fulfilled it | `arc query --debt --json` lists the change |

The model's `approved` flag has no field in arc and is not compared. arc
keeps the two facts it is read from: the authorization's verdict, which no
later audit rewrites, and the audit verdicts beside it. So "Approval beside
a later negative audit" is measured as that pair: after an independent
negative audit, arc's closure still names the verdict and its newest audit
verdict is `changes-requested`, which is what the model's basis and audit
verdict say; whether the pair should read as approved stays unsettled.

"External beside local" is measured as a disagreement. Where a witnessed
approval and an external approval of the head both stand and the policy
lets an external approval count, arc's basis names both, and the model's
`AuthorizedByVerdict` names the verdict alone. Under a policy that
requires independent review the external approval does not count and arc
names the verdict alone, as the model does. The class is adjudicated
`unsettled`.

Policy motion is adjudicated only where arc's record is, field for field,
the one the model makes when it decides afresh under the moved policy:
`Built.redecidedState` is the history the model records from
`decide` under the execution-time observations, integration and admitted
audit included, and the rule compares arc's answer with that history's
authorization, audit verdict, open audit findings, and owed review. The
expectation is the model's alone; nothing in it is read from arc's answer.
Any other difference on such a history stays a disagreement.

One class is `encoding`. Where policy requires a declared actor, arc
refuses to record a verdict nobody declared, and the model's ledger holds
it: `require_declared_actor` is modelled for the invoker only. Both
decisions agree, since the refused verdict could not have authorized
anything; the recorded basis differs by that verdict where a waiver
authorized the merge beside it (`cover-undeclared-reviewer-waived`).

One disagreement class on this channel is a model defect, and the model
states the rule that answers it: arc refuses a contributor's approving
audit wherever policy forbids self-approval, and records it, discharging
nothing, elsewhere. `admitAudit` is that rule, and the scenario builder
records only the audits it admits. A builder that recorded every audit
would disagree with arc on `cover-waived-author-audit`: an `approved`
audit verdict where arc has none.

`--mutant fulfilled-implies-approved` cannot object, since it faults only
the `approved` flag arc does not record.

At seed `20260907`, `--channel coverage --cases 200 --check-time-cases
200`: 453 cases, 396 agreed, 10 adjudicated, 47 skipped, 0 disagreed, 0
failed to replay.

| rows | cases | agreed | adjudicated | skipped |
| --- | --- | --- | --- | --- |
| the 42 histories named for the decision | 42 | 42 | 0 | 0 |
| the 11 histories named for coverage | 11 | 9 | 2: 1 external beside local, 1 undeclared reviewer | 0 |
| `generated-0` .. `generated-199` | 200 | 175 | 6: 1 external beside local, 4 policy motion, 1 undeclared reviewer | 19, as on the decision channel |
| `check-time-0` .. `check-time-199` | 200 | 170 | 2: 1 external beside local, 1 policy motion | 28, as on the execution channel |

`--mutant later-audit-rewrites-integration-basis` objects on
`cover-waived-negative-audit`, where the fault names the audit as a
verdict and arc's basis names the debt, and exits non-zero; `--mutant
fulfilled-implies-approved` agrees everywhere and exits zero.

### Results against the installed arc

The same seed and case counts, replayed against the arc installed when the
run was made, `arc 2026.9.9`, whose binary postdates arc `1170fb4`. The
model still characterizes `comparisonRevision`. The histories include the
widened generator's and the five named after the contract's questions.

| channel | earlier run, at the comparison revision | this run, installed arc |
| --- | --- | --- |
| decision | 442 cases: 398 agreed, 0 adjudicated, 44 skipped, 0 disagreed | 447 cases: 368 agreed, 39 adjudicated, 40 skipped, 0 disagreed |
| execution | 448 cases: 339 agreed, 62 adjudicated, 47 skipped, 0 disagreed | 453 cases: 315 agreed, 93 adjudicated, 45 skipped, 0 disagreed |
| coverage | 453 cases: 396 agreed, 10 adjudicated, 47 skipped, 0 disagreed | 458 cases: 398 agreed, 15 adjudicated, 45 skipped, 0 disagreed |

No replay failed. Before these classes were named, a first pass left 16,
37, and 3 rows unclassified on the three channels. Each adjudicated row
falls in one class:

| class | kind | decision | execution | coverage |
| --- | --- | --- | --- | --- |
| a declaration or policy moved by an uncommitted edit, which the installed arc does not read | arc moved since the pin | 24 | 37 | 6 |
| an iterating change without approval | unsettled (C11) | 11 | 11 | 0 |
| a newer run from another environment hides the pass at the evaluated tree | Rust defect (C14) | 1 | 1 | 1 |
| a newer run recording no environment hides the pass at the evaluated tree | unsettled (C14) | 3 | 3 | 3 |
| authority at execution | unsettled (C20) | – | 41 | – |
| external beside local | unsettled (C9) | – | – | 4 |
| undeclared reviewer | encoding | – | – | 1 |

- **Arc moved since the pin.** The installed arc reads `.arc/gates.toml`
  and `.arc/policy.toml` from the target branch's commits, which is reading
  (ii) of C12 and reading (i) of C20's policy motion. The plan moves a
  declaration and a policy by editing the worktree's files without
  committing them, so for this arc nothing moved. A row is classified this
  way only where arc's answer is the model's own for the scenario with
  those moves undone, agreed or adjudicated as that scenario would be. This
  is not a defect of either side. It does mean that, against this arc, the
  declaration-changed and policy-motion histories measure nothing about
  C12 or C20 until the plan commits the move on the target. The policy
  motion class (C20) therefore no longer appears: every history it
  classified at the comparison revision is explained by the unmoved
  reading.
- **Iterating without approval (C11).** arc's check reports `iterating` and
  leaves out `no-valid-approval`, which is reading (ii). The model reads
  (i). On the execution channel the dry run refuses with exit 13 on the
  same blockers. With withheld authority it exits 17 beside them, which
  the authority class then covers.
- **An older pass hidden by a newer run from another environment (C14).**
  This is `gate-older-pass-newer-other-environment` and the rows that
  generate its shape. The latest patchset returns to tree A. A pass at A
  from this environment is followed by a run at A from another
  environment, and arc refuses the gate. C14 is settled: a record from
  another environment never hides one that answers. With the newer run
  left out arc is ready, and with the older pass left out arc refuses as
  the model does, so the newer record alone is the difference. Filed in
  arc's journal as the feature request
  `gate-evidence-hidden-by-other-environment`, with the replay steps.
- **An older pass hidden by a newer run recording no environment (C14).**
  This is the same shape with a probe that printed nothing. C14 does not
  say whether an unknown environment is another key or an unknown reading
  under the key in force. The contract records both readings; the model
  reads the first and arc behaves as the second.
- The authority, external-beside-local, and undeclared-reviewer classes
  are the ones on record at the comparison revision.

### What a quiet run means

Every replayed history agreed, or disagreed in a class somebody read and
named, over the fields the CLI can express and on the channel the run
compared. It is supporting evidence for the model's characterization of
these decisions and for arc's implementation of them, and nothing more:
the fields the CLI cannot record, the answers arc keeps no field for (the
model's `approved`), and the operating-system behaviour a pure model cannot
state remain outside it.

### Recommendation

The evidence supports extracting one pure decision boundary from arc: the
blocker derivation in `status.rs`, which turns already-computed facts —
approval validity, gate greenness, probe discharge, open findings, holds,
the branch, dependency and rebase state, and whether the merge was
evaluated — into the blocker list. It has an independent twin in
`evaluate`, the differential protects it on 398 agreed histories, named and
generated, and the extraction changes no observable answer. The approval-validity
computation above it, where local, external, waiver, and danger interact,
is the next candidate and the one where the vocabulary differences listed
under unsettled design would have to be settled first.

## Comparison revision

`comparisonRevision` names arc `26f6bdc`. Every commit between the previous
pin, `df47db0`, and it was read for its effect on the modelled decision. The
model changes were written from the behaviour each commit's tests and docs
state, not by translating its diff.

| commits | subject | effect on the model |
| --- | --- | --- |
| `eaca714`, `e580393` | verdicts decided outside arc; local refusals kept beside an external approval | modelled: `ExternalVerdict` record, `RefusedExternalVerdictStands`, `AuthorizedByExternalVerdict`; a local refusal is checked before the external decision; the `external` fixture and the external-approval mutant |
| `be9799c`, `913df16` | gate evidence bound to the environment a probe reports; a failed probe is no identity | modelled: `Declaration.environment`, `Verification.environment`, `Observations.environments`, three coverage constructors; the `environment` fixture and the environment-ignored mutant |
| `ba7de9d`, `53e70cb`, `c9e029b`, `2143242` | replica pairing and integration authority | modelled at execution: `IntegrationAuthority`, `RefusedAuthorityWithheld`; the protocol that decides who holds authority is an observation, not modelled |
| `9b6ac80`, `745a27c`, `fb1227b` | operator policy layered with project policy; conflicting gate declarations refused | the model takes the effective policy and declaration set as observations; the gates two layers declare differently are an observation too, refused alone as `RefusedConflictingDeclarations` |
| `e8e16a3` | `done` with no gate declared reports a check state | already modelled: no required gate yields an empty gate basis |
| `a6a04a8` | a contribution is recorded ready to send instead of merged | no change to the decision; the effect kind is unsupported |
| `4eb7200`, `82cfcbb`, `6f4999b`, `081b5d8`, `96f3c17`, `3102eb3` | already-contained heads, checkout guards, squash rollback | Git effects, unsupported |
| `4f637de`, `d330b54`, `da289f5`, `0f87cff`, `51e3f4d`, `b20300a`, `11d1e15` | session identity detection and its reader | no change: identity collapses to the declared/assumed boolean |
| `fec3f1c`, `a138b98`, `3cc953f`, `ceaa01e`, `5b6fe2f`, `a26542a` | bundles, journal exchange, patchset links, store stamps, build | no effect on the decision |
| `fc5801b`, `2309683`, `5e8bac7`, `8e4866c`, `1f567a5`, `fed2648`, `630dd30`, `ed1477b`, `4076eef`, `f9fcbd9`, `54c9fe2`, `8c4df11` | workspace views, journal locking, docs | no effect on the decision |

## Unsettled design

Points where the model fixes a reading that production or a future slice may
still choose differently. Each is a deliberate choice, not an oversight.

- **Refusal order is presentation.** The semantics of a refusal is the set
  of grounds that stand (CONTRACT.md, C23). `refusals` lists them in a fixed
  order and `decide` names the first, but neither order carries meaning:
  arc's documentation gives each blocker an exit code and derives no
  precedence among them, and the model claims none. Refusals compare as
  sets, which is how the differential compares them. Conflicting
  declarations are the one structural exception, a set of one ground
  because nothing else can be evaluated.
- **A moved head is its own ground.** The model names `RefusedHeadMoved` and
  still evaluates authorization and gates against the recorded patchset.
  Production folds a moved head into approval validity and gate lookup, so
  it reports no valid approval and gates not green instead. The facts agree;
  the vocabulary does not, and the differential's mapping states the
  correspondence.
- **External beside local.** When a witnessed approval and an external
  approval both stand, the model's basis names the witnessed verdict.
  Production records both in its authorization basis where the policy lets
  the external approval count; the coverage channel adjudicates each such
  history.
- **Tree before environment.** Coverage reads the tree before the environment,
  so evidence from another tree in another environment is reported as
  other-tree. Production tests both and reports neither first. The worktree
  sits between them: dirty evidence at another tree is other-tree, and dirty
  evidence at this tree is dirty whatever its environment.
- **A merge nobody evaluated.** The model names it when the head is behind
  its target, a gate is required, and no record of a required gate carries
  the evaluated tree, whatever that record's result. Production reads the
  evidence its gate lookup selects for the evaluated tree; the two agree on
  every history the CLI can record, where no record at that tree is ever
  unreadable.
- **Conflicting declarations stand alone.** Production refuses to check at
  all, so no blocker is reported beside the conflict; the model returns that
  one ground, not every ground, because there is no declaration set to read
  the rest against.
- **Authority at execution.** Production refuses a store without integration
  authority when `integrate` starts, before readiness; `check` never asks.
  The model refuses it in `execute`, before comparing the basis, and never in
  `decide`; a decision that was refused is answered with its own refusal
  whatever the store's authority, where production answers exit 17.
- **Debt kind derivation.** `nothing-read`, `contributor-only`,
  `repair-unread`, and `independent-review` are derived;
  `merge-resolution-unread` is accepted only when declared, because the
  ledger sees a merge resolution and a repair identically. Whether the
  ledger itself should distinguish them is open.
- **Coverage after a repair.** A negative audit fulfils the read and leaves
  its findings open. A repair after that audit starts a fresh obligation in
  the model. Whether the fulfilled read should survive a repair is a policy
  question the model does not answer.
- **Approval beside a later negative audit.** `approved` reports
  whether an independent approving answer exists. An independent approval on
  the shipped patchset makes it true even after a negative audit; the audit's
  verdict remains its own field. Production keeps no such flag: it keeps the
  authorization's verdict unrewritten and the audit verdicts beside it, and
  the coverage channel compares that pair. Whether a later negative audit
  should withdraw the approval flag is open.
- **An unknown environment at the evaluated tree.** A run that recorded no
  environment answers nothing for a gate with a probe. The model keys it
  apart, so it does not hide an older pass from this environment either
  (C14, reading (i)). The installed arc lets it decide as the newest record
  at the tree.
- **Policy motion.** A policy that changes between decision and execution
  produces `RefusedBasisMoved` rather than a re-decision. Re-deciding under
  the new policy would be a different action, with a different basis.
  Production re-decides: `integrate` evaluates readiness under the policy in
  force when it runs, and the execution channel adjudicates the difference
  where that re-decision permits.
- **Contested verdicts.** The model treats more than one active tip as
  contested and refuses. It does not model the repair of a contested chain
  beyond the arrival of a single superseding verdict.
- **Claim episodes.** A claim's expiry is modelled as a fact about liveness
  only. Stage budgets, staleness, and claim generation are not modelled.

## Open decisions against the contract

Where the model and a settled clause of [CONTRACT.md](CONTRACT.md) answer
differently. Each is recorded here, not repaired, until it is adjudicated as
a model defect or a contract to amend; it then moves to
[Adjudicated](#adjudicated). Where a clause is unsettled, the clause itself
names the reading the model takes, and nothing is listed here.

None stands.

## Adjudicated

Disagreements between the model and the contract, each with its class and
the change that settled it. A model defect carries a fixture that fails on
the model before the fix.

- **Which verification answers a gate (C14): model defect.** `readGate`
  took the newest record for the gate and declaration across every tree,
  so a newer run at tree B hid an older pass at the evaluated tree A, and a
  newer record under another declaration or environment hid a matching one.
  The model keys evidence by tree, declaration, and environment; the newest
  record under the key decides, which is the clause's reading (i) for
  several matching records, and the newest record overall only says why
  nothing answers. Fixture `keyed`; commit `5b833c8`.
- **Falsification (C13): model defect.** `readGate` read `falsified` from
  the newest record at the evaluated tree, so a later pass naming no
  failure hid an earlier one that did. The model reads it from any
  readable passing record under the key in force; the counted revision is
  read through C14, where two commits with one tree are one evaluation.
  Advisory only; no decision changes. Fixture `falsified`; commit `b7e838a`.
- **Declared actors (C18): model defect.** `evaluateDeclared` refused an
  undeclared invoker as a decision ground. The clause, from
  `docs/review.md` ("Reading is unaffected"; `integrate` checks before it
  merges), leaves the readiness check alone. `RefusedUndeclaredActor` is an
  execution refusal, raised by `execute` after withheld authority. Fixture
  `undeclared-actor`; commit `59b529e`.
- **The basis (C19): model defect.** `DecisionBasis` named no prerequisite
  closures, and the observations named only the prerequisites still open.
  `docs/changes.md` lists each prerequisite's closure in the authorization
  basis. `Observations.prerequisites` names each prerequisite with the
  closure that integrated it, where one did; the open ones refuse, and the
  basis and the integration record name the rest. Fixture `prerequisites`,
  which the model without the slot does not compile; commit `51fb6b2`.
- **Execution rebuilds the basis (C20): model defect.** `execute` compared
  the basis with the observed head, target, tree, and policy and never
  computed readiness again, so a finding opened, a hold set, a verdict
  recorded, or gate evidence superseded between the decision and the
  execution left the plan standing. `docs/changes.md` recomputes readiness
  and rebuilds the basis before merging. `execute` evaluates again; a
  refusal stands down with `MovedReadiness` and its grounds beside the
  observed moves, and a rebuilt basis that differs names each moved slot.
  Permission is still not effect: the plan records nothing, and policy
  motion still stands down, the clause's reading (ii). Fixture `rebuilt`;
  commit `aea73bb`.
- **Debt kinds and the owed review (C21): contract to amend.** The clause
  said the ledger derives neither `merge-resolution-unread` nor
  `repair-unread`. `docs/review.md` defines `repair-unread` in ledger terms
  ("an approved patchset, then authored work nobody read") and reserves
  only the merge resolution for the caller, "because the ledger sees a
  resolution and a repair the same way"; `arc debt --help` says the same.
  The clause now derives `repair-unread` for a patchset with no verdict
  after an approved one, and keeps `merge-resolution-unread` declared-only.
  Its unsettled case narrows to earlier verdicts none of which approves,
  read as `independent-review`: `nothing-read` is defined as no verdict on
  any patchset, so it is no reading there. The model disagreed with both
  texts in different ways — `debtKindFor` derived `nothing-read` after an
  approval, and `reviewObligation` derived `repair-unread` from the absence
  of a change request — and answers to the amended clause through one
  derivation, `derivedKind`, for the debt and the owed review. Fixture
  `debt-kind`; commit `9e0f0c9`.

## Deferred out of this package

Recorded here so a reader does not read the package's scope as a claim
about them:

- **The candidate protocol.** The proposed challenge/evaluation/selection
  semantics is a separate model in its own component, described under
  [The proposed candidate protocol](#the-proposed-candidate-protocol). The
  existing-authorization model carries none of its rules and cannot import
  it.
- **A multi-obligation debt representation.** The single-slot waiver query
  is the production reducer's semantics; a representation carrying several
  obligations would be a different model, not a refinement of this one.

## Known unsupported semantics

- **Git effects.** Synthesizing a merged tree, deciding whether it
  conflicts, verifying that a merge commit's tree is the evaluated one,
  closing a change the target already contains, the checkout guards, squash
  rollback, and the reset after a mismatch are outside the model. The head,
  the target, how the two merge, and the evaluated tree are observations;
  the `needs-rebase`, `merged-tree-unevaluated`, and `branch-missing`
  blockers are grounds read from them.
- **Fork branches.** The `fork-branch` blocker is not modelled and has no
  replay: arc refuses to open a change on a fork's branch and refuses a fork
  marker over an open change's branch, so no command sequence puts a change
  on one.
- **A tree that moved during the run.** Production records evidence whose
  worktree changed while the command ran and never counts it. The model's
  verifications carry no such flag, and no plan step can move a tree
  mid-run deterministically.
- **Durability, locking, races, crash recovery.** A pure model cannot
  establish them; they stay independent OS-level tests.
- **Gate declarations beyond the conflict.** Which layer a declaration
  comes from, and how two agreeing layers merge, are not modelled: the model
  takes the effective declaration set, and the names of the gates two layers
  declare differently, as observations.
- **Ledger replay of environments.** Where production evaluates without a
  checkout, evidence carrying any identity counts. The model characterizes
  the live decision, where the identity must be observed here and equal.
- **External change-request findings.** Production carries them on the
  external verdict; the model's external decision carries none, and the
  change request itself is the refusal.
- **Contribution mode.** Whether a permitted integration merges or is
  recorded ready to send is an effect kind the model does not name.
- **Acceptance probes beyond discharge.** Brief versions, attested probe
  runs, and a brief superseding another are not modelled: a patchset names
  the brief in force when it was recorded, and a probe is read against that
  brief's base and the patchset's head.
- **Provenance categories.** `actor_source` values (`flag`, `env`, `derived`,
  `git-fallback`) collapse to a declared/assumed boolean. `require_declared_actor`
  is modelled for the invoker only.
- **Forks, worktrees, retention, bundles, journal, changelog projection,
  replica exchange.** None are modelled; authority is an observation.
- **Review-map advisories.** `reviewer-behind-final-patchset`,
  `no-independent-reviewer`, and the other advisories are not modelled; they
  never block, and the model's job is the blocking decision.
- **Dependency status.** `Observations.prerequisites` names each prerequisite
  and the closure that integrated it; how a chain's readiness is computed is
  not modelled.

## The proposed candidate protocol

A separate model of semantics no arc revision implements. It is checked for
consistency and for sensitivity to named faults; no differential exists or
can exist until an implementation does. The evidence below is produced by:

```sh
cabal v2-test candidate-spec --test-show-details=direct --test-options="--seed 20260907 --tests 300"
```

### Separation

The candidate model is the internal library `arc-model:candidate`, whose
only project dependency is `arc-model`, and of it only
`Arc.Model.Identifiers` and `Arc.Model.Observed` are imported. The main
library cannot use it. An `import Arc.Candidate` in an `Arc.Model.*` module
is refused as a hidden package:

```
Could not load module 'Arc.Candidate'.
It is a member of the hidden package 'arc-model-0.1.0.0:candidate'.
```

and declaring the dependency to force it is refused before anything builds:

```
Dependency cycle between the following components:
    library
    library candidate
```

No `Arc.Model.*` module, the `spec` suite, the scenarios, or the
differential depends on the candidate component.

### Structural type invariants

- **Distinct identifiers.** `CandidateId`, `EpisodeId`, `EvaluationId`,
  `ReviewId`, `SelectionId`, `ToolRecordId`, `JournalId`, `ArtifactName`,
  `RepositoryId`, `ContentId`, `PathName`, `VersionId`, and
  `InferenceSource` are separate types, beside the shared ones. A candidate
  is never its tree: registrations compare by `CandidateId`, trees by
  `TreeId`.
- **A registration has no change.** `Registration` carries no change or
  patchset field, so registering an alternative cannot open one; only a
  `SelectionBasis` names a `Destination`.
- **A reference separates address from observation.** `ContextRef` holds a
  `Locator` and, separately, an `Observed VersionId` and an `Observed
  Extent`. `resolve` goes through the version; an omitted version resolves
  to `VersionUnobserved`, never to the locator's current content.
- **Relations carry their establishment.** `ContextRelation` is a sum of
  `Supplied`, `Read`, `Declared`, and `Inferred`; only `Read` holds a
  `ToolRecordId`, only `Declared` an attributed declarant, only `Inferred` an
  `InferenceSource`. `readSatisfaction` consults `Read` alone.
- **Omitted is not a result.** `EvaluationRecord.outcome` and `.environment`,
  `Observations.target` and `.environment`, reference coverage, and the
  capture a provider reported are `Observed` values; no code path turns
  `Omitted` into a pass, a match, full coverage, or a pin.
- **The reuse policy has no default.** `evaluate` and `refusals` take a
  `ReusePolicy` argument; `Requirements` has no reuse field and the library
  exports no default value. Every basis records the policy it was decided
  under.
- **Selection is validation.** `evaluate :: ReusePolicy -> Requirements ->
  Observations -> State -> Proposal -> Either (NonEmpty Refusal)
  SelectionBasis` takes the choice as input and returns no state. Recording
  it is a separate `record` of `SelectionRecorded`, which touches only the
  selection map.
- **Permission is not effect.** `promote` returns a `PromotionPlan`; only
  `recordPromotion`, given an `Observed` result, writes a `Promotion`.
- **Collection is not permitted by the model.** `collection` answers
  `CollectionRefused root` or `NoRootReaches`; there is no constructor for
  permission to delete.

### Runtime validation

#### Unit fixtures

`candidate-test/Fixtures.hs`, 63 checks:

| fixture | what it anchors |
| --- | --- |
| `equal-tree` | two registrations of one tree share one storage entry; a review of A authorizes A and not B (`ReviewOfOtherCandidate`); B's producer may review A and not B |
| `different-tree` | two trees, two storage entries; either is selectable |
| `selection-immutable` | selecting and promoting leaves every registration as recorded; the basis names the proposal's choice |
| `stale-target` / `stale-evaluation` | a proposal naming an old target is `target-moved`; evidence at another tree, declaration, or environment is refused with the coordinate; a target moved after the decision stands the promotion down |
| `episode` | an episode with no candidate, one with three, and a candidate citing two episodes |
| `expiry` | an expired episode is not live; the selected candidate and its episode record stay rooted; an unrooted alternative is reached by no root; a declared root retains a losing alternative |
| `amended` | a read of the first version resolves to it after an amendment and still meets the requirement; an unversioned reference resolves to nothing; a lost version is unavailable |
| `lead-repair` | the lead is among the contributors and the repaired tree ships; the lead cannot be the independent reviewer; a review of the unrepaired tree is stale |
| `reuse` | the same selection is refused under `ReuseNever` (`OtherRegistration`) and permitted under `ReuseOnMatchingCoordinates`; the latter still needs the tree and a recorded environment; review authority is never reused |
| `claims` | a declared reliance, an inference, a supply, an unknown coverage, a partial read, and no read are each their own shortfall; relations stand as record, claim, or inference by establishment |
| `citation` | a declaration citing an unrecorded read is refused; one citing a recorded read is accepted and remains a claim |
| `registration` | a second registration of one identity and an unversioned brief are refused |
| `effect` | a promotion plan records nothing without an observed result |
| `capture` | a rooted reference is retained when pinned, at risk when unpinned or unobserved |
| `unknown` | an unobserved outcome, target, or environment, and no named evaluation, each refuse |
| `every-ground` | a stale target, a failed gate, a changes-requested review, and a declared-only read are all reported, in order |
| `demonstration` | a producer reviewing its own candidate is refused; the contributor-identity fault permits |

#### Properties

Fourteen properties over generated plans:

| property | statement |
| --- | --- |
| registrations immutable | the registrations after every event are exactly the ones registered |
| selection is named | the basis's candidate, target, selector, destination, evaluations, and review are the proposal's |
| review authority | a required review in a basis names the chosen registration and shipped tree, approves, and is by no contributor |
| evidence grounded | every basis evaluation is at the shipped tree, the required declaration, the observed environment, passed, and on the chosen registration unless the policy reuses |
| repairers contribute | basis contributors are exactly the producers and the repair authors |
| unknown never permits | an unobserved target, environment, outcome, or coverage never permits |
| reads are observed | every read in a basis is a tool record of the chosen candidate's episode covering the required version and extent |
| target moved stands down | a target moved after the decision refuses the promotion as `basis-moved` |
| roots retain | a selection's candidate, tree, evaluations, brief, and episodes are refused collection |
| expiry deletes nothing | every collection answer is the same with and without episode expiry |
| reuse-never is stricter | whatever `ReuseNever` permits, `ReuseOnMatchingCoordinates` permits |
| unpinned at risk | a retained reference is `Retained` only when its provider reported it pinned |
| reference resolves observed | every read resolves to the version it observed, or reports it unavailable |
| relations by establishment | a tool record stands as a record, a declaration as a claim, an inference as an inference |

#### Mutants

Each must be killed, and each divergence must be of the predicted class.
Decision faults draw from every plan; promotion and retention faults from
plans the model permits.

| fault | channel | predicted divergence | killed (seed 20260907) |
| --- | --- | --- | --- |
| candidate identity dropped when trees match | decision | permits, different refusal | 2 tests, 9 shrinks |
| decision reused after the target moved | promotion | permits | 15 tests, 11 shrinks |
| contributor identity ignored in selection authority | decision | permits, different refusal | 46 tests, 7 shrinks |
| unknown context treated as complete | decision | permits, different refusal | 1 test, 8 shrinks |
| collection permitted of rooted content | retention | permits | 1 test, 7 shrinks |
| episode TTL expires a retained candidate | retention | permits | 2 tests, 10 shrinks |
| declared context consumed as a read | decision | permits, different refusal | 27 tests, 7 shrinks |

Each shrunk counterexample is the smallest plan exhibiting its fault: an
evaluation of the equal-tree sibling under `ReuseNever`; a target moved
after a permitted decision; B's producer reviewing B; a read with unobserved
coverage; any permitted selection, whose candidate is reached only through
it; an expired episode under a selection; a declared-only reliance. A mutant
that agrees with the model on every generated plan fails the suite as
`SURVIVED`.

#### Generator coverage

4000 plans at seed `20260907`: permitted 529, equal-tree pair 2376,
zero-candidate episode 1927, episode of three 957, expired episode under a
root 693, amended reference 1961, lead repair 105, divergent reuse policies
51, stale target 509, stale evaluation 593, declared-only read 247, coverage
unknown 224, retained at risk 825, promotion stood down 114. A class with a
count of zero fails the suite by name.

### Open decisions

The owning design leaves these open; the model takes each as a parameter or
reports it unsupported, and states no default:

| decision | treatment |
| --- | --- |
| evaluation reuse across registrations | `ReusePolicy` argument: `ReuseNever`, `ReuseOnMatchingCoordinates` (tree, declaration, and recorded environment equal; an unrecorded environment matches nothing). The `reuse` fixture decides one selection both ways and gets different answers; review authority is outside the policy and never reused |
| provider durable-capture guarantees | an observation per referenced version, `Pinned` or `Unpinned`, or absent; a rooted reference is `RetainedAtRisk` unless pinned, and an unversioned one is at risk as `ReferenceUnversioned` |
| retention budgets for unreferenced history | unsupported: `NoRootReaches` states a reference fact and grants nothing |
| canonical context and manifest encoding | unsupported: locators and versions are opaque identifiers compared for equality |
| initial trace-mapping scope | unsupported: no mapping from source ranges to candidates is represented |
| production core language and packaging | unsupported, and not a question a model answers |

### Unsettled design

Readings the model fixes where the sources do not; each could be chosen
differently.

- **What selection authority is.** The sources say equal trees share no
  selection authority without saying what it is. The model reads it as the
  independent review a selection may require: bound to one registration and
  tree, and by no contributor, repair authors included. Who may *select* is
  unconstrained; the selector is recorded only.
- **Unnamed negative reviews.** A proposal names the reviews it relies on. A
  changes-requested review of the chosen candidate that the proposal does
  not name does not refuse the selection. Whether one should, as a standing
  verdict does on an arc change, is open.
- **Repairs.** A repair is a proposal field naming its author and resulting
  tree, not a registration. Evidence and review must be at the repaired
  tree. Whether a repair should itself be registered is open.
- **Which reads count.** A read requirement is met by reads from episodes the
  chosen registration cites. Reads by a repairer, or by the selector, do not
  count.
- **Liveness.** Episode expiry gates no write: a registration may cite, and a
  tool may record a read for, an expired episode. What an expired episode may
  still record is not stated by the sources.
- **What a root reaches.** A candidate reaches its tree, brief, parents,
  episodes, and declared context; an episode reaches what was supplied to and
  read by it; a selection reaches its candidate, shipped tree, evaluations,
  review, and the references its reads resolved. Judgements and inferences
  reach nothing.
- **Recording a basis.** `SelectionRecorded` accepts any `SelectionBasis`;
  that it came from `evaluate` is the caller's obligation, as a decision
  basis is in the existing model.

### Comparing a future implementation

An implementation could be compared the way the differential compares arc:
replay a plan through its commands and compare, over sets, its refusals with
`refusals`, its selection record with the `SelectionBasis`, its promotion
refusal with `promote`, and its collection and retention answers with
`collection` and `retention`. That needs, on the implementation's side: a
registration command that opens no change and refuses a duplicate identity;
records for supplied context, tool reads with coverage, declarations with a
checked citation, and inferences with a source; evaluation and review records
naming the registration and tree; a selection command taking every proposal
field; a promotion that re-reads the target; a query for what a root
retains; and a stated reuse policy, since the model's answer depends on it.
A mismatch would be classified as elsewhere: implementation defect, model
defect, or an open decision above.
