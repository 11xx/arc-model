# Findings for arc documentation

Quotes below are exact sentences, with whitespace folded from the captured text.
They are recorded in arc-model because this task forbids writes to arc or its journal.

## The 35f9501d findings

All six findings from 35f9501d are closed by the 954f2334 captured text:

| finding | status at 954f2334 | the sentences that settle it |
| --- | --- | --- |
| E1, which `[budget]` keys are enforcement keys (C31) | Closed | gate-costs: "A [budget] table enforces when it has no `landing` key, the empty table included, or when beside `landing` it sets `total`, `raise`, `raise_per` or `exclude` to other than its default; `landing` alone, or with those keys at their defaults such as an empty `exclude`, does not. An enforcing table in any layer of the effective suite makes every required integration gate need a budget, in every profile. Per-gate budgets without such a table require none of the others." |
| E2, whether a change head's `[confine]` governs before landing (C43) | Closed | gate-confinement: "For an open change, the declaration in force is the destination's combined with the operator's, and the change head's committed table counts only in two ways. When neither the destination nor the operator declares a table, the head's table governs, roots and `required` as written. Otherwise the head's roots are ignored, never refused, whether they widen or narrow, and `required = true` on any side requires enforcement, which `required = false` elsewhere cannot lift. ... The declaration in force, adopted or required by the head included, is what a gate's evidence identity and receipts carry before the change lands..." |
| E3, readiness blocker and patchset scope for reserved commits (C44) | Closed | change-integration: "Integration, provisional preparation and multi-change landings check the recorded patchset that ships, the newest, over its `base..head` and the target's `..head`; earlier patchsets are not read. ... Readiness reads the same: `check` and `status` list `reserved-identity` (check exits 21) with the refusal's own words, and the next step names the re-authoring and `arc snapshot`." `arc check --help` adds `21  reserved-identity`. |
| E4, verdict clearing of an `integrate --debt` ineligible-review debt (C22) | Closed | debt-obligations: "`arc review` records only on an open change and `arc audit` only on an integrated one, so a debt `arc debt` declares before integration clears with a verdict recorded since on the patchset that then ships, or an audit after integration, and a debt `arc integrate --debt` declares clears only with an audit." |
| E5, home and refusal of integration's target check (C20) | Closed | change-integration: "Both readings of readiness must have read the target revision the decision observes and, unless a contribution declaration hands the change to a receiver, the merge tree it observes. A disagreement there, or gate, policy or budget declarations differing from the basis, refuses with exit 1 and \"integration target, merge tree, gate or policy configuration changed while preparing the merge; nothing was written; re-run once the worktree has settled\", and writes nothing." `arc integrate --help` and `identity-options` cross-reference it. |
| E6, placement and version of the waited-CPU condition (C31) | Closed | gate-costs now holds the canonical busy-host rule naming "Version 2, the current rule", with all four conditions including "a tree clock covering the run's waited user and system CPU at a share at most 5% below the reference's own share", and "Version 1 holds the same thresholds without the coverage condition." `gates` and `change-gates` both cross-reference `arc guide gate-costs`. |

## F1. Budget suspension scope in `arc verify --help`, `rules-rounds`, and candidates (C31, C42, unsettled)

Source: [topics/gates.txt](topics/gates.txt).

> An overrun passes only under the busy-host rule of `arc guide gate-costs` or a budget suspension, below.

> While one covers a gate, a passing run over its budget is accepted wherever integration evidence is judged, as of the moment of judgement: a receipt recorded earlier counts, and once the suspension ends the same receipt is refused again. ... Publication judges strictly.

Source: [help.txt](help.txt), `arc verify --help`.

> An over-budget raw pass exits 1 unless the busy-host rule accepts it; a refusal needs --rerun.

Source: [topics/rules-rounds.txt](topics/rules-rounds.txt).

> Recording a brief or a budget suspension (`arc gates suspend`) is a lead's. An unset role is `lead`, with full access.

Source: [help.txt](help.txt), `arc candidate verify --help`.

> Exits 0 when every gate run passes and the budget judge of `arc guide gates` accepts its command time, and 1 otherwise

Three gaps remain around budget suspensions:

1. `arc verify --help` was not updated to mention budget suspensions beside the
   busy-host rule, though `topics/gates.txt` states that verify accepts an
   over-budget pass under an active suspension (`accepted over budget`).
2. `topics/rules-rounds.txt` restricts `arc gates suspend` to the lead role
   without stating whether `arc gates resume` is also lead-only or open to any
   role.
