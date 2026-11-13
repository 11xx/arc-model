# Findings for arc documentation

Quotes below are exact sentences, with whitespace folded from the captured text.
They are recorded in arc-model because this task forbids writes to arc or its journal.

## D1. Can an assessed verdict discharge ineligible-review? (C22, unsettled)

Source: [topics/debt-obligations.txt](topics/debt-obligations.txt).

> An audit without an assessment, with an `ineligible` one, or whose binding is not `bound` is recorded, says why, and is listed beside the obligation, which stays open; a verdict recorded since clears it only with an eligible, bound assessment of its own (`arc review --assessment`).

Source: [topics/debt-recovery.txt](topics/debt-recovery.txt).

> Outside assessed ladder clearance, ineligible-review additionally requires an audit that approves or requests changes with an eligible, bound assessment.

## D2. Is candidate verify success raw or budget-qualified? (C42, unsettled)

Source: [help.txt](help.txt).

> Exits 0 when every gate run passes and 1 otherwise.

Source: [topics/gates.txt](topics/gates.txt).

> A command outcome remains pass in the ledger even when its run_ms exceeds the budget in force.

Source: [topics/candidates.txt](topics/candidates.txt).

> Execution and selection judge timing against the effective budgets in `arc guide gates`.

## D3. Does the global boundary exclude ladder capability? (C40, contradictory prose)

Source: [topics/boundaries.txt](topics/boundaries.txt).

> arc never scores the coordinates a debt records, joins them against a roster, or orders two models against each other.

Source: [topics/debt-clearance.txt](topics/debt-clearance.txt).

> With an applicable ladder, arc owns capability. At the read's basis time, it selects the latest version whose `effective_from` is at or before that instant.

Source: [topics/debt-clearance.txt](topics/debt-clearance.txt).

> Findings eligibility requires the reader rank to meet every agent author's floor.

## D4. Does danger alone forbid contributor approval? (C4, inherited unsettled rule)

Source: [topics/debt-review.txt](topics/debt-review.txt).

> A change touching a declared path needs a verdict from somebody other than its author; elsewhere a self-recorded verdict satisfies the gate.

Source: [topics/debt-recovery.txt](topics/debt-recovery.txt).

> Where `forbid_self_approval` is off, an approving verdict from the identity that wrote the work is recorded rather than refused, and `arc review` and `arc audit` both name the match: who it was recorded as, which patchset that identity wrote, and whether arc assumed the identity rather than anyone declaring it.

## D5. Which eligible answer refuses an assessment/2 debt declaration? (C21, unsettled)

Source: [topics/debt-obligations.txt](topics/debt-obligations.txt).

> An `eligible` assessment is refused on this kind, because there is no debt to record.

> In `/1` qualifiers are present exactly when the independence is `ineligible`; in `/2` a file that clears is eligible on both answers, names no qualifier and names its reviewer's effort, and one that does not clear names a qualifier.

D1 retains the audit-only ordinary model reading; no verdict assessment is represented.
D2 retains the documented execution budget requirement but leaves the CLI exit interpretation open.
D3 scopes ordinary model-match rules separately from the unmodeled assessed ladder.
D4 retains danger plus forbid_self_approval as the model choice.
D5 does not infer assessment/2 behavior from the model, which represents /1 only.
