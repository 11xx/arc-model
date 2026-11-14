# Findings for arc documentation

Quotes below are exact sentences, with whitespace folded from the captured text.
They are recorded in arc-model because this task forbids writes to arc or its journal.

## The b405104a findings

| finding | status at 510e3f0a | the sentences that settle it |
| --- | --- | --- |
| D1, an assessed verdict clearing ineligible-review | Closed | debt-obligations: "It clears with a read recorded since the declaration that approves or requests changes under an assessment of its own with `independence: eligible`: an audit (`arc audit --assessment <file>`) or a verdict on the patchset that shipped (`arc review --assessment <file>`), by a reader who is also independent of the contributors and whom the assessment describes." debt-recovery: "An ineligible-review debt also asks the read, audit or verdict alike, for an eligible, bound assessment of its own" |
| D2, candidate verify's exit status | Closed | `arc candidate verify --help`: "Exits 0 when every gate run passes and the budget judge of `arc guide gates` accepts its command time, and 1 otherwise: an over-budget or unmeasured pass is recorded as a pass, its line names the refusal, and selection refuses it as an evaluation." |
| D3, the global boundary and ladder capability | Closed | boundaries: "arc holds no ranking of its own: it never scores the coordinates a debt records, and joins or orders models only against the dated ladder a destination commits for assessed clearance (`arc guide debt-clearance`)." |
| D4, danger alone and self-approval | Closed | debt-review: "Under `forbid_self_approval`, a change touching a declared path needs a verdict from somebody other than its author. Elsewhere authorship refuses no approval, but assessed clearance gates only a clearing one, which an author's own read never is under a ladder (`arc guide debt-clearance`)." |
| D5, which eligible answer refuses an assessment/2 declaration | Closed | debt-obligations: "An assessment under which the named read would discharge the debt is refused on this kind, and one under which it would not is recorded: without `review_clearance` its `independence` decides, under it the read's clearance (`arc guide debt-clearance`) does, and a judgment arc cannot establish records the debt." |

`arc integrate --help` and `arc debt --help` at b405104a also said of
ineligible-review "arc never derives it", beside debt-clearance's derivation
under assessed clearance. Both now read "arc derives it only under
`review_clearance = "assessed"`, for an approval that finds without clearing."

## E1. Which `[budget]` keys are enforcement keys? (C31, unsettled)

Source: [topics/gate-costs.txt](topics/gate-costs.txt).

> Every required integration gate needs a budget when enforcement keys exist in that table; a landing-only table requires no individual budgets.

> Total bounds the worst-case integration suite and is enforced.

No route defines "enforcement keys". At b405104a, [topics/gates.txt](../b405104a/topics/gates.txt)
said "Every required integration gate needs a budget when that table exists."
A table holding only `raise`, `raise_per` or `exclude` required every budget
then; whether it does now is not stated.

## E2. Does a change head's own `[confine]` govern its commands before it lands? (C43, unsettled)

Source: [topics/gate-confinement.txt](topics/gate-confinement.txt).

> Project commands run under the committed destination's declaration: gates, selectors, environment probes, preparation, slot identity, invalidate and warm commands, changelog renderers, and commands in acceptance and publication scratch checkouts.

> The checkout being evaluated cannot select its own authority.

> A change can adopt confinement when the destination has none, or require enforcement, but cannot widen an existing destination's roots.

The first two read as the destination's table alone governing a change's
commands; the third reads as a head's narrowing table taking effect for the
change. Neither says whether a head that widens the roots is refused or has
its widening ignored, nor which declaration a head's adoption changes for
evidence identity before the change lands.

## E3. Does readiness report a reserved commit, and which patchsets does integration check? (C44, unsettled)

Source: [topics/change-integration.txt](topics/change-integration.txt).

> `snapshot` and `integrate` refuse a patchset containing a commit whose raw author or committer address uses .invalid, .example, .test, .localhost, example.com, example.org or example.net, including subdomains.

> Integration checks recorded patchsets too, including provisional preparation and multi-change landings.

Source: [help.txt](help.txt), `arc integrate --help`.

> Refuses recorded patchsets with reserved-domain author or committer addresses; see `arc guide change-integration` for the domains and re-authoring.

`arc check --help` lists no blocker for it, so a change recorded before the
guard can read ready and then be refused by `integrate`. "Recorded patchsets"
does not say whether only the patchset being shipped or every patchset the
change recorded is checked.

## E4. Can a verdict answer an ineligible-review debt declared at integration? (C22, unsettled)

Source: [topics/debt-obligations.txt](topics/debt-obligations.txt).

> It clears with a read recorded since the declaration that approves or requests changes under an assessment of its own with `independence: eligible`: an audit (`arc audit --assessment <file>`) or a verdict on the patchset that shipped (`arc review --assessment <file>`), by a reader who is also independent of the contributors and whom the assessment describes.

A debt declared by `arc integrate --debt` is recorded at integration, so a
verdict recorded since it would be recorded on a closed change. No route says
whether `arc review` records on an integrated change. The sandbox replay
observed arc refuse it ("change ... is integrated; event is open-only"), which
makes the verdict route reachable only for a debt declared before integration;
the guide does not say so.

## E5. Where does integration's target check live? (C20, open boundary)

Source: [topics/identity-options.txt](topics/identity-options.txt).

> Authorization boundaries start fresh mutable observations. Movement guards take independent observations. Readiness target heads and merge trees must agree with the destination and tree observed by the decision.

This integration requirement appears only in the `ARC_TRACE` coverage
paragraph. Neither change-integration nor `arc integrate --help` states it,
and no route names the refusal or exit status a disagreement produces.

E1 to E4 leave the contract unsettled with their readings; E5 is settled by
reading a disagreement as a basis that differs, so nothing is written. The
model realizes none of the unsettled readings.