3. `topics/gates.txt` scopes suspension acceptance to "wherever integration
   evidence is judged" and states "Publication judges strictly", while
   `arc candidate verify --help` delegates to "the budget judge of `arc guide
   gates`" and `topics/candidates.txt` does not mention suspensions — leaving
   open whether candidate verification, selection, and promotion honour an
   active budget suspension.

## F2. Invalid gate trailers on `arc check` and `interface_budget` interaction with `[budget] total` (C31, C45, unsettled)

Source: [topics/contributions.txt](topics/contributions.txt).

> Change-size: interface selects a gate's declared `interface_budget`; any other value is refused

> Invalid, empty, multiline, mixed, or excessive (> 3 distinct) declarations refuse `arc verify`, `arc check`, `arc integrate`, and `arc land`, and report as `gate-trailers-invalid` in `arc doctor`.

Source: [topics/gates.txt](topics/gates.txt).

> Unknown `.arc/gates.toml` keys refuse. `interface_budget` requires `>= budget`; `invariants` reads target's list and binds reuse (`arc guide contributions`).

Three points are left unstated:

1. Neither `arc check --help` nor `topics/exit-codes.txt` lists a blocker name
   or exit code for invalid gate trailers (unlike `reserved-identity`, exit 21),
   so it is unstated whether `arc check` emits a JSON blocker or refuses
   outright with exit 1 like conflicting gate declarations.
2. No route states how `interface_budget` interacts with `[budget] total`:
   whether declaration-sum validation checks `budget` alone or also
   `interface_budget`, and whether a change declaring `Change-size: interface`
   is allowed to exceed `total` or still bound by it.
3. No route states whether `Change-size: interface` on a change whose gates
   declare no `interface_budget` is a no-op (using ordinary `budget`) or
   refused.

## F3. Earlier-patchset waiver retirement standing vocabulary (C6, C27, unsettled presentation)

Source: [topics/debt-recovery.txt](topics/debt-recovery.txt).

> A debt stands in one of three states, and every view that shows it reads the same one. `declared`: the change has not integrated, so nothing is owed yet and no review has answered it. `owed`: the change integrated and no eligible review has answered it. `discharged`: one has, and the debt names it.

> When a guarded integration records an independent approval of the shipped patchset as its authorization, a waiver bound to an earlier patchset stays in the event history and creates no shipped obligation. The approval must have receiver review authority and satisfy applicable clearance. An assessment that explicitly denies clearance cannot retire the earlier waiver. A waiver used to authorize integration remains an obligation of the shipped patchset, with its declared extent.

The substantive rule is settled: an earlier-patchset waiver is retired by a
guarded integration authorized by an independent approval of the shipped
patchset (without an assessment denying clearance), so it creates no shipped
obligation and is not `owed`. What the text leaves unstated is which
`debt_standing` value (or null/absent) JSON views report for a change whose
only historical debt was retired this way, since `declared` is defined as
"the change has not integrated" and `discharged` as "an eligible review has
answered it" (which an unassessed approval cannot do for an `ineligible-review`
debt on the shipped patchset).

## F4. Closed-change `[confine]` table: current destination vs closure-time target (C12, C43, unsettled)

Source: [topics/gate-confinement.txt](topics/gate-confinement.txt).

> A closed change uses its destination branch's current table.

Source: [topics/change-integration.txt](topics/change-integration.txt) (C12).

> A closed change's gate and policy declarations are the target's at the revision the closure recorded as where the target stood, plus the gates its judged head adds...

The two passages disagree on a closed change whose destination branch changed
its `[confine]` table after closure: `gate-confinement` says it uses the
destination branch's current table, whereas `change-integration` pins project
gate declarations to the closure's recorded `target_before` revision.

## F5. Stale trailer prose in `arc integrate --help` and `arc check --help` (C10, C39, documentation drift)

Source: [help.txt](help.txt), `arc integrate --help` (top summary vs `--no-trailers`).

> Contribution trailers are advisory only: a missing asserted line, or a role line carrying a placeholder or a session id, is advice to rewrite with arc rewrite trailers before integration. Review credit stays in the ledger.

> Skip automatic contribution trailer stamping on this integration. By default (`[trailers] auto = true`), fast-forward integration stamps applicable missing projected role trailers (`Planned-by`, `Implemented-by`, `Reviewed-by`, `Orchestrated-by`) over `target..head` via a `role_additions` rewrite applied atomically with the target ref move (no-op when nothing is missing, respecting `commit.gpgsign`, refusing commits shared with other branches, tags, or stacked open changes, and moving only source, target, and required `refs/arc/*` pins)...

Two sentences in the top paragraph of `arc integrate --help` contradict the new
`--no-trailers` option and `topics/contributions.txt`:

1. "Review credit stays in the ledger" is stale: `arc trailers` and
   auto-stamping now project `Reviewed-by` from qualifying pre-integration
   `Approved` verdicts (only post-integration audits stay ledger-only).
2. "Contribution trailers are advisory only" sits beside a new default
   integration-time refusal (enforced even in `--dry-run`) when `[trailers]
   auto = true` would auto-stamp commits reachable from another branch, tag, or
   stacked open change. `arc check --help` also still advises `--from <rev>
   --append <line>` without mentioning `--sync` or `Reviewed-by`.

## F6. Finding `--commit` survival rule omitted from `arc resolve --help` (C10, placement / open edge cases)

Source: [topics/change-commands.txt](topics/change-commands.txt).

> A `resolved` disposition citing `--commit` stands when that commit (after recorded rewrites) is an ancestor of the head or matches a non-merge commit in `base..head` by exact Git patch-id, and the fix survives at the head without being reverted; otherwise the finding remains open.

`arc resolve --help` states only that `resolved`, `accepted-risk`, and
`obsolete` release a blocking finding and does not mention the `--commit`
ancestry/patch-id/survival condition. Neither route states whether a later
`resolved` disposition without `--commit` supersedes a non-surviving
`--commit` disposition, or whether the survival rule applies only to open
review findings or also post-integration audit findings.
