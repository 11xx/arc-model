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
  `ClaimId`, `HoldId`, `FailureLabel`, `ProbeCommand`, and `EnvironmentId` are
  separate types. A revision cannot be compared with a tree, a patchset cannot
  be passed where an event is wanted, and an environment identity cannot be
  mistaken for the probe that yields it.
- **Observation is total.** `Observed a = Omitted | Observed a`. There is no
  default, no `Bool`, and no exception path from a missing observation to a
  result: a gate reading can be `Omitted` in every one of its four fields, and
  a probe that yields nothing where the decision is made is `Omitted`, never
  an identity.
- **Four gate readings are four fields.** `GateReading` carries the result,
  the coverage (`Covered` / `NeverEvaluated` / `EvaluatedOtherTree` /
  `DeclarationMoved` / `EvaluatedOtherEnvironment` / `EnvironmentUnrecorded`
  / `EnvironmentUnobserved`), the availability (`NotProduced` / `Recorded
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
  policy, authorization, one covered evaluation per required gate, and the
  finding and hold vectors that had to be empty.
- **Permission and effect are different values.** `execute :: Observations ->
  ChangeState -> Decision -> Either Refusal ExecutionPlan` re-checks the basis
  and the store's authority to act; `recordIntegration` is the only function
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
| `repair-review` | an approved first patchset plus an unread repair is a stale approval and an `OwedReview RepairUnread` |
| `unknown` / `elsewhere` / `changed` / `unreadable` / `failed` | omitted, other-tree, shape-moved, unreadable, and failing gate evidence each produce their own reading and refusal |
| `environment` | evidence from another environment, evidence recording none, and a probe that fails here are each their own coverage and refusal; a gate without a probe takes evidence from anywhere |
| `equal-tree` | equal trees with different contributor and obligation scopes decide differently; a waiver rescues the contributor; an unused debt is not named |
| `external` | an external approval authorizes where no independent review is owed and is refused as `no-approval` where one is; beside a local approval the witnessed verdict is named; a change request stands over a local approval and over a waiver; a local refusal stands over an external approval; a rejection stands; an external approval is no independent read |
| `episode` | an expired claim ends liveness, not the retained debt and evidence; the waiver still applies |
| `debt-unused` | a debt recorded beside an approval that stood anyway authorized nothing |
| `stale` / `target-moved` / `policy-moved` | a moved head refuses; a target or policy that moves between decision and execution stands the action down |
| `authority` | a check does not consult replica authority: the decision permits and the execution stands down |
| `every-ground` | a history refused on an open finding and a failing gate reports both grounds in priority order; the decision is the first |
| `permission-not-effect` | permission alone records no integration; recording lands the basis |
| `audit` | an open change refuses an audit; an approving audit needs a declared independent identity; a negative audit is open to anyone |
| `provisional` | a provisional approval gates like any other |
| `demonstration` | the model refuses a contributor reviewer; the deliberate fault permits |

### Properties

Twelve properties run over generated scenarios; seeds and case counts are
recorded in the README.

| property | statement |
| --- | --- |
| integratable permits | every history the generator marks integratable permits |
| mutation flips | each one-invalid-transition mutation of an integratable history either refuses or stands down at execution |
| basis grounded | every fact in a permitted basis is present in the ledger and observations; an external authorization names an approval of exactly the basis head; the consumed finding and hold vectors were empty |
| unknown never permits | omitted, unreadable, other-tree, shape-moved, other-environment, environment-unrecorded, and probe-failed evidence never permit |
| moved basis stands down | a target or policy moved between decision and execution produces `RefusedBasisMoved`, never a reused basis, unless authority is withheld, which is refused first |
| waiver exact | a named waiver is bound to the basis patchset and is the newest for it |
| refusal stands | a changes-requested or comment-only verdict on the current patchset is never permitted |
| read needs a reader | a fulfilled read implies a declared, non-contributor reader recorded on the shipped revision |
| debt unused | a debt bound to an approved patchset is reported as recorded debt, not as an authorization input |
| negative audit does not approve | a negative audit that fulfils the read leaves the approval flag false unless an independent approving answer exists |
| decision is the first ground | `decide` permits exactly when `refusals` is empty and otherwise refuses on its first element |
| grounds are facts | every ground `refusals` returns names a fact the history and observations hold, checked constructor by constructor; execution-only refusals never appear |

### Mutants

Twelve deliberate faults; each must be killed, and each divergence must be of
the predicted class. Distinguishing a different refusal from a permission is
deliberate: dropping one ground of a refusal is a real fault even when another
ground answers.

| fault | channel | predicted divergence | killed (seed 20260907) |
| --- | --- | --- | --- |
| contributor identity ignored | decision | permits, different refusal, different basis | 45 tests, 7 shrinks |
| gate matched by name | decision | permits, different refusal | 80 tests, 4 shrinks |
| unknown treated as success | decision | permits, different refusal | 8 tests, 5 shrinks |
| authorization reused after its basis moved | execution | permits, different refusal | 26 tests, 10 shrinks |
| fulfilled implies approved | coverage | different value | 13 tests, 1 shrink |
| latest debt applied to every patchset | decision | permits, different refusal | 34 tests, 7 shrinks |
| debt clears a refusing verdict | decision | permits, different refusal | 5 tests, 7 shrinks |
| later audit rewrites the integration basis | historical | different value | 3 tests, 5 shrinks |
| unreadable evidence counts as review | decision | permits, different refusal | 45 tests, 4 shrinks |
| external approval counts as independent review | decision | permits, different refusal, different basis | 9 tests, 7 shrinks |
| environment ignored | decision | permits, different refusal | 49 tests, 7 shrinks |
| authority ignored | execution | permits, different refusal | 72 tests, 4 shrinks |

A surviving mutant is reported as a failure; the suite exits non-zero. The
reason a mutant may legitimately exhibit more than one class is the fault
itself: a ground dropped from a refusal surfaces as a permission when nothing
else stands in the way, and as a different refusal when something does. The
external-approval fault also surfaces as a different basis: where an external
approval already authorizes, the fault names a witnessed verdict instead.

### Demonstrated counterexample

The smallest demonstration is the unit fixture, not a shrunk random case. The
history is one patchset authored by `author`, with `author` also recording an
approving verdict:

- model: `Refused (RefusedSelfApproval (EventId 2) (ActorId "author")
  (fromList [ActorId "author"]))`;
- `contributor-identity-ignored` mutant: `Permitted`, because it drops the
  contributor comparison from the independence rule.

The mutant's property also finds its own smallest random counterexample (45
tests, 7 shrinks): a one-patchset history whose verdict is recorded under an
assumed identity, under a policy that requires independence. Both are
reported by the suite; neither is committed as a golden string, because the
fixture pins the behaviour and the shrunk case pins the shrinker.

### Generator coverage

The coverage sampler generates 4000 scenarios and fails if any required class
is never reached. At seed `20260907` the counts are: permitted 349, waived
127, externally authorized 27, external refused 485, self-approval refused
116, gates refused 335, gate failed 31, environment refused 137, verdict
stands 818, head moved 820, target moved 68, policy moved 63, authority
withheld 61, debt unused 100, unknown observation 521, audit fulfilled read
92, audit negative not approved 19, episode expired 1945, equal-tree
contributor variation 2026. A class with a count of zero is reported by name,
so the suite cannot pass on trivial histories.

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
| `9b6ac80`, `745a27c`, `fb1227b` | operator policy layered with project policy; conflicting gate declarations refused | no change to a modelled answer: the model takes the effective policy and declaration set as observations; a conflicting declaration set is refused before any decision is asked, listed unsupported |
| `e8e16a3` | `done` with no gate declared reports a check state | already modelled: no required gate yields an empty gate basis |
| `a6a04a8` | a contribution is recorded ready to send instead of merged | no change to the decision; the effect kind is unsupported |
| `4eb7200`, `82cfcbb`, `6f4999b`, `081b5d8`, `96f3c17`, `3102eb3` | already-contained heads, checkout guards, squash rollback | Git effects, unsupported |
| `4f637de`, `d330b54`, `da289f5`, `0f87cff`, `51e3f4d`, `b20300a`, `11d1e15` | session identity detection and its reader | no change: identity collapses to the declared/assumed boolean |
| `fec3f1c`, `a138b98`, `3cc953f`, `ceaa01e`, `5b6fe2f`, `a26542a` | bundles, journal exchange, patchset links, store stamps, build | no effect on the decision |
| `fc5801b`, `2309683`, `5e8bac7`, `8e4866c`, `1f567a5`, `fed2648`, `630dd30`, `ed1477b`, `4076eef`, `f9fcbd9`, `54c9fe2`, `8c4df11` | workspace views, journal locking, docs | no effect on the decision |

## Unsettled design

Points where the model fixes a reading that production or a future slice may
still choose differently. Each is a deliberate choice, not an oversight.

- **Refusal priority.** The model checks findings before authorization, and
  authorization before gates, and holds last. Production renders the first
  blocker by its own ordering; the model's ordering is stated rather than
  derived, and a reader comparing refusals should compare the facts, not only
  the first tag. `refusals` returns every ground so that comparison is
  possible.
- **A moved head is its own ground.** The model names `RefusedHeadMoved` and
  still evaluates authorization and gates against the recorded patchset.
  Production folds a moved head into approval validity and gate lookup, so
  it reports no valid approval and gates not green instead. The facts agree;
  the vocabulary does not.
- **External beside local.** When a witnessed approval and an external
  approval both stand, the model's basis names the witnessed verdict.
  Production records both in its authorization basis.
- **Tree before environment.** Coverage reads the tree before the environment,
  so evidence from another tree in another environment is reported as
  other-tree. Production tests both and reports neither first.
- **Authority at execution.** Production refuses a store without integration
  authority when `integrate` starts, before readiness; `check` never asks.
  The model refuses it in `execute`, before comparing the basis, and never in
  `decide`.
- **Debt kind derivation.** `nothing-read`, `contributor-only`, and
  `independent-review` are derived; `merge-resolution-unread` and
  `repair-unread` are accepted only when declared, because only the caller can
  say which of the two a ledger sees identically. Whether the ledger itself
  should distinguish them is open.
- **Coverage after a repair.** A negative audit fulfils the read and leaves
  its findings open. A repair after that audit starts a fresh obligation in
  the model. Whether the fulfilled read should survive a repair is a policy
  question the model does not answer.
- **Approval beside a later negative audit.** `approved` reports
  whether an independent approving answer exists. An independent approval on
  the shipped patchset makes it true even after a negative audit; the audit's
  verdict remains its own field. Whether a later negative audit should
  withdraw the approval flag is open.
- **Policy motion.** A policy that changes between decision and execution
  produces `RefusedBasisMoved` rather than a re-decision. Re-deciding under
  the new policy would be a different action, with a different basis.
- **Contested verdicts.** The model treats more than one active tip as
  contested and refuses. It does not model the repair of a contested chain
  beyond the arrival of a single superseding verdict.
- **Claim episodes.** A claim's expiry is modelled as a fact about liveness
  only. Stage budgets, staleness, and claim generation are not modelled.

## Deferred out of this package

Both are recorded here so a reader does not read the package's scope as a
claim about them:

- **The candidate protocol.** The proposed challenge/evaluation/selection
  semantics is a separate model. This package models existing arc
  authorization only, and the candidate rules must not be added to it by
  accident.
- **The differential.** A comparison that runs the same histories through the
  arc binary and the model is the next deliverable. A quiet differential run
  will be supporting evidence, not proof of equivalence.

## Known unsupported semantics

- **Git effects.** Synthesizing a merged tree, verifying that a merge commit's
  tree is the evaluated one, closing a change the target already contains,
  the checkout guards, squash rollback, and the reset after a mismatch are
  outside the model. The evaluated tree and the target before are
  observations, and the `needs-rebase`, `merged-tree-unevaluated`,
  `branch-missing`, and `fork-branch` blockers are not modelled.
- **Durability, locking, races, crash recovery.** A pure model cannot
  establish them; they stay independent OS-level tests.
- **Conflicting gate declarations.** Two policy layers declaring one gate with
  different commands or probes make production refuse to evaluate at all. The
  model takes an effective, unconflicted declaration set as an observation.
- **Evidence on a dirty tree and its waiver.** Production counts a run
  recorded on a dirty tree only under a waiver for that revision; the model's
  verifications carry no dirtiness.
- **Ledger replay of environments.** Where production evaluates without a
  checkout, evidence carrying any identity counts. The model characterizes
  the live decision, where the identity must be observed here and equal.
- **External change-request findings.** Production carries them on the
  external verdict; the model's external decision carries none, and the
  change request itself is the refusal.
- **Contribution mode.** Whether a permitted integration merges or is
  recorded ready to send is an effect kind the model does not name.
- **Acceptance probes.** The `acceptance-probes-not-green` blocker is not
  modelled.
- **Provenance categories.** `actor_source` values (`flag`, `env`, `derived`,
  `git-fallback`) collapse to a declared/assumed boolean. `require_declared_actor`
  is modelled for the invoker only.
- **Forks, worktrees, retention, bundles, journal, changelog projection,
  replica exchange.** None are modelled; authority is an observation.
- **Review-map advisories.** `reviewer-behind-final-patchset`,
  `no-independent-reviewer`, and the other advisories are not modelled; they
  never block, and the model's job is the blocking decision.
- **Dependency status.** `Observations.blockedBy` names blockers; how a chain's
  readiness is computed is not modelled.
