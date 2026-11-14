# arc-model contract

The rules the model answers to. Each clause states a rule of arc's
integration authorization, whether the rule is settled, where it comes
from, and the model functions that realize it. The model is checked against
this text; arc's implementation is not a source for it.

## How to read a clause

- **Rule** is what a history, together with what is observed when the
  question is asked, must answer.
- **Status** is *settled*, or *unsettled* with every reading stated. A
  clause is unsettled where arc's documentation at the comparison revision
  is silent or where two passages of it disagree. An unsettled clause names
  the reading the model takes; that reading is a choice, not a finding.
- **Source** names where in arc's documentation at the comparison revision
  the rule comes from — the guide `arc` prints with no arguments, by its
  section heading, a command's `--help`, or arc's `README.md` — or says the
  contract makes the decision itself. Where the operator has ruled on what
  a passage of the guide means, and recorded the ruling in arc's journal,
  the ruling is cited beside the passage it reads.
- **Realized by** names the model functions that implement the rule. Each
  of them carries a comment naming the clause.

A disagreement between a clause and the model is recorded in `REPORT.md`,
under "Open decisions against the contract", and is adjudicated there, not
by editing either side to match.

## Scope

The contract covers the authorization of an existing arc revision, the one
`comparisonRevision` names. The candidate protocol — registration,
evaluation, selection, and promotion — has its own model (`Arc.Candidate.*`)
with its own open decisions in `REPORT.md`, and is outside this contract.
The patchset a promotion produces is not: it is reviewed, waived, and
integrated as any other (the guide, "The history model"), so every clause
here reads it as a patchset like any other. Git effects, durability,
locking, forks, queues, and the other items `REPORT.md` lists under "Known
unsupported semantics" are outside the contract too.

C31 to C44 also state documented authorization requirements whose clocks,
host administration, kernel confinement, retained Git objects, commit bytes
or richer review records the pure model cannot observe. Each clause
distinguishes its modeled decision from its unrealized protocol or external
boundary. A permission from the model
assumes those external requirements were satisfied; it is not a complete
readiness certificate for those configurations.

History rewrites and what protects shared history belong to Git effects and
are outside the contract, with their documentation's refusals ("Refusals
happen before any ref move"; `--include-shared` "grants permission without
changing the default range"; a `refs/arc/keep` pin "follows the successor").
What a rewrite means for an approval, a waiver and a patchset is not outside:
C1, C5 and C6 state it.

Replicas bring three rules of their own: which imported reviews count
(C24), what a replica without authority may prepare (C25), and how the
authority accepts a delivered change (C26). The contract states them; the
model does not realize them yet, and `REPORT.md` says why under "Deferred
out of this package".

## Clauses

### C1. Patchset identity

**Rule.** A patchset is an immutable snapshot of a change's branch: a base,
a head revision, the head's tree, the contributors whose work it carries,
and the brief in force when it was recorded. Each contributor is carried at
the coordinate the ledger recorded for it, model included. Verdicts,
waivers, and probe evidence bind to a patchset, never to a branch name. The
latest recorded patchset is the one an integration would ship. A change
with no patchset has nothing to authorize and is refused.

A clean `arc rebase` — the mechanical replay arc performs itself, in a
repository without the project's configuration, reading the ref Git
updated — records a fresh patchset of the patchset whose head it replayed,
carrying every contributor the earlier patchset carries at its recorded
coordinate, model included, and naming exactly the tip that replay wrote.
Where no matching patchset exists, completed bound-run attribution may be
established at the original head before replay (C38). The replaying session
is not the replayed patchset's implementer. A replay
that falls back to `git rebase`, or stops for a person to resolve, records
ordinary work, whose author follows C38; `--contributors` and `--solo` decide any
replayed patchset's contributor set, a member the replay carries over
keeping its recorded coordinate and one it does not carry credited as
declared.

**Status.** Settled. The refusal of a change with no patchset is a decision
the contract makes: approvals bind to patchsets, so without one nothing can
be approved. The guide lets a patchset's contributors be amended until the
first verdict on it; after that they are fixed, which is all C4 reads.
A snapshot after a rewrite that invalidates approval records a fresh
patchset even when the mapped head already equals the branch; it grants no
approval. An implicit verdict refuses while the approved and mapped heads
differ; an explicit historical patchset verdict can be recorded and stays
stale. C39 also permits complete role-addition approval carry. The model has no rewrite map, so its fresh patchset identity states
the authorization boundary without the mapped-head recording protocol.
Recording a patchset while another actor holds a live claim on the change
requires declared contributors or `--solo`; that is a condition on
recording a patchset, not on authorizing one, and the model's ledger holds
only patchsets that were recorded. The contributor coordinates a patchset
carries are recorded facts, like its revision; the model states a replay's
inheritance by reading the replayed patchset's recorded coordinates, and
the replay protocol itself is outside it.

**Source.** The guide's "Run a change" and "Rules that change what you do",
the README's "One change, end to end", and current
arc guide change-integration, arc guide debt-review,
arc snapshot --help and arc rebase --help. The current guides describe
mechanical inheritance, ordinary bound-run attribution and the live-claim
declaration requirement; C38 states the complete acquisition rule.

**Realized by.** `effectiveContributors`, `latestPatchset`,
`patchsetById`, `evaluateDeclared`.

### C2. The observed head

**Rule.** An integration is refused unless the branch head observed when
the question is asked equals the latest patchset's head: any new commit
invalidates what was decided about the old head. A change whose branch is
gone has no head, and is refused on that ground rather than compared with
anything.

A closed change is judged where it closed: at the head its closure
recorded, or at its latest patchset's head where the closure recorded none.
Its branch and its target are not read, so neither a missing branch, a
commit after the closure, nor a target that moved raises a ground, and its
gate evidence answers at that head's own tree (C3), under the declarations
C12 reads for a closed change. It is still refused as closed (C10).

**Status.** Settled. arc reports a moved head as no valid approval and gates
not green, since both bind to the head; the model names the moved head as
its own ground. That is vocabulary, and C23 makes it presentation. The
model's closures record no head, so it judges every closed change at its
latest patchset's head; a closure recording another head is a fact it
cannot state.

**Source.** `README.md`, "One change, end to end" (a new commit makes the
approval stale); the guide, "Rules that change what you do" (any new commit
makes the approval stale), "Run a change" ("A closed change is judged at
the head its closure recorded, or at its newest patchset's when the closure
recorded none"; "`status`, `show`, and `check` read neither its branch nor
its target, so deleting the branch or moving the target after closure
leaves the head its verdict and gate evidence are read against where it
was"), and "Exit codes" (6, a missing branch).

**Realized by.** `evaluateDeclared`, `execute`.

### C3. The exact evaluated tree

**Rule.** The tree an integration would ship is the one gate evidence must
answer. Where the head already contains its target, that is the head's own
tree. Where the head is behind a target that moved and the two merge
cleanly, it is the merge's tree, which neither branch committed, and a
change none of whose required gates was evaluated at that tree is refused
(`merged-tree-unevaluated`). Where the merge does not resolve, there is no
single tree to evaluate and the change is refused as needing a rebase.

The integration shape resolved for the target decides whether a head behind
it may ship as a merge at all. Under `no-ff` the integration is a merge
commit of the target and the approved head, and ships the merge's tree as
above. Under `ff-only`, the built-in shape, the target must be an ancestor
of the approved head or already contain it, so a head behind a target that
moved is refused as needing a rebase even where the two merge cleanly. The
shape resolves from the `--shape` flag, the operator's defaults, the target
project's defaults, the user's configuration, and the built-in `ff-only`,
in that order; the model takes the resolved shape as part of the policy it
observes.

**Status.** Settled. Under `ff-only`, the check retains
`merged-tree-unevaluated` beside `needs-rebase` when the merge lacks evidence;
exit 11 for the rebase precedes exit 14. The merge's gate grounds remain
independent (C23).

Which history an integration then writes — a fast-forward, a merge commit,
or nothing because the target already contains the head — is a Git effect,
outside the contract.

**Source.** The guide, "Rules that change what you do" (gate evidence binds
to a tree; a change behind its target is refused with
`merged-tree-unevaluated` until the merge is evaluated), "Run a change"
("Under ff-only, the observed target must be an ancestor of the approved
head, or already contain it"; "Integration performs no automatic rebase
under ff-only"; "`--shape no-ff` creates a merge commit with the observed
target and approved head as its parents"), "Files" (the style precedence;
`[defaults.integration] shape`; `[integration] shapes`), and "Exit codes"
(11, "when the target conflicts or ff-only ancestry requires rebasing";
14; the explicit `ff-only` blocker set in "Rules that change what you do");
`arc integrate --help` and `arc check --help`, `--shape`; `arc verify --help`,
`--against`. The same passage ends: "The rule names no integration shape:
under `ff-only`, where no merge ships, a change behind its target still lists
`merged-tree-unevaluated` beside `needs-rebase` in `check --json`, and
`check` exits 11 for the rebase before it would exit 14."

**Realized by.** `evaluateDeclared`, `gateEvidence`.

### C4. Contributors and reviewer independence

**Rule.** The ledger, never commit trailers, says who held which role. The
effective author of an event is the subject it was recorded on behalf of,
otherwise its actor. C38 states how completed bound runs can supply a
recorded contributor set at snapshot time. A patchset's contributor set is the set declared for it
when nonempty, otherwise its effective author alone; that set is its
authorship, and the patchset's implementer is the identity of that
authorship. Its planner is the plan's recorded planners, else an asserted
`Planned-by`, else the brief's recorder; its orchestrator is the invoker
recorded beside an `--on-behalf-of` subject; its integrator is the actor of
`arc integrate`, never the subject that command was invoked on behalf of.
Planning, orchestrating, and integrating somebody else's work are not
authorship.

A change has one danger scope. It is *inside* the danger gate when it
touches a path either policy file declares dangerous, was raised with
`arc begin --dangerous`, or its danger could not be determined. It is
*outside* when danger paths are declared and it touches none. In a
repository that declares no danger path the gate is *uniform*: one rule
applies to every change, and for independence (below) every change is
inside it.

Where independent review is required, an approval is rejected when its
effective author is a contributor to the patchset it approves, when arc
assumed the reviewing identity rather than anyone declaring it, or when the
model its verdict recorded, effort dropped, equals the model the ledger
records for that patchset's implementer. A read under that model is a
self-review at any effort. A model compares as a string: arc holds no alias
table, so a model spelled another way is not matched by this ordinary model-match test.
Observed identities and the dated mixed-model exception are C40's unrealized
requirements. Where the ledger
records no model for the implementer, the read is judged by the actor,
session, and harness it records, and commit trailers never supply the
missing model. A verdict that recorded no model names nobody for this
comparison. Independence is judged against the
patchset the verdict binds to, never against a later one. A rejected self-approval is no approval (C5), and a
waiver bound to the same patchset can rescue it (C6).

Commit trailers are a projection arc writes from the ledger. A range whose
trailers disagree with the ledger is reported. For commits with no ledger
record, such as imported ones, trailers are declared, unverified evidence:
alone they neither discharge nor refuse, and the read says so.

**Status.** Settled on the effective author, the contributor fallback, the
ledger as the source of authorship, the ledger's implementer model as the
second identity, the danger scopes, the inertness of the planning,
orchestrating, and integrating roles, and when independent review is
required: only where the change is inside the danger gate *and*
`forbid_self_approval` is on. With the policy off, a self-approval is
recorded, counts, and leaves an independent-review debt owed. A danger scope
alone requires nothing. The model records the audit's held roles and reads
none of them: a planner, orchestrator, or integrator is never authorship, so
no rule consults one. Under assessed clearance (C40) an author's own read
never clears, which is a clearance rule rather than an approval refusal.

The reviewing model is a second identity, read from the ledger. Where
self-approval is forbidden the gate rejects such an approval "as it rejects
a contributor match"; where it is not, the verdict is recorded and counts
under C4's reading (ii) and shows only "that a review happened and not that
it was independent", so it is not an independent read for coverage (C22). A
read under the model the ledger records for the implementer, at any effort,
leaves the debt owed regardless of `forbid_self_approval`; that policy
governs approval authority rather than independent coverage. `Planned-by`
and `Orchestrated-by` never refuse a read: planning and orchestrating are
recorded as the auditor's dirty context for routing, and arc computes no
score. Integrating somebody else's work is not contributing to it. A
`changes-requested` verdict is never refused for its model.

**Source.** arc guide debt-review states ledger authorship, contributor
fallback, inert planning/orchestration/integration roles and ordinary
model-match independence, and when independence is required: "Under
`forbid_self_approval`, a change touching a declared path needs a verdict
from somebody other than its author. Elsewhere authorship refuses no
approval, but assessed clearance gates only a clearing one"; "Declare no
danger paths and every change is in scope." The bare `arc` overview: "Under
forbid_self_approval a dangerous path needs somebody else's verdict, or a
debt that stays owed." arc guide debt-recovery states the policy-off
recording rule and independent-coverage bars. arc review --help,
arc audit --help, arc trailers --help and arc roles --help state the
same recorded roles. C38 states completed-dispatch attribution. C40 states
the observed-model and dated election exceptions: the ordinary string
comparison is not a claim that assessed ladders have no alias registry.

**Realized by.** `effectiveActor`, `effectiveContributors`,
`independenceOwed`, `authorizationFor`, `implementerModelMatch`.

### C5. Approval validity

**Rule.** At most one verdict governs a change: the tip of the verdict
chain, where a verdict supersedes the tips it observed or corroborates one
without replacing it. Two tips that nothing supersedes leave the chain
contested: no verdict is authoritative, and the change is refused as
contested rather than as unreviewed. An approval authorizes only when it
governs, binds to the latest patchset, and the head has not moved (C2). A
provisional approval gates exactly like any other. An approval bound to an
earlier patchset is stale.

**Status.** Unsettled on a new patchset at an unchanged head, which the
guide and `--help` neither describe nor rule out.

- (i) The approval binds to the patchset, so it is stale on the new one
  (`README.md`: `arc integrate` "merges only the patchset a verdict
  approved").
- (ii) The approval is valid while the branch head equals the approved head
  (the guide, "Rules that change what you do": "A verdict binds to the
  exact approved patchset head. Any new commit makes the approval stale").

The model reads (i). After a rewrite that invalidates approval, a fresh snapshot and a verdict
on that patchset are required; a snapshot alone approves nothing.
An approval after a recorded history rewrite follows
the rewrite only when the successor differs from the approved head in nothing
but its signature, as judged when the mapping was recorded or imported, and
any other successor leaves it stale. What happens to the approval of a
change that has already closed is not stated. The model records no rewrite,
so rewrites are unsupported.

What the documentation states of a rewrite is the boundary the model keeps:
"An approval follows a recorded rewrite only when the successor differs from
the approved head in nothing but its signature"; "Snapshot records a new
patchset whenever the latest patchset's approved head differs from the
current branch head, even when its mapped head matches. Earlier verdicts
remain bound to their own patchsets and stay stale for the rewritten head; a
snapshot or rewrite grants no approval." A content or trailer rewrite keeps
"the open patchset's approval anchor; a fresh snapshot binds the successor".
Status and check "direct the caller to snapshot, and an implicit verdict on
the latest patchset refuses before recording anything"; an explicit
`--patchset` judgment "may record historical work, retaining that patchset's
review head and its stale coverage". In the model's terms the fresh patchset
is a patchset like any other: a verdict or waiver recorded before the rewrite
binds an earlier patchset (C1, C6), so it covers nothing of the new one, and
a verdict on the fresh patchset can.

**Source.** The guide, "Review coverage and debt" (the
verdict chain, contested verdicts, provisional verdicts, "the patchset's
approval anchor, which follows signature-only and role-addition rewrites"), "Rules that
change what you do" (staleness), and "History rewrites"; `arc snapshot
--help` ("A head whose rewrite invalidated approval requires a fresh patchset,
even when the latest patchset's mapped head already matches the branch.
Re-approval requires a verdict on that fresh patchset"); `arc review
--help`, `--relation`, `--provisional`; `README.md`, "One change, end to
end".

**Realized by.** `activeVerdicts`, `verdictContested`, `governingVerdict`,
`authorizationFor`, `evaluateDeclared`.

### C6. A waiver binds to one patchset

**Rule.** A debt declared for a patchset is a waiver for exactly that
patchset. It stands in for an absent approval, or rescues an approval
rejected under C4, and nothing else. It stops applying when a later
patchset is recorded; a new patchset needs a new declaration. A debt
declared after integration carries no patchset and waives nothing. An
integration's recorded basis names the debt only when the waiver supplied
the approval or let a rejected self-approval stand. Beside an approval that
stands without it, local or external (C9), the debt authorized nothing: the
basis leaves it out, and the review it records is still owed until a read
discharges it (C22).

**Status.** Settled, except where C5 and C19 are open. The
guide binds a debt to "the exact patchset head declared", which is C5's
question for a later patchset at the same head; the model reads the
patchset there too. That a debt declared after integration waives nothing
is a decision the contract makes: nothing is left to authorize. What the
recorded basis names is C19's. A debt `arc integrate --debt` declared
stays declared when that integration is refused, and waives like any other
on the patchset it names; an imported debt waives only as C24 allows.
A waiver follows signature-only and complete role-addition rewrites
(C39). Any other message or content rewrite leaves it stale even when the mapped head equals the branch:
a fresh snapshot and debt declaration are required. Equivalent declarations
reuse the obligation and confirm its backing publication; that changes no
waiver scope. Rewrites and publication durability are outside the model.

**Source.** The guide, "Review coverage and debt" (the
debt "can stand in for an absent verdict or rescue a self-approval rejected
by repository policy"; it "binds to the exact patchset head declared, so
new work needs a new declaration") and "Run a change" ("A debt declaration
is recorded in the basis only when its waiver supplied the approval or let
it stand"); the operator's ruling `authorization-rules-follow-the-guide` in
arc's journal (a debt beside an external approval that makes the approval
valid is left out of the basis, and "the obligation itself is untouched");
`arc integrate --help`, `--debt` ("The obligation survives closure and
`arc query --debt` finds it"); the guide, "Review coverage and debt" ("A
refused `arc integrate --debt` keeps the debt it declared").

**Realized by.** `debtsForPatchset`, `newestWaiver`, `authorizationFor`,
`waiverUsed`, `debtsNotUsed`, `coverageAfterIntegration`.

### C7. Which waiver applies (question b)

**Rule.** For a given patchset, only debts declared for that exact patchset
are considered. A debt declared for any other patchset is ignored, however
recent. If at least one debt is bound to the patchset, the patchset is
waived.

**Status.** Settled for whether a waiver applies. Unsettled for which debt
the recorded basis names when several are bound to the one patchset:

- (i) the newest;
- (ii) the oldest, the first one that let the approval stand;
- (iii) all of them.

The guide names a consumed debt in the recorded basis (C19) but does not
choose among several applicable debts. The model reads (i).

**Source.** The guide, "Review coverage and debt" (the
waiver binds to the exact patchset head declared).

**Realized by.** `newestWaiver`, `debtsForPatchset`.

### C8. A refusing verdict is not waivable

**Rule.** A governing changes-requested or comment-only verdict on the
current patchset refuses the integration, and no debt clears it: a debt
records a missing review, and a refusal is a review that was given. A
refusal bound to an earlier patchset does not refuse the current one; the
new patchset is what answers it.

**Status.** Settled.

**Source.** The guide, "Review coverage and debt" ("A
current `changes-requested` or `comment-only` verdict is its own next action
and offers no debt route: a waiver records a missing review, not a way past
a refusal"); `arc integrate --help`, `--debt`.

**Realized by.** `authorizationFor`, `reviewObligation`.

### C9. External verdicts

**Rule.** An external verdict records a decision made outside arc about an
exact revision. It gates only where that revision equals the current
patchset head. An external approval never counts alone inside the danger
gate (C4), whatever `forbid_self_approval` says: there it can stand beside
a local approval, and its refusals still refuse, but it never supplies the
approval itself. Outside the gate it authorizes alone; in a uniform
repository it authorizes alone unless independent review is owed (C4).
Where it authorizes, no local changes-requested or comment-only verdict may
refuse the current patchset. It never supersedes a local refusal, never
satisfies independent review, and is never an independent read for
coverage (C22), because arc cannot verify who decided. An external approval
that authorizes is the authorization, and a debt beside it is not (C6). An
external rejection of the current head closes the change as abandoned.

**Status.** Settled, except where noted below. That an external approval
never counts alone inside the gate whatever `forbid_self_approval` says is
the guide's "never alone on a dangerous path", as the operator's ruling
reads it. That a uniform repository has no dangerous path for this rule,
so its external approval counts alone unless independence is owed, is the
ruling's amendment; the guide's text does not decide it. Unsettled:

- *An external change request beside a local approval or a waiver.* The
  documentation says an external verdict gates, and that a change request
  can carry findings; it does not say whether a change request stands over a
  local approval or a waiver. (i) It stands over both, as a refusal. (ii) It
  gates only through the findings it carries. The model reads (i) and
  carries no external findings.
- *Several external verdicts about one revision.* (i) The newest governs.
  (ii) Any refusal among them stands. The model reads (i).
- *The basis where a local and an external approval both stand.* (i) The
  basis names the local verdict alone. (ii) It names both. The model reads
  (i).
- *An external verdict after a recorded rewrite.* (i) Its revision follows
  the rewrite, as other recorded revisions do (the guide, "History
  rewrites": "every derived reading follows them forward"). (ii) It names
  the old revision and stops matching. Rewrites are unsupported in the
  model.

**Source.** The guide, "Review coverage and debt" (an
external decision is recorded "beside, never as, a verdict arc witnessed";
an approval "gates only the revision it names and never alone on a
dangerous path"; it "never supersedes a local refusal"; "A change request
carries findings, and a rejection of the head closes the change"); the
operator's ruling `authorization-rules-follow-the-guide` in arc's journal,
as amended (an external approval "never supplies the approval there by
itself"; a repository declaring no danger path still lets it count alone
"unless `forbid_self_approval` owes independence"); `arc external verdict
--help`.

**Realized by.** `externalVerdictAt`, `authorizationFor`,
`independenceOwed`, `coverageAfterIntegration`.

### C10. Findings, holds, dependencies, and lifecycle

**Rule.** Each of the following refuses the integration, independently of
the others:

- an open blocking finding in the shipped review set (audit findings are a
  separate set and never block);
- an active hold (holds are independent, and releasing one leaves the rest
  in force);
- a prerequisite change that has not integrated;
- a closed change;
- a change that declares it is iterating (C11).

Claims are advisory liveness and refuse nothing. Integration warns about
an active foreign claim unless actor, harness, and session all match its
owner. A missing or empty coordinate cannot match. This warning never
changes the authorization. The guide names integration as lead-owned. Claim
renewal and release ownership are outside this integration decision.

**Status.** Settled on the blockers and claim warning. Unsettled on
"Integration remains lead-owned": (i) the lead owns the workflow, without a
role-based refusal; (ii) only an invoker with the lead role may integrate.
Neither the guide nor `integrate --help` states a role refusal. The model
reads (i) and carries no role observation.

Contribution-trailer and changelog advice never adds a blocker, whether a
trailer is missing or contains an invalid coordinate. Forge readiness is
independent of local integration's gates and judgments.

**Source.** `README.md`, "One change, end to end" (no open blocking
finding, no active hold, every prerequisite integrated); the guide, "Rules
that change what you do" (claims are advisory, never locks; complete foreign-claim matches),
"Contribution trailers" (advice never blocks), "Forge" (local authorization
is independent), and "Exit
codes" (2, 4, 6, 7, 13); `arc release-hold --help` (one hold at a time);
`arc audit --help` and the guide's `arc findings --audit` (audit findings).

**Realized by.** `findingResolved`, `openBlockingFindings`,
`evaluateDeclared`.

### C11. An iterating change and the missing approval (question c)

**Rule.** A change that declares it is iterating is refused on that ground
until the declaration is cleared. While it iterates, the approval check is
suppressed: no missing, stale, self-rejected, or contested approval ground
is reported. Every other blocker still applies. Clearing the declaration
restores the approval check; iteration grants no integration permission.

**Status.** Settled.

**Source.** The guide, "Run a change": "While a change declares `iterating`,
`check` reports `iterating` and suppresses `no-valid-approval`; every other
blocker still applies." `arc iterating --help`; `arc begin --help`,
`--iterating`; the guide, "Exit codes" (13).

**Realized by.** `evaluateDeclared`.

### C12. Gate declarations

**Rule.** A gate is declared by name with a command, an optional timeout,
optional profiles, optional events, an optional selector (C29), and an
optional environment probe. The project's write confinement (C43) is part of
every gate's declaration. Its event set selects integration, publication,
or both; an omitted set selects both. Required integration gates exclude
declarations selecting publication alone. Publication has its own guard
(C30). The declarations in
force are `.arc/gates.toml` as committed on the change's target branch at
its current head, together with the operator's gates, plus gates the
change's own head declares under names the target does not; a change can
add gates but can neither delete nor weaken one. A declaration is part of
the target's tree, so moving it moves the target (C3); only the operator's
layer, outside every tree, moves a declaration alone. A change whose target
branch cannot be resolved is refused (`target-unreadable`), since nothing
says what it owes. Evidence answers only the declaration it ran under, so a
declaration edited after its evidence was recorded is a check that has not
run (`declaration_changed`). Which gates are required follows the change's
profile; a change whose profile requires no gate owes no gate evidence and
integrates on its approval alone. A gate that is required but has no
declaration is refused like missing evidence. Two policy layers declaring
one gate name with a different command or a different environment probe are
in conflict. The check refuses, and no other ground is evaluated, because
there is no declaration set to evaluate against. Execution refuses too.

A closed change (C2) reads the project's gate and policy declarations
where it closed: the target's at the revision its closure recorded as where
the target stood, plus the gates its judged head adds, so a gate the target
declares later is not owed and a declaration the target breaks later does
not fail it. A closure that recorded no target revision — an abandoned or
superseded change, a legacy closure, or an asserted fast-forward given no
`--target-before` — reads the target's current declarations. The
operator's layer is read as it stands now either way.

**Status.** Settled, except which fields of a declaration its evidence
answers beyond confinement, which C43 settles. The guide says the run "under
the declared gate" decides, and that two layers agreeing on command and probe
combine with the shorter timeout. (i) The command and the timeout: evidence
run under another timeout is under another declaration. (ii) The command
alone, with the probe read through C15. The model reads (i).

The model takes the effective declaration set, the required gates, and the
conflicting names as observations. That a required gate with no declaration
is refused is a decision the contract makes: an unknown is never success
(C13). Which revision a closed change's project declarations come from is
an observation boundary the model does not select: its observations name
the set in force.

**Source.** The guide, "Run a change" (required gates are read from the
target branch plus the gates the change adds; `target-unreadable`; a
profile with no declared gate runs none; a closed change's "gate and
policy declarations are the target's at the revision the closure recorded
as where the target stood, plus the gates its judged head adds"; "A
closure that recorded no target revision … reads the target's current
declarations instead. The operator's own gate and policy files are read as
they stand now"), "Review coverage and debt" (layers combine by name; the
same name with a different command or probe is a conflict that `arc check`
and gate execution refuse), "Rules
that change what you do" (the run under the declared gate decides), and
"Files" (the `[gates.<name>]` table); `arc policy --help`.

**Realized by.** C31 to C37 state additional budget, coverage, admission and
batch constraints absent from the effective declaration inputs. For the
represented command, timeout, confinement and event fields: `declarationShape`, `declarationApplies`, `evaluate`, `gateEvidence`,
`execute`.

### C13. The four gate readings

**Rule.** A required gate is read four ways, kept apart:

- **pass/fail**: what the run reported;
- **coverage**: whether the run answers the event, declaration, the evaluated
  tree (C3), the worktree state (C16), and the environment (C15) in force;
- **availability**: whether a record exists, whether arc ran it or somebody
  attested to it, and whether the record could be read;
- **falsification**: whether passing evidence names a failure it answers.

A gate is green only when it is covered and passed. Nothing unknown is
success: an omitted observation, an unreadable record, a run of another
declaration, tree, or environment, and evidence of unknown cleanliness each
leave the gate not green. Attested evidence counts like any other, marked as
attested. Falsification is advisory and never blocks.

A passing gate is discriminating when any readable passing evidence for
that gate at the counted tree names a falsification. A later pass naming
none does not retract it. Falsification does not require that the evidence
answer the current declaration or environment; coverage does (C14, C15).
Where the counted tree is unresolved, the guide uses the counted revision;
the model always observes an evaluated tree and does not model that fallback.

**Status.** Settled. That an unreadable record is not a result is a decision
the contract makes; the documentation does not describe unreadable records.

**Source.** The guide, "Rules that change what you do": "A passing gate row
is `discriminating` when any passing evidence for that gate at the counted
tree (or revision when the tree is unresolved) names a falsification. A
later pass without one does not retract it." The same section binds gate
coverage to a tree and declaration and makes falsification advisory;
`arc verify --help`, `--attest`, `--falsified-by`, `--predicted`.

**Realized by.** `readGate`, `gateGreen`, `gateEvidence`.

### C14. Which verification answers a gate (question a)

**Rule.** Evidence is keyed by the operation event, the tree the run read,
the declaration it ran, and the environment it recorded. A publication pass
answers no integration requirement, and an integration pass answers no
publication requirement. Evidence that recorded no event is read as
integration evidence. For a tree-bound gate, two commits with one tree are one evaluation, so
evidence recorded at an earlier revision answers a later head with the same
tree. A `binds = "commit"` declaration in any applicable layer narrows this:
only execution at the required commit, or its evaluated merge, answers;
rewrites never carry its evidence. Publication reuse requires its exact
recorded target revision. A record at another tree, under another declaration, or
from another environment never answers the gate at the evaluated tree, and
never hides a record that does. Coverage and confinement require fresh
identity: evidence that recorded neither answers only an unconfined,
unscoped declaration. With an older pass at tree A and a newer run
at tree B, evaluated at A, the run at B says nothing: the answer comes from
the records at A.

Among several records under the key, the newest decides: a later failing,
dirty, or unreadable run replaces an earlier pass. A record at the
evaluated tree that carries no environment, for a gate that declares a
probe, is not under the key in force, so it answers nothing (C15) and hides
nothing.

**Status.** Settled. Declaration omission and evidence omission are
separate claims: the former selects both events, the latter is integration.

**Source.** The guide, "Rules that change what you do": "Gate evidence
binds to a tree, not to a commit"; the gate line reads "`inherited from
<revision>` wherever the run that answered was against another commit
holding that tree"; "The newest run at the evaluated tree under the
declared gate and applicable environment decides; other runs cannot hide
it". A reuse of passing evidence is keyed the same way: `arc verify
--help`, `--skip-green` ("Evidence counts for its tree whichever commit it
ran on, as it does for readiness, and only the newest evidence readiness
counts there is a candidate. Reuse records that tree and requires that
evidence to carry the same content key"), so a reuse for a head that
already contains its target answers at that head's tree, and a gate whose
newest evidence failed or carries no tree is run again rather than reused.

`arc guide gates`: "Coverage and confinement require fresh identity; legacy
evidence answers only unconfined, unscoped declarations."
The guide, "Files", states that evidence identifies its event and that a
publication pass does not satisfy an integration requirement. The same
section states that historical verification evidence with no recorded event
is integration evidence.

**Realized by.** `readGate`, `readGateFor`, `evidenceEvent` for tree-bound
checks. Commit binding is documented but not realized: gate lookup receives
an evaluated tree, not the required execution commit. `arc guide
rules-evidence` states "only a run at the head's own commit, or at the merge
of that commit, answers for it"; `arc guide gates` declares `binds` and its
layering. Scheduling default reuse and `--rerun` are execution effects.

### C15. Environment probes

**Rule.** A gate that declares an environment probe is green only for
evidence carrying the identity the probe yields where the decision is made.
A probe that fails, prints nothing, or overruns yields no identity, and no
evidence counts for that gate there. Evidence carrying no identity is
unknown and answers only gates that declare no probe. A gate with no probe
takes evidence from any environment. Attested evidence names its
environment explicitly.

**Status.** Settled. Which coverage is reported first when evidence is at
another tree *and* from another environment is presentation (C23).

**Source.** The guide, "Rules that change what you do" (a gate may declare
an environment probe; a failed, empty, or overrunning probe yields no
identity); `arc verify --help`, `--environment`.

**Realized by.** `readGate`, `gateEvidence`.

### C16. Dirty worktrees and the dirty-tree waiver

**Rule.** Evidence that arc ran on a worktree holding uncommitted changes is
recorded and does not count: no checkout of its revision reproduces the tree
it read. Evidence whose worktree state is unknown does not count either.
Attested evidence carries its own execution context and no worktree state.
A dirty-tree waiver, declared with a reason, lets dirty evidence count; it
binds to the head it was declared at, and the next commit ends it.

**Status.** Settled, except as below. That evidence of unknown cleanliness
does not count is C13's decision that nothing unknown is success; the
guide and `--help` do not describe it.

- *Several waivers at different heads.* (i) Only the newest is in force.
  (ii) Each covers the head it names. The model reads (i).
- *Dirty evidence evaluated at a later commit with the same tree.* (i) The
  waiver covers evidence recorded at its head wherever that evidence
  answers (C14). (ii) The next commit ends the waiver, so it no longer
  covers that evidence. The model reads (i).

**Source.** `arc verify --help`, `--waive-dirty` ("Dirt is fatal by
default: a passing run whose tree no checkout reproduces is recorded and
declines to satisfy the gate"; the waiver binds "to this head alone — so
the next commit ends it") and `--attest`.

**Realized by.** `dirtyTreeWaiver`, `readGate`, `gateEvidence`.

### C17. Acceptance probes

**Rule.** Every acceptance probe declared on the brief a patchset binds to
blocks until evidence bound to that brief and probe fails at the brief's
base (baseline) and passes at the patchset's head (final). The newest run
for each phase at its required revision decides. A brief with no base, or
with its base equal to the patchset head, cannot discharge a probe. The pair
proves discrimination, not relevance.

**Status.** Settled.

**Source.** The guide, "Run a change": "Both runs must name that brief and
probe; the newest run for each phase at its required revision decides. A
brief with no base, or with a base equal to the patchset head, cannot
discharge a probe." The preceding sentence requires baseline failure at
that brief's base and final success at the patchset's head; the guide,
"Exit codes" (12); `arc brief --help`, `--probes-json`, `--base`;
`arc verify --help`, `--probe`, `--probe-phase`.

**Realized by.** `briefOf`, `newestProbeRun`, `probeRefusals`.

### C18. Established and declared actors

**Rule.** Every write needs an established actor. An explicit actor is
established and declared; absent one, arc assumes `<harness>:<session>`
when both are known, otherwise Git's configured user name. When neither
fallback exists, a write refuses regardless of `require_declared_actor`.
An assumed actor is established but is not declared and cannot supply an
independent approval (C4). Reading is unaffected, so a readiness check
refuses neither a missing nor an undeclared invoker.

A command that can record checks `require_declared_actor` when opening its
append handle, from the invoking checkout. Integration additionally checks
the destination's requirement at the observed transition revision. Either
requirement refuses an undeclared effective author; a declared
`--on-behalf-of` subject satisfies that requirement. It does not establish
the actor who invoked the write. An unparseable append policy refuses before
recording; the model receives resolved requirements and cannot represent
that parse failure.

**Status.** Settled on the requirements. Unsettled on the single refusal
returned when a missing actor and withheld authority both stand: (i) the
identity guard refuses before an integration is evaluated; (ii) the
integration's unconditional exit 17 for withheld authority answers first.
The model reads (ii). Both readings refuse and record nothing.

Placeholder identities, malformed supplied agent coordinates and a
`harness:session` actor with an empty session are refused by the write's
identity validation (`arc guide identity-basics`: "An actor written as
harness:session requires a nonempty session"). The model's actor observation
represents a validated identity or absence; the spelling validation and
harness/session/model lookup are outside it.

**Source.** The guide, "Say who you are" ("When neither exists no actor is
established: a write refuses"; the append guard reads the invoking
checkout; "Integration also checks the change target's policy before
merging"; placeholder validation; the commands that record nothing include
`check`), and "Run a change" (destination declarations pinned to the
transition's observed revision); `arc integrate --help`, `--actor` and
`--on-behalf-of`; "Pair replica stores" (plain integration without authority
refuses with exit 17).

**Realized by.** `execute`, with `Observations.invoker`,
`invokerDeclared`, and `appendRequiresDeclaredActor`.

### C19. The decision basis

**Rule.** A permission names what it rests on: the patchset, its head, the
evaluated tree, the target branch and where it stood, the policy and the
integration shape resolved under it (C3), the authorization (the approving verdict, the debt when its waiver supplied
the approval or let a rejected self-approval stand (C6), or the external
decision), one covered passing evaluation per required gate and its
normalized declaration values, each prerequisite's closure, and the
blocking-finding and hold vectors that had to be empty. A refusal names the
facts that stood in the way.

**Status.** Settled on the integration basis's contents. C31, C32, C37 and
C41 state budget constraints, raise pins, batch references and landing facts
that the model's basis does not carry. The guide also
names an approving verdict's provisional reason, an external approval when
consumed, normalized gate and policy values, and the danger determination.
The model's basis identifies verdicts, captures required gate declarations,
and carries the effective policy. The referenced verdict carries its
provisional reason; the policy's danger scope (C4) represents the danger
determination, without its provenance: which path, the escalation, or why
the scope was undetermined. The guide's recorded shape names the history
the integration wrote (`fast-forward`, `merge`, or `already-contained`);
the model's basis names the resolved shape the decision was taken under,
and the history written is C3's Git effect. The coverage channel compares
the authorization slots only, not the full recorded basis.

Unsettled on whether declaration values in the basis are read committed or
uncommitted: (i) values from committed declaration files; (ii) values from
the checkout including local edits. The guide states what is recorded but
does not settle this observation boundary for every declaration layer. The
model takes declaration and policy values as observations, without choosing
how files supplied them. C12 specifies the target as the project source;
it does not settle the operator layer's observation boundary.

**Source.** The guide, "Run a change", the paragraph beginning "A guarded
integration records the shipped patchset and head": it enumerates the
basis, the shape among it,
including "the normalized gate and policy values consumed, and the danger
determination", and records a debt only when its waiver supplied the
approval or let it stand. `integrate --dry-run` prints the basis; readiness
and the basis are rebuilt before merging. The paragraph after it makes the
decision one function of observed facts, a plan naming the target revision,
the approved head, the tree the merge must ship, and the basis to record,
which `integrate --dry-run --json` prints as `arc-integration-plan/1`
(`arc integrate --help`, `--json`). The facts C1 to C18 read name the
model's corresponding slots; the guide, "Exit codes", names refusals.

**Realized by.** `evaluateDeclared`, `authorizationFor`, `gateEvidence`.

### C20. Execution

**Rule.** Permission is not effect. A decision records nothing; only an
integration puts its basis in the ledger, and it records the basis it was
taken on. Within one integration, readiness is computed again and the basis
rebuilt before merging, and if readiness fails or the basis differs nothing
is written. The target head and merge tree that readiness reads must be the
destination revision and tree the decision observed; a readiness reading made
for another target revision or merge tree does not authorize the
integration. A decision made earlier, such as a dry run's plan handed back,
never changes the integration's decision: the integration decides afresh
from what it observes, under the policy in force when it runs, and names
what moved since the earlier plan — the approved head, the target revision,
the gate or policy declarations, the approval, or provisional routing and
prerequisites — beside its refusal, or as a warning when it still proceeds.
The debts a plan saw are part of the approval it names (C28).
A store paired with replicas integrates only while it holds integration
authority. A readiness check reports a store without it as a ground of its
own, `integration-mode`, beside every other ground that stands, and an
integration there is refused for the missing authority whatever else
refuses it. The explicit provisional preparation such a store may make
instead is C25's. A missing branch or conflicting declarations leave
nothing to act on.

**Status.** Settled. A policy that changes between a decision and the
integration is re-decided under the policy in force, which the guide's
integration plan settles; project policy is committed on the target, so
moving it moves the target too (C12), and the change then evaluates a merge
nobody evaluated (C3), refused wherever a gate is required. Which refusal
answers an integration in a store without authority when its decision is
refused as well is settled on the authority: `arc check --help` lists
`integration-mode` first among its blockers "in precedence order", the
guide has `integrate` refuse in `check`'s vocabulary, and it says of a
paired replica without authority that "Plain integrate refuses there with
exit 17". The ground set the check reports beside it stays C23's.
Which refusal answers a readiness reading whose target or merge tree differs
from the decision's is not named: the guide states the agreement in its
account of what an invocation observes, not among integration's refusals.
The contract reads it as the basis differing, so nothing is written. The
model decides readiness and the plan from one observation set, so the two
agree by construction; the race between observations is outside the model.

**Source.** The guide, "Exit codes" (`integrate` refuses in `check`'s
vocabulary; exit 17 for a replica without authority), "Rules that change
what you do" (a single `integrate` checks that its merge carries the
evaluated tree and undoes it otherwise), "Pair replica stores" ("A paired
replica without authority is refused by `integrate`"; "Plain integrate
refuses there with exit 17"), "Run a change" (the paragraph beginning "The
decision is one function of facts observed": "Handing it back with
`integrate --expect-basis <file>` never changes the decision; it names what
moved since … in one line beside a refusal, or as a warning when the
integration still proceeds"), and "Files" (policy is read from the change's
target branch); `arc check --help` (the exit status table: "17
integration-mode"); `arc integrate --help`, `--dry-run`, `--json`,
`--expect-basis`; `arc guide identity-options` ("Authorization boundaries
start fresh mutable observations. Movement guards take independent
observations. Readiness target heads and merge trees must agree with the
destination and tree observed by the decision").

**Realized by.** `evaluateDeclared`, `execute`, `recordIntegration`.

### C21. Debt kinds and the owed review

**Rule.** Debt names nothing-read, merge-resolution-unread, repair-unread,
replayed-unread, contributor-only, ineligible-review or independent-review.
A declared kind wins over an ordinary derivation; replayed-unread is derived
only by composed landing and cannot be declared or imported as a declaration
(C41). Assessed clearance may derive ineligible-review from a findings approval
(C40). Otherwise a declaration names an ineligible read and routing's reasons.

The ordinary derivation is nothing-read with no verdict on any patchset;
contributor-only when every verdict on this patchset is its contributors';
repair-unread when this patchset has no verdict and an earlier one has approval;
independent-review otherwise. The review-obligation view reports a covering
read, standing refusal (C8), waiver (C6), or the owed kind.

An ineligible-review declaration names a verdict or audit: explicit read, else
latest verdict on its patchset, else after integration latest audit; none
refuses. Qualifiers are same-model, same-family, below-floor, floor-unknown,
reviewer-unseated and below-clearance. Source is assessed or declared, with a
route-version coordinate. A read flag on another kind refuses.

Assessment/1 retains independence, qualifiers and route version; qualifiers
are present exactly when independence is ineligible. Assessment/2 additionally
retains findings eligibility and clears. A clearing /2 answer must be eligible
on both answers, name reviewer effort and no qualifier; a nonclearing one needs
a qualifier. Shape, closed qualifier names and one-token route version are
validated. The ordinary /1 route refuses an eligible assessment because it
declares no missing independent review.

Production records the ledger planner, implementer, orchestrator and integrator.
The unique verbatim Implemented-by projection from the patchset's range is kept
as trailer_implementers for comparison and assessment binding, never as the
source of those roles. Missing range evidence differs from an empty list.

An ineligible-review declaration refuses an assessment under which its named
read would discharge the debt and records one under which it would not.
Without `review_clearance` the assessment's independence decides; under it
the read's clearance (C40) decides, and a judgment arc cannot establish
records the debt.

**Status.** Settled on the represented ordinary kinds and /1 declaration.
Named audit reads, below-clearance, assessment/2 and the assessed/replayed
derivations are documented but not realized. The model has no
`review_clearance`, so independence decides its declarations. Unsettled:

- A new unread patchset after earlier negative/comment-only verdicts is not
  assigned a specific derived kind by the documentation; the model uses the
  general independent-review case.
- A declaration with neither assessment nor qualifier may refuse or retain
  no qualifier; the model refuses.

**Source.** arc guide debt-obligations ("An assessment under which the named
read would discharge the debt is refused on this kind, and one under which
it would not is recorded: without `review_clearance` its `independence`
decides, under it the read's clearance (`arc guide debt-clearance`) does,
and a judgment arc cannot establish records the debt"), arc guide
debt-clearance, arc debt --help and arc integrate --help ("arc derives it
only under `review_clearance = "assessed"`, for an approval that finds
without clearing"; "A file under which that read would discharge the debt
is refused"), including the assessment schema rules.

**Realized by.** debtKindFor, derivedKind, reviewObligation and declareDebt
for ordinary verdict-based /1 declarations. C40/C41 state the unrealized
assessment/2, clearance, extent and landing protocols.

### C22. Audits, and why a fulfilled read is not an approval

**Rule.** An audit reads the integrated revision and cannot be recorded while
the change is open. It never rewrites the recorded authorization. Its findings
are separate from those that shipped. A declared independent read recorded
after the debt, approving or requesting changes on what shipped, discharges
ordinary debt. A `comment-only` read judges nothing and leaves debt owed.
An audit carrying an ineligible assessment discharges no kind of debt.
Without assessed clearance or an assessment, actor and ledger model authorship
decide independence (C4). Planning, orchestration and integration of another's
work do not supply authorship. An approving self-audit refuses where policy
forbids self-approval; a negative audit can record without independence but
discharges nothing unless independent. Discharge never implies approval.

Outside assessed ladder clearance, `ineligible-review` requires an independent
approving or changes-requested read recorded since the declaration under an
eligible bound assessment of its own: an audit, or a verdict on the patchset
that shipped. Without assessed ladder policy, a read of either kind carrying
an ineligible assessment discharges no kind of debt, and a verdict without
an assessment, with an ineligible one, or with one that does not bind leaves
`ineligible-review` open. Binding requires the reader's model among the
reviewer's identities, equal efforts where both name one, and author coverage
of every range `Implemented-by` coordinate at its effort; a verdict's
assessment binds exactly as an audit's. An author with no effort covers its model at any
effort; a trailer with no effort needs such an entry. Missing range evidence
is not an empty author set. C40 states observed-model, clearance and extent
requirements, including the exception for a clearing ladder agent.

A debt with no production record reads the shipped patchset's authorship.
A closure with no source patchset recovers the patchset whose head is its
integrated commit, else the newest before closure. With no patchset, declared
trailers alone neither discharge nor refuse.

**Status.** Settled on ordinary verdict kinds, ineligible-assessment bars,
and the reads that clear `ineligible-review`: debt-obligations and
debt-recovery agree that an audit or a verdict clears it under its own
eligible, bound assessment. The guide does not say whether `arc review` can
record a verdict on a change that has closed; a debt declared at integration
is then answerable by a verdict only if it can. The model accepts whatever
verdicts the history holds. The binding order when both auditor and authors fail is unsettled: the model
checks the auditor first. Whether a later negative audit withdraws an approval
is unsettled: the model retains the approval beside the audit. Whether a repair
after a discharging read starts a new obligation is unsettled: the model starts
one. An approving audit that is not independent is refused where
`forbid_self_approval` is on and recorded otherwise, as C4 settles; it
discharges nothing either way.

**Source.** `arc guide debt-recovery`: "A `comment-only` read judged nothing:
it is kept as a read and the debt stays owed"; "Without assessed ladder policy,
an ineligible assessment leaves debt owed"; "An ineligible-review debt also
asks the read, audit or verdict alike, for an eligible, bound assessment of
its own". `arc guide debt-obligations`: "It clears with a read recorded since
the declaration that approves or requests changes under an assessment of its
own with `independence: eligible`: an audit (`arc audit --assessment <file>`)
or a verdict on the patchset that shipped (`arc review --assessment
<file>`)"; "a verdict in the same case leaves it open". `arc review --help`
binds a verdict's assessment "exactly as `arc audit --assessment` binds one".
`arc audit --help`: "An audit whose
`--assessment` says `ineligible` discharges no debt of any kind, whatever actor
records it". `arc guide debt-obligations` and `arc audit --help` state
model-and-effort author coverage, missing-range handling and the binding
outcomes `bound`, `model-mismatch`, `effort-mismatch`, `model-unrecorded`,
`identities-unstated`, `authors-uncovered` and `authors-unread`.

**Realized by.** `admitAudit`, `auditDischarges`, `auditIsIndependent`,
`assessmentBinding`, `auditClears`, `verdictClears`, `coverageAfterIntegration`, `debtStanding`,
`openAuditFindings`, `latestIntegration`, `historicalAuthorization` for
ordinary local reads. Author-effort binding is documented but not realized:
the retained author projection and assessment authors hold model slugs only.
Closure recovery is outside the input history, whose integrations always
name their patchset. C40 lists other unrealized review requirements.

### C23. Refusal order is presentation

**Rule.** The meaning of a refusal is the set of grounds that stand. The
order in which they are listed, and so which one is "first", is
presentation and carries no semantics. There is one structural exception:
where gate declarations conflict (C12), the set is that one ground alone,
because no other ground can be evaluated. A single-refusal answer, such as
a readiness exit code or the model's `decide`, is a projection of the set
chosen for display. Two answers agree when their sets of grounds agree,
through the vocabulary mapping.

**Status.** Settled; a decision the contract makes. The documentation gives
each blocker its own exit code and reports every blocker, and derives no
precedence among them: `arc check --help` lists the blockers "in precedence
order" and has the exit code name "the first blocker", which fixes a
display order and states no reason for it. An order stated without a reason
would be a second semantics that nothing constrains. Refusals at execution
are one answer, not a set; C20 settles the one the documentation names
there, the missing authority.

**Source.** A decision the contract makes; the guide, "Exit codes"; `arc
check --help` (the exit status table; `--json` emits all blockers).

**Realized by.** `evaluate`, `refusals`, `decide`.

### C24. Review eligibility across replicas

**Rule.** Every event keeps the origin that recorded it. An event another
replica recorded reaches this store only through an import the operator
admitted, and it may do here only what its publisher was granted for its
origin: facts, review input, review authority, debt input, waiver,
authority, rewrite, integration, provisional integration, or external
decision. A foreign verdict gates only where its origin was admitted with
review authority and is a current member of `trusted_review_replicas` in
the operator's policy, which starts empty, so by default no foreign verdict
satisfies review. A foreign verdict that gates still answers to C4: a
contributor's or an assumed identity's approval is rejected as a local one
is. Verdict selection is local first: a foreign verdict never replaces a
local refusal or settles a contested local chain (C5), and one that does not
gate stays an attributed input, shown with its origin. A review-input audit
discharges no debt and corroborates no provisional approval (C22); a debt
imported as debt input waives nothing (C6) and stays an obligation. Project
policy grants none of this, and an integration already recorded stays a
fact whatever trust later becomes.

**Status.** Settled. The guide's "current" membership and its "Historical
closures remain facts" together decide a trust revoked after an
integration: later decisions stop counting the verdict, and the recorded
basis is not rewritten.

**Source.** The guide, "Pair replica stores" ("Pairing grants project
membership, never publishing capabilities"; "No foreign replica supplies
review authority by default. A foreign verdict needs both admitted
review-authority and current trusted_review_replicas membership to gate.
Contributor and assumed-identity checks still apply"; "foreign edges cannot
replace a local refusal or settle a contested local graph. Review-input
audits cannot discharge debt or corroborate provisional approval;
debt-input cannot waive approval"; "Enrollment and review trust are
operator-only; project policy cannot grant them"; "Historical closures
remain facts") and "Run a change" (finding release in "the receiver's
eligible disposition graph"); `arc review --help`, `--provisional`
("Obligation selection follows approval's local-first verdict history");
the operator's ruling in arc's journal on replica authorization ("No foreign
replica satisfies review on the authority. `trusted_review_replicas` in
operator policy exists and starts empty. Imported verdicts stay attributed
inputs, shown with their origin, and cannot overcome a local refusal").

**Realized by.** Nothing yet: the model's events carry no origin, so every
event it holds is local.

### C25. Provisional integration

**Rule.** A paired replica without integration authority prepares an
integration only when asked explicitly, with `integrate --provisional`, and
only where `[replica] provisional_enabled` is not declared false. The
preparation is decided under the canonical target's review, actor, and
gate rules, together with any gate the staging destination adds; a staging
policy cannot weaken them. It writes an unsigned merge to a staging branch
in the replica's own namespace, never to the canonical target, and leaves
an obligation: publication and closure stay owed to the recipient, the
known authority holder unless the caller routes it elsewhere. Preparation
is not integration. The change stays open, and a provisional prerequisite
satisfies only another local preparation, never a canonical dependency
(C10). A rejection by the authority stays attached to the obligation,
across authority transfers, until a superseding judgment on the delivered
patchset disposes of it or an accepting integration settles the delivery.
Without the flag, the store's integration is refused as C20 says.

**Status.** Settled. Debt publication accompanying a refused preparation
is reported separately, including durable, visible-unconfirmed, absent,
and unknown publication states. Recovery and syncing that publication are
outside this model and change neither the patchset waiver scope nor the
preparation's authorization requirements.

**Source.** The guide, "Pair replica stores" (the `integrate --provisional`
paragraphs: "Explicit provisional preparation is available on paired
replicas without authority. Plain integrate refuses there with exit 17";
"canonical review, actor and gate rules and additional staging/head gates
still govern preparation. A staging policy cannot weaken them"; "A verified
refusal remains attached across authority transfer until an explicit
superseding judgment disposes of it or an accepting integration settles the
delivery"; "Imported preparation never satisfies a canonical dependency");
`arc integrate --help`, `--provisional`, `--for-replica`, `--for-forge`;
`arc check --help`, `--provisional`; the operator's ruling in arc's
journal on replica authorization ("Without it, plain `integrate` on a
replica without authority keeps refusing with exit 17. When the authority
rejects a change, the rejection is attached to its obligation, which stays
listed until it is explicitly disposed of or the change is integrated").

**Realized by.** Nothing yet: the model has no staging destination and no
provisional obligation.

### C26. Accepting a delivered change

**Rule.** The authority accepts a change another replica delivered by
preparing it, as lead: it admits the delivery (C24), binds a checkout,
signs the change's commits, snapshots, runs the required gates at the
signed head and the brief's acceptance probes, and records that evidence
and no judgment. Imported passing evidence never stands in for the local
gate run. A signature-only rewrite carries an eligible approval across it
(C5); eligible verdicts that fork refuse readiness until a local reviewer
supersedes them. Where the authoritative target moved beyond the delivered
base, acceptance stops and names the rebase, snapshot, and fresh review it
owes; it never replays the content onto moved history. The prepared change
is then decided under C1 to C23 like any other, and commonly still owes the
local review.

Acceptance requires the delivered branch head to equal the latest
patchset's head or its recorded signature-only successor. A worker that
rebases records a patchset before export, declaring the implementing
contributors; rebasing alone supplies no implementation credit. This is
preparation's head binding, not an approval.

**Status.** Settled.

**Source.** The guide, "Pair replica stores" (a worker's rebase requires a
patchset before export; acceptance's delivered-head equality),
"Prepare a delivered change" ("Preparation records
evidence and returns readiness; it records no judgment"; "Imported passing
evidence never suppresses the local head-gate run"; "If the authoritative
target moved beyond that base, acceptance stops with explicit rebase,
snapshot, and fresh review guidance"; "Genuine eligible verdict forks
retain all tip IDs and origins and refuse readiness"); `arc accept --help`;
the operator's ruling in arc's journal on replica authorization ("The
accept verb never replays content onto moved authoritative history. It
stops and prints the exact rebase, snapshot and review remedy").

**Realized by.** Nothing yet: acceptance is preparation, and the decision
it leads to is the one C1 to C23 describe.

### C27. A debt's standing

**Rule.** A debt stands in one of three states, and every reading of it is
the same one. It is *declared* while its change has not integrated: nothing
is owed yet and no review has answered it. It is *owed* once the change has
integrated and no eligible review has answered it. It is *discharged* when
one has, and the debt names the review that did. Which review is eligible is
C22's: an independent approving or changes-requested verdict or audit on the
shipped revision recorded after the debt was declared for the kinds C22 does not except, and only an
audit, or a verdict on the shipped patchset, whose own assessment is bound,
eligible and covers the work for `ineligible-review`. A debt is outstanding, listed as an obligation and
binding as a recorded obligation only while it is owed; a declared debt is
absent from the debt queues. Standing changes no waiver: a declared debt
still stands in for an absent approval at integration (C6).

**Status.** Settled on the three states and what moves a debt between them.
The guide says the waiver keeps "its meaning: true, listed and binding only
for `owed`", where a waiver that bound only after integration would rescue
nothing the integration needed; the model reads "binding" there as the
obligation's, and keeps C6's waiver scope. The guide does not say how the
state reads for a debt declared on a patchset other than the one that
shipped, or after the change closed without integrating; the model reads a
change that has not integrated as declared, whichever the patchset, and an
integrated change's debt as answered by any eligible review of the shipped
revision recorded after it.

**Source.** The guide, "Review coverage and debt": "A debt stands in one of
three states, and every view that shows it reads the same one. `declared`:
the change has not integrated, so nothing is owed yet and no review has
answered it. `owed`: the change integrated and no eligible review has
answered it. `discharged`: one has, and the debt names it. [...]
`debt_outstanding`, the debt queues and the waiver keep their meaning: true,
listed and binding only for `owed`, which is why a declared debt is absent
from `arc inbox`, `arc query --debt` and the workspace backlog"; `arc status
--help` ("`debt_standing` is `declared` before the change integrates, `owed`
after, and `discharged` once a review answers the debt").

**Realized by.** `debtStanding`, `coverageAfterIntegration`.

### C28. Planning a declaration, and expecting a basis

**Rule.** `arc integrate --debt ... --dry-run` decides the integration as it
reads once the debt is declared, and writes no event. It says which debt it
would declare, or that the change already carries it: a declaration that
repeats the reason, kind and declarer against the same patchset and coverage
records nothing and names the debt in force. A declaration the execution would
refuse (C21) is refused by the plan, with the same message and exit code. The
plan never invents an approval: every ground C1 to C20 reads stands, a
`changes-requested` verdict on the exact head among them (C8), and a debt
beside an approval that stands authorized nothing (C6).

Handed back with `--expect-basis`, the plan names what moved, and the debts
it saw are part of the approval it names. The event the execution itself
writes is not a move. A debt another actor declared meanwhile, or an
existing declaration the execution reuses instead of writing, is. A plan made
without `--debt` records the debts the patchset carried when it was made, so
a debt declared after it is a move even where the integration never
consumes it.

**Status.** Settled on the plan's decision, its refusals, and the two moves.
The documentation does not say whether a plan that would declare a debt names
the event the execution will write: it says only that "a plan that would
declare names no debt event in `authorization`". The model gives the
declaration the identifier the next one would carry, so that executing the
same declaration yields the planned authorization and any other debt makes the
authorization move. `--provisional --dry-run` "plans the same way".

**Source.** The guide, "Review coverage and debt": "`arc integrate --debt ...
--dry-run` plans the integration as it reads once the debt is declared, and
writes no event. The plan says `would declare debt` with its kind, reason,
bound patchset and, for `ineligible-review`, the named read, qualifiers and
assessment basis; a debt the change already carries reads `debt already
declared` with its event. A declaration the execution would refuse is refused
by the plan with the same message and exit code: an unknown qualifier, no
verdict to name, an eligible assessment, a read flag on another kind. The plan
never invents an approval, and a changes-requested verdict on the exact head
still refuses it. [...] a plan that would declare names no debt event in
`authorization`. Handed to `--expect-basis`, the event the execution itself
writes is not a move; a debt another actor declared meanwhile, or an existing
declaration the execution reuses, is. `--provisional --dry-run` plans the
same way"; `arc integrate --help`, `--dry-run` ("With `--debt`, the plan reads
the change as it would once that debt is declared and says which debt it would
declare; a declaration the real run would refuse is refused with the same
message") and `--debt` ("With `--dry-run` nothing is declared: the plan shows
the debt").

**Realized by.** `declareDebt`, `planDeclaring`, `executeDeclaring`,
`execute`.

### C29. Conservative delta selectors

**Rule.** Integration may use a gate's optional selector, which receives the
source and target trees, the changed paths and the declared gates as `arc-gate-delta/1`. A complete
`arc-gate-selection/1` answer acknowledges the complete input object in its
`request` and names the gates affected by that delta. Writing stdin alone
proves no acknowledgment.
A required gate excluded by such an answer may reuse passing evidence at
the source tree only under the same event, declaration and applicable
environment. The receipt retains the source evidence, both trees, selector,
declaration and environment. A selector produces no gate result.

A missing command or answer, a failed, malformed or incomplete answer,
unknown named gates, an absent or mismatching acknowledgment, unobserved
source or paths, or missing green source
evidence runs the required check. A selector that names the gate runs it.
Publication checks every required gate on a changed tree and never uses a delta selector to skip one.

**Status.** Settled on conservative fallback and the coordinates of reuse.
The model takes a typed selector answer, including its acknowledged delta
and declaration set, and the path delta as observations;
it neither executes a selector nor infers the relevance of a path. Receipt
creation plans reuse; appending a production reuse event and retention are
outside its effects. The guide does not define whether a selector editing
its own command must always select its gate; the model grants no source
evidence under a changed gate command, and leaves selector relevance to
the declared command.

**Source.** `arc guide gates`: "includes `complete: true`, `request` equal
to the complete input object, and `gates` naming affected checks"; "Missing,
failed, malformed, incomplete, unknown or mismatched answers run the required
checks". C34 states paths selection; C33 states the separate baseline protocol.

**Realized by.** `planGate`, `ReuseReceipt`, `gateGreenFor`.

### C30. Standalone publication guard

**Rule.** `arc publication --target <branch> --profile <profile>` runs the
complete publication tier at that local branch's current head. The profile
defaults to `local`. Optional `--revision <full-commit-id>` requires the
observed branch head to equal the caller's queued revision, even when two
revisions have the same tree. Passing integration evidence does not satisfy
it, and passing publication evidence at an earlier tree does not satisfy the current
tree. A profile selecting no publication gates owes none unless C33 adds a\nparticipating base-pass gate. This guard is
local: it makes no network request, installs no implicit hook, and needs no
change, patchset or review verdict. Failure names the integrations since the
most recent successful publication pass. `--skip-green` reuses a complete
publication pass at the same tree and environment.

**Status.** Settled. C31 and C32 govern current budgets and raises for fresh
and cached publication, with repository authority from the recorded integration
destination or associated open change, plus the publication tree's additions
and tightenings and current operator policy. An arbitrary branch cannot
authorize its own raise; unavailable repository budget authority leaves
operator constraints binding. C33 requires full execution of participating
base-pass gates, including integration-only ones, since the last successful
publication. C37 requires publication checks to execute alone.
The model receives the resolved branch tree and the
effective declarations for the selected profile. It answers evidence
coverage; running the checks, recording the publication, choosing the
failure's integration interval, recognizing a complete publication receipt,
and retaining its Git objects are effects outside the pure model.

**Source.** The guide, "Files"; `arc publication --help`.

**Realized by.** `publicationAt`, `publicationEvidence`, `gateGreenFor`.

### C31. Current gate budgets and total rules

**Rule.** A raw passing outcome is green only if its selected receipt fits the
budget in force when read, or the busy-host rule below excuses its overrun.
Clock equality passes; one millisecond over fails unless excused.
A budgeted receipt needs `run_ms`; legacy, imported or attested evidence without
it is unmeasured, and `duration_ms` never substitutes. Budget is outside
execution identity: choose the structurally newest eligible receipt first,
then judge timing, without searching older faster passes or implicitly rerunning.
A later reduction changes current applicability, never historical authorization.

The busy-host rule excuses an overrun only with at most 3% more user-space
instructions than the newest eligible reference and at least 25% unrelated
CPU use both before the gate (verification startup to spawn, at least
100 ms) and during it, and only when the clock fits the reference's run time
scaled by the capacity other work left each run, with 25% slack, and only when
the tree clock covers no more than 5% less of the run's waited CPU than it
covered of its reference's. Unattributed
concurrent batches, missing or incomplete counters and host readings, zero
counts, implausibly low instruction rates and a holder or leader with
restricted CPUs grant no excuse. A reference is a clean, unmoved, unexcused
direct pass of the same gate and declaration on the same known host shape,
at this run's tree or a revision leading to its destination, whose clock fits
the budget in force; cached receipts never supply one. The receipt carries
its reference, rule version and thresholds; readers judge with those and the
current budget, never with live load or a replacement reference. Lowering
the budget retires an excuse whose reference stops fitting. An excused run
never becomes a reference, raise evidence or a base-pass seed, including
after a raise. Work references and excuses adopt store format 12 before
publication or import; readers through format 11 refuse it.

The effective budget and total are the minima of applicable destination,
committed head, operator and staging declarations; absence cannot loosen one.
A raise substitutes only its named destination constraint (C32). Enforcement
keys in a `[budget]` table require each required integration gate's budget,
including a gate the destination declares and the change's head removes; a
landing-only table requires none. The advisory `landing` key never changes
acceptance. Validate
every declared profile and the unqualified case after layering: a missing
budget or excessive declaration sum blocks check, accept, integrate and land,
even with green rows or no required gate in the active profile. Publication-only
gates do not enter the integration total. C37 states the only batch discount.

Budget durations are positive whole milliseconds, including exact decimal
units; overflow and submillisecond precision refuse. Without a declared timeout,
a budgeted command has a checked execution limit of ten budgets. Run time
includes output drain and excludes arc admission and preparation; wrapper waits
inside the command still count. Recorded limits and budgets are provenance.
Every accepting path rejudges: verify, status, integration, acceptance, landing,
candidate selection/promotion and publication. The queue stops on a budget
refusal until explicit `verify --rerun` supplies new evidence. Format 9 is
adopted before budget verification/reuse, evidence, authorization or consuming
imports; readers through 8 refuse. Reads alone and budget-free writes do not
adopt it.

**Status.** Settled, except which `[budget]` keys are enforcement keys.
`total` is enforced and `landing` is advisory; the guide does not say whether
`raise`, `raise_per` or `exclude` alone make the table require gate budgets:
(i) only `total` does; (ii) every key but `landing` does. The waited-CPU
condition is settled: `arc guide change-gates` says "beyond 5% less is not
excused", and the conditions `arc guide gates` gives after "only with" are
necessary, not a complete list. A threshold change takes a new rule version,
and a receipt is read under the thresholds it names. The guide states the
condition only among the rule's known limits and names no current rule
version; REPORT.md keeps that as a documentation finding about where the rule
is stated. The model judges no budget, so no reading enters it. The busy-host rule makes no gate green
that the model would refuse: the model's raw pass already assumes C31's
judgment succeeded.

**Source.** `arc guide gates` (budget paragraphs and the busy-host rule:
"The busy-host rule excuses an overrun only with at most 3% more user-space
instructions than the newest eligible reference and at least 25% unrelated
CPU use both before and during the gate"; "Lowering the budget retires an
excuse whose reference stops fitting. Excused runs never become references,
raise evidence or base-pass seeds, including after a raise"; "A threshold
change takes a new rule version"), `arc guide gate-costs` (CPU accounting; "Every required integration gate needs a budget
when enforcement keys exist in that table; a landing-only table requires no
individual budgets"; the landing budget "never changes acceptance"),
`arc guide change-gates` (the rule "is not proof against a change built to
deceive it"; "An exec the counters cannot follow shows as a tree clock
covering less of the run's waited CPU than its reference's did: beyond 5%
less is not excused, and less than that hides"), `arc guide gates-together` (total accounting), `arc verify --help`, `arc publication --help`,
`arc candidate verify --help`, `arc candidate select --help`,
`arc candidate promote --help`, `arc accept --help`, `arc land --help`.

**Realized by.** Nothing: durations, instruction counts, host load, budget
layering, declaration totals, timeouts and store-format admission are outside
the model's observations.
The model's gate result is raw success or failure, qualified by its modeled
coverage; its permission assumes C31's external budget judgment succeeded.

### C32. Raising budgets

**Rule.** A higher committed repository declaration needs an applicable immutable
raise even if every run fits the old budget. Keeping a gate while removing its
budget refuses; removing the total while any gate remains refuses. Removing a
gate, removing all gates with the total, or lowering either needs no raise;
the destination's obligations remain owed by the change. A removed gate keeps
its destination budget; one with none cannot be given one, so a change cannot
both remove it and declare a total. The refusal names the route: land the
removal with no total, then declare budgets and the total in a following
change.

A gate raise needs the newest direct execution at the exact clean stable head,
matching destination command and environment, unexcused (C31), passing above
the destination budget and within the proposed one. Reuse, rewritten coordinates, attestation,
bypass and measurement cannot establish need. A clean accepted batch may.
The increment is `old * raise * min(1, added / raise_per)`, floored to whole
milliseconds with checked arithmetic; trusted defaults are 20% and 500 lines.
Head rules may tighten; requests share one destination basis and final delta
without compounding. The total needs a separate explicit transition: its maximum
declaration cost across all profiles must exceed the old total and fit the new
one and operator ceiling; a new gate can justify it without a gate overrun.

Counting needs destination ancestry containing the declared base.
`arc-budget-growth/2` counts endpoint net nonblank logical-file growth,
subtracting shrinkage/deletions in the same trusted scope, floored at zero.
Pinned rename/copy detection, UTF-8/NUL paths, isolated Git metadata and no
external diff/text conversion prevent host configuration granting credit.
Moves, splits, copies without growth, whitespace, binary/non-UTF-8 files,
symlinks, gitlinks and excluded/custom-diff files grant none. Overlapping globs
count once; intermediate churn and another unintegrated member grant no credit.
Destination/operator paths and inert/exclude rules constrain scope; head rules
may remove growth but cannot remove trusted shrinkage debit. Uncertainty refuses.
Operator ceilings constrain repeated raises; padding/relevance remain review.

The record binds change, destination revision, exact head/tree, growth algorithm,
rule digest, per-file counts, old/new values, allowance, direct execution or
total sum, and reason. Every head/destination change, even signatures or trailers,
requires a fresh record. Missing objects or changed inputs refuse applicability.
A fresh snapshot captures the entire raise set, then ordinary review or debt is
required, even at unchanged Git head. Landing members cannot pool credit.
Integration, acceptance, landing, candidates and publication refuse stale or
missing raises. Imported records are facts, subject to receiver constraints;
format 9 fences older readers. Historical authorization remains fixed.

**Status.** Settled. The removed-gate route restates what the destination's
retained obligation and C31's budget requirement already imply; it changes no
acceptance.

**Source.** `arc guide gate-raises` (the raise need "be unexcused"),
`arc guide gate-costs` ("A removed gate that has a budget on the destination
keeps it; one that has none cannot be given one, so a change cannot both
remove it and declare a total"), `arc gates raise --help`.

**Realized by.** Nothing: counted Git growth, direct timing, immutable raise
sets and snapshot acquisition are outside the model. This is a documented
but unrealized authorization protocol, not an alternative approval waiver.

### C33. Cross-change base passes

**Rule.** Only destination-committed `selection.base_passes = true` opts in;
a change cannot opt itself in. Authoritative completion retains clean stable
local timed integration executions at the installed tree, with declaration,
coverage, environment, profile, source coordinates and digests. Reuse, bypass,
attestation, untimed, excused, over-budget and dirty-waived evidence establish
none.
Empty snapshots establish none and obscure no gate's older entry.

Each gate's first observation may use its newest eligible retained local
baseline in both target and evaluated head first-parent histories. Other
gates' observations do not consume this right. Any prior observation of that
gate at any head, including failure, not-admitted or budget refusal, prevents
it. Search at most eight retained target/profile baselines and select the first
eligible one containing the gate; mismatching declaration/environment/coverage
or budget runs the gate, never an older matching/faster entry. First-parent
walks stop at 256 commits; inconclusive ancestry, missing objects, moved
history, different profile/event or failed probes are cache misses. Commit-bound
gates execute. Rewrites do not advance baseline coordinates.

The complete endpoint diff proves nonimpact using destination coverage and
danger; dangerous and unnamed paths affect every gate and `.arc/` is protected
even beneath inert. Deltas include both rename endpoints, deletions and mode/type
changes; unreadable, invalid or excessive input executes. A declared selector
grants no cross-change reuse. Witnesses cite the immutable baseline/digest,
authority and execution provenance plus retained objects proving adoption,
ancestry and diff; hashes/asserted paths alone are insufficient. Replay validates
structural facts without current budgets; acceptance rejudges original timing.
Imported facts cannot seed local baselines and imported reuse needs admitted
baseline integration authority. Witnesses are bounded to 1 MiB. Format 10 fences
readers/writers through 9 before publication/import, including already-open
writers. Retention keeps eight baseline ref sets; a receipt retains its proof
objects independently.

Landing may consume base passes at complete final content and retains one final
baseline. Candidates consume/create none; provisional preparation creates no
canonical baseline; accept forces executions; publication creates none.
Publication fully executes every participating gate since the previous successful
target/profile publication, including integration-only gates; completion IDs
set the interval. Missing cache snapshots erase no obligation; `--skip-green`
cannot suppress those executions. The destination guard spans checking and
confirmation. Declared coverage remains an assumption that full execution can
falsify.

**Status.** Settled.

**Source.** `arc guide base-passes`, `arc guide gates-together`,
`arc publication --help`, `arc verify --help`, `arc accept --help`.

**Realized by.** Nothing: the model has no cross-change baselines, retention,
authority proofs or Git paths. It does model same-change source selection in
C29. Publication callers must resolve C33's additional obligations externally;
`publicationEvidence` alone does not certify their execution.

### C34. Paths, inert exclusions and coverage identity

**Rule.** Paths use case-sensitive repository-relative globs: `*` stays within
a segment, `**` crosses segments, `**/` includes zero directories, and a trailing
slash selects descendants. Inert paths affect none unless dangerous; dangerous
or unnamed paths affect every gate. A gate with no paths is affected by every
non-inert path; renames check both ends. The complete map spans all events and
profiles. An unreadable danger declaration conservatively affects every path.

Same-change reuse needs a green source under the same declaration/environment.
Path proof may emit selector `arc:paths`; a script is consulted only for a still
affected gate and cannot clear unnamed/dangerous paths when path selection is
declared. An uncertain delta runs the gate. Paths, combined inert lists, the
complete coverage map and dangerous patterns participate in evidence identity;
nonempty coverage requires a fresh identified pass. Target coverage remains
binding until edits land. Different paths for one layered gate conflict.
C29 requires acknowledgment of the entire request; publication runs its changed
tree's complete tier. C33 supplies the stronger cross-change protection.

**Status.** Settled.

**Source.** `arc guide gates`, `arc guide base-passes`,
`arc gates paths --help`.

**Realized by.** C29 models selection from an already observed affected set,
including exact acknowledgment. Filesystem deltas, glob matching, dangerous-path
classification and complete coverage identity are documented but not realized;
`DeclarationShape` represents command, timeout and confinement only. Automatic `arc:paths` proof
and protected `.arc/` validation remain outside the model.

### C35. Admission and exclusive execution

**Rule.** An exclusive name admits one command across account projects/checkouts.
The holder keeps it through its last descendant, even after arc exits; there is
no queue order. Either declaration may require it; omission cannot remove it.
Equal names take the shortest admission limit, default 60s. Different project/
operator names conflict; target/head divergence retains the target's lock.
Lock name and admission are outside execution identity. Expiry starts no command.

Expiry or command exit 75 records `not-admitted`, neither pass nor failure.
Timeout outranks exit 75. The newest such attempt is not green, cannot answer
an earlier failure and prevents fallback to an older pass; verify reruns,
accept refuses it as unobserved, publication with no failing gate records
not-admitted and exits 1. An interrupted gate/probe is killed as a process group
and records no result. Evidence that failed to publish is no evidence.

**Status.** Settled.

**Source.** `arc guide change-gates`, `arc guide gates`,
`arc guide rules-claims`, `arc verify --help`, `arc publication --help`.

**Realized by.** `readGateFor`, `gateGreenFor` model a `GateNotAdmitted`
observation as not green under the newest structural key. Host locks, waiting,
process groups, timeout ordering and evidence publication are external effects.

### C36. Bypass satisfies nothing

**Rule.** A bypass declaration has no effect and a recorded bypass supplies no
integration or publication requirement. It grants no missing measurements,
raise justification or baseline authority.

**Status.** Settled.

**Source.** `arc guide change-gates`: "Recorded bypasses are history and satisfy
no integration or publication requirement"; `arc guide gates` (the `bypass`
key), `arc guide gate-raises`, `arc guide base-passes`.

**Realized by.** `readGateFor`, `gateGreenFor` refuse `Bypassed` evidence.
Parsing retired declarations and old store envelopes is outside the model.

### C37. Concurrent acceptance

**Rule.** Every layered declaration must consent to concurrency. Standalone
gates execute first in name order, then the consenting set. Duplicate exclusive
names are invalid. Five clean stable direct measurement rounds, all passing
with command timing, establish host/store-local acceptance of the exact complete
structural identities and membership, not budget compliance. Failed measurement
removes prior acceptance. Budget, exclusive and admission values do not change
structural identity. Measurement is private, never exported.

Missing/unreadable acceptance or host identity executes standalone; a singleton
or explicit gate executes alone. Reuse/selection precede scheduling, so the
remaining subset needs its own exact acceptance; otherwise standalone costs
apply and may exceed the total. `--rerun` cannot bypass measurement and
`--parallel` remains unqualified preflight with unknown cleanliness.

A batch pass is green only with retained tested tree, clean before/unchanged
after content and head, and current exact local acceptance. Dirty waivers cannot
rescue it. Receipts/authorization retain batch, acceptance, store, host and
member identities; replay validates frozen references without loading current
host administration. Imported batch evidence cannot be green at another store,
even after receiver measurement. Eligible clean batch execution may justify a
raise or baseline, whose use rechecks acceptance. Publication/candidates run
alone. Per integration profile total is standalone sum plus maximum concurrent
budget only for its complete exactly accepted set; otherwise all budgets add.
Landing counts the union once and obeys every member's strictest total. Format
11 fences readers/writers lacking these semantics.

**Status.** Settled.

**Source.** `arc guide gates-together`, `arc gates measure --help`,
`arc verify --help`, `arc land --help`.

**Realized by.** Nothing: scheduling, host measurement, aggregate budgets and
store-format admission are outside the pure model. A raw standalone pass never
establishes a batch permission here.

### C38. Completed bound-run authorship

**Rule.** Explicit contributors, solo or represented subject decide snapshot
attribution. Otherwise local completed dispatches may derive the recorded
contributors at snapshot time, never repair an existing patchset. The inspected
range starts at the previous mapped patchset head or first resolved base, an
ancestor of head. Only proved complete role-appends/signatures with unchanged
implementer sets, readable objects and a recorder outside executor bindings
carry that boundary; other temporally relevant rewrites prevent derivation.

Each delegated commit needs this change's local dispatch, nonconflicting local
implementation binding and end, a dispatch-to-end interval including Git's whole
second committer timestamp without rounding, matching worktree, valid represented
agent coordinate naming the bound harness, and exactly that implementer trailer.
Binding can follow end but not precede dispatch. Covering dispatches agree on
session/model; one executor session keeps one coordinate throughout the range.
Reviewer bindings supply no implementation. Trailers corroborate, never invent,
the ledger's identity. Each executor contributes its bound harness/session and
retained represented model; the first executor in commit order is production's
implementer and all remain authors. Invoker-bound or uncovered own commits add
the invoker. Missing/conflicting/relevant evidence retains recorder attribution
for the whole patchset and names ambiguity. No executor means recorder fallback.

Unchanged snapshots preserve attribution. An explicit different subject at
unchanged content creates a fresh patchset; omission never reverts a subject.
Mechanical replay preserves matching patchset authorship or bound-run attribution
established at the original head before replay. Ordinary rebase grants no
inheritance. Live-claim declaration rules still bind. An unrecorded rewrite
preserving boundary, times and trailers is undetectable.

**Status.** Settled.

**Source.** `arc guide debt-review`, `arc guide change-integration`,
`arc guide rules-evidence`, `arc snapshot --help`, `arc rebase --help`,
`arc trailers --help`.

**Realized by.** `effectiveContributors` and C4 read the resulting recorded
set and ledger models. Deriving it from dispatch, executor session, Git time,
worktree and rewrite proof is outside the model's history vocabulary. The model
accepts recorded patchsets, not unvalidated attribution claims.

### C39. Approval-preserving rewrites

**Rule.** Approval anchors, waiver scope and eligible extent identity follow
signature-only and complete role-addition rewrites. A role addition appends
complete Planned-by, Implemented-by, Reviewed-by or Orchestrated-by entries to
the final trailer block (or a fresh block after one blank line), with all other
headers/tree byte-identical except signature and parents translated only through
eligible rewrites. Replacing/removing/reordering roles, Assisted-by, body edits,
changed committer/extra headers, or ineligible changes below head leave approval
stale; snapshot and fresh judgment are required. Added roles are declared text,
never a review or a change to recorded contributors/production/debt.

The receiver recomputes carry from local objects; incoming maps are judged
together to stable dependency-ordered parent carry irrespective of event order.
Nonstabilizing judgment cycles refuse the whole import. Pending acceptance
signing still requires signature-only. A withdrawn-only proof is set aside on
the withdrawing replica and refuses import elsewhere. Commit-bound gates never
inherit through rewrites (C14); raises never inherit (C32).

**Status.** Settled.

**Source.** `arc guide rewrites-evidence`, `arc history rewrite --help`,
`arc rewrite trailers --help`, `arc guide debt-obligations`.

**Realized by.** Nothing: the model has no rewrite maps or commit bytes. C1,
C5 and C6 consume already resolved patchset/approval facts; neither gate nor
raise carry is inferred from tree equality beyond C14's tree-bound evidence.

### C40. Review clearance, extents and receipts

**Rule.** A read compares its recorded and disagreeing observed reviewer models;
either author match refuses or leaves debt owed. A dated target/operator
`tiebreak_reviewers` election may waive only model-match and, under assessed
clearance, family tests for mixed-model authorship. It requires an exact recorded
model/effort and matching observation, an active nonoverlapping interval at
recording, another canonical author model, and the same destination. It never
waives actor/contributor/author-session/assumed-identity, rank, effort ordering,
authority or coverage. Unreadable elections grant no exception; recorded reads
retain their election or absence despite later policy edits.

Under assessed policy only clearing approvals authorize and only clearing reads
discharge. With no ladder, agent clearance requires model/effort and a bound
assessment/2 with `clears: true`. With a ladder, the destination's authorizing
registry judges integration; its accepted current registry judges later reads,
except a ladder-changing or unread range remains under closure's target-before
registry. Candidate/dirty files supply no authority. Missing closure basis is
not established. Read-time debt uses the stricter checkout/registry policy.
At judgment basis time select the latest dated version; gaps and missing
coordinates are not established. Reader rank meets every author floor; a lower
named effort of the same model never qualifies. Missing effort uses conservative
reader minimum/author maximum. Clearing also needs a family unlike every author's,
subject to the narrow election. Both observed/recorded models meet the bar.
Persons are exempt from model floors, not independence; ineligible-review persons
still need eligible bound assessment. A clearing ladder agent needs none.
Optional assessments must bind, but their capability opinion cannot override
the ladder. Recorded contributors, production implementer and range implementer
trailers all enter clearance authorship. Approval that only finds needs debt;
changes-requested, gate failures and other refusals still bind. Coordinate
admission uses enablement or the strictest inclusive cutoff at recording, while
capability uses judgment basis time; unknown admitted coordinates never clear.

Extents resolve whole or scoped diff/tree entries and blobs before recording;
empty scopes refuse. A read covers only the same domain/base/revision or eligible
successor. Whole covers scoped; scoped must include every obligation entry with
matching blob and exclude none, and never covers whole. Scoped reads do not
combine. An extentless read cannot cover an explicit obligation; two absent
extents leave coverage not established under ordinary rules. Verdicts carry no
extent, so only audit can discharge an explicit extent. Comment-only never
discharges. Assessed policy and extent coverage independently qualify assurance;
partial reads do not refresh it, nor edit-only verdicts on replayed landings.

Receipt ingestion pins subject/frontier and records the reader as represented
subject, the invoker as writer. Receipt-wide errors write nothing; item errors
refuse only that item. Moved subject/frontier or internal contradiction refuses;
identical published items are idempotent. Independence, clearance and binding are
identical to direct reads. Earliest exact visible assistant key/verdict reply in
the exact session within issue/ingestion supplies basis time; absent it declared
judged_at or recorded time applies. Invalid/out-of-window judged_at refuses even
with a reply. Import keeps the basis but receiver registry judges. Source
custody, atomic dispositions and extents require format 7.

**Status.** Settled. The boundary statement scopes arc's model ordering to the
dated ladder a destination commits for assessed clearance, so ladder
capability judgment is part of the rule; no ladder judgment is realized by the
model. Imported facts grant no receiver review authority.

**Source.** `arc guide debt-review`, `arc guide debt-clearance`,
`arc guide debt-obligations`, `arc guide debt-recovery`, `arc guide assurance`,
`arc guide repair` (receipts), `arc guide boundaries` ("arc holds no ranking
of its own: it never scores the coordinates a debt records, and joins or
orders models only against the dated ladder a destination commits for
assessed clearance"), `arc review --help`, `arc audit --help`,
`arc receipt template --help`, `arc review-ladder import --help`.

**Realized by.** Nothing for ladders, observations, elections, extents, receipt
acquisition or dated assurance: those fields are absent. C4/C22 model ordinary
local recorded identities and assessments without these optional protocols.
C22's ordinary comment-only and ineligible-assessment bars are modeled.

### C41. Atomic landing and asserted correspondence

**Rule.** A lands-with component cannot terminally transition a member alone;
open partners require land, abandoned/superseded partners require withdrawal.
Landing includes every open component member, orders dependencies and refuses
cycles, no-ff/contribution targets, incompatible declarations/bindings/locks,
multiple commits under squash policy, or an empty required-gate union. Stack
members retain their bases; other members replay once onto their composed
parent. Conflict abandons with nothing closed. Each keeps its own approval,
policy and obligations; replay beyond an approved base needs debt, derived as
replayed-unread, never declared/imported as a declaration. Only an audit of
what landed discharges that kind. Members cannot pool raises.

The suite runs once at the final content, using every member's strictest
constraints and checking shared receipts on the top member. Missing timing or
a budget refusal (C31), which a busy-host excuse can lift, refuses without
splitting or retry. Pending intent blocks other
terminal transitions. Commit rereads all pins under ordered authority/target/
graph/member locks; movement abandons. One guarded target transaction and one
completion close all members with their own landed ranges and shared original
target-before. Recovery publishes only proved authorized application, abandons
proved unapplied intent, and refuses unexplained movement. Split attempts occur
only after gate failure within max-attempts, preserve components and dependencies,
and close only successfully landed children. Imported completion needs admitted
integration plus debt/waiver capability when applicable, held member patchsets
and source heads; trial replay grants no rewrite map. Replayed original verdicts
read only the edit and grant no landed-range assurance.

An asserted integration of independently replayed commits needs explicit
correspondence matching change/patchset/head/endpoints and every source commit,
oldest first, one-to-one ordered descendants with equal stable patch IDs.
Merges and empty commits refuse. The assertion stays asserted, grants no gate
evidence and is not a landing.

**Status.** Settled.

**Source.** `arc guide change-landing` ("Missing run_ms or a budget refusal
under `arc guide gates` names the member, gate, run time and budget, leaves
the target unmoved and does not trigger splitting or an implicit retry"),
`arc land --help`, `arc close --help`, `arc guide replicas`,
`arc guide debt-obligations`.

**Realized by.** Nothing: the model authorizes one recorded patchset and has
no landing graph, composed range, pending intent, correspondence or replayed debt.
These are documented but unrealized protocols; Git transactions/recovery are
outside the pure boundary. C10's ordinary prerequisites cannot stand in for them.

### C42. External execution and acceptance boundaries

**Rule.** Ordinary gate evidence is open-only. Post-integration attestation
requires the shipped tree, tested revision, command/gate, result, host and runner;
it is a later receipt, never gate evidence, authorization or debt discharge.
Environment probing reads clean evaluated content; an observing report with no
such checkout yields no identity/receipt, whereas integration may create a scratch
checkout. A missing/failed probe is not an environment shared by two runs.
Probe descendants are stopped before using its answer. Publication retains its
own obligations (C30/C33). Acceptance executes local required gates itself,
never suppressing them with imported passes, base passes or ordinary reuse;
it preserves signature-only delivery constraints (C26/C39).

Slot admission/leases, build preparation and host locks supply no passing result.
Cleanup, journal publication, network/forge effects, retention and process
accounting confer no integration authority. Optional per-check timing errors
remain advisory; command outcome decides. Candidate evaluation includes its
tree's additions and tightened budgets; candidate verification exits 1 for a
pass the budget judge refuses; selection and promotion rejudge current
budgets and raises, but consume no base pass and create no baseline.

**Status.** Settled. Candidate verification exits 0 only when every gate run
passes and the budget judge accepts its command time; an over-budget or
unmeasured pass is recorded as a pass, named as refused, and refused as an
evaluation by selection. The candidate model makes no duration judgment.

**Source.** `arc guide change-integration`, `arc guide rules-evidence`,
`arc guide slots`, `arc guide gates`, `arc guide gate-costs`,
`arc guide delivery`, `arc guide candidates`, `arc accept --help`,
`arc verify --help`, `arc candidate select --help`, `arc candidate promote --help`,
`arc candidate verify --help` ("Exits 0 when every gate run passes and the
budget judge of `arc guide gates` accepts its command time, and 1 otherwise:
an over-budget or unmeasured pass is recorded as a pass, its line names the
refusal, and selection refuses it as an evaluation").

**Realized by.** C15 accepts an observed probe identity or its absence.
Checkout selection, receipts after closure, acceptance execution, slots,
preparation, cleanup and candidate timing are outside the model's effects or
not represented. Candidate structural selection remains a separate model;
its permission is conditional on these external current-budget checks.

### C43. Write confinement

**Rule.** A project declares writable roots in `.arc/gates.toml` under
`[confine]`, with `required` defaulting to true. Every command arc runs on a
project's behalf runs under the committed destination's declaration: gates,
selectors, environment probes, preparation, slot identity, invalidate and
warm commands, changelog renderers, and commands in acceptance and
publication scratch checkouts. The checkout being evaluated cannot select its
own authority. Every launch needs an explicit destination scope; a missing
scope refuses the command and names the site. A checkout with no established
destination refuses: a free checkout may use the primary checkout's recorded
owner's destination, an unowned primary checkout its committed branch, and
otherwise destination resolution refuses.

Operator roots supplement destination roots, and either layer can require
enforcement. A change can adopt confinement where the destination has none,
or require enforcement, but cannot widen an existing destination's roots.
Required confinement that cannot be applied, through an unavailable kernel
interface, missing rights or a failed installation, refuses the command;
only `required = false` permits a labelled unconfined fallback. Without the
table, an explicitly scoped command keeps ordinary write authority.

Confinement participates in execution identity. A declaration's identity
binds its declared roots and its `required` flag, so a pass under another
confinement, an unconfined pass included, does not answer a confined
declaration, and evidence that recorded no confinement answers only an
unconfined one. Receipt identity describes the resolved execution, including
automatic roots.

Confinement grants nothing. Programs Git runs from configuration, Git hooks,
and operator `watch --exec` and `events --exec` handlers keep their own
authority; a confined command's writes elsewhere are refused, never
authorized.

**Status.** Settled on scope, refusal and identity. Unsettled on what a change
head's own `[confine]` does before it lands. "Project commands run under the
committed destination's declaration" and "The checkout being evaluated cannot
select its own authority" read as (i) the destination's table alone governs a
change's commands, a head's table taking effect when it lands; "A change can
adopt confinement when the destination has none, or require enforcement, but
cannot widen an existing destination's roots" reads as (ii) a head's
narrowing or adopting table governs its own commands now. Under either, the
guide does not say whether a head that widens the roots is refused or has
its widening ignored. The model takes the effective declaration as an
observation (C12), so neither reading enters it.

**Source.** `arc guide gate-confinement` (scope, layering, resolution,
kernel requirements, receipts: "Confinement participates in execution
identity, so a pass under another declaration, including an unconfined pass,
cannot silently remain green"; "Declaration identity binds declared paths and
the required flag; receipt identity describes resolved execution, including
automatic roots"), `arc guide gates` ("Coverage and confinement require fresh
identity; legacy evidence answers only unconfined, unscoped declarations"),
`arc guide change-gates`, `arc guide sandbox`, `arc changelog --help`,
`arc events --help`, `arc watch --help`.

**Realized by.** `declarationShape`, `readGateFor`: a declaration's
confinement is part of the shape evidence is recognized by. Destination
resolution, launch scope, root validation and expansion, layering, kernel
enforcement and fallback are outside the model.

### C44. Reserved commit identities

**Rule.** A snapshot refuses a patchset containing an introduced commit whose
raw author or committer address uses `.invalid`, `.example`, `.test`,
`.localhost`, `example.com`, `example.org` or `example.net`, subdomains
included; a base override cannot hide an introduced commit. Integration
refuses a recorded patchset carrying such a commit, so one recorded before
the guard cannot reach integration, including through provisional
preparation and multi-change landings. A project's identity-health exception
does not permit a reserved address. The refusal names the commit and the
re-authoring route; a fresh snapshot of the re-authored head is required.

**Status.** Settled on the snapshot and integration refusals. Unsettled on
whether readiness reports a reserved commit: the guide names `snapshot` and
`integrate`, and neither `arc check --help` nor the integration topic lists
a readiness ground for it, so (i) `arc check` reports the change ready and
only integration refuses, or (ii) readiness refuses as integration does.
Also unsettled on which recorded patchsets integration checks: (i) the one it
ships, or (ii) every patchset the change recorded. The model represents no
commit addresses, so neither reading enters it.

**Source.** `arc guide change-integration` ("`snapshot` and `integrate` refuse
a patchset containing a commit whose raw author or committer address uses
.invalid, .example, .test, .localhost, example.com, example.org or
example.net, including subdomains"; "Integration checks recorded patchsets
too, including provisional preparation and multi-change landings"),
`arc snapshot --help` ("Refuses reserved-domain author or committer addresses
in introduced commits, regardless of --base"), `arc integrate --help`
("Refuses recorded patchsets with reserved-domain author or committer
addresses"), `arc guide sandbox` (the identity-health exception).

**Realized by.** Nothing: commit author and committer addresses are Git
object bytes outside the model's patchset. The model's ledger holds the
patchsets a snapshot recorded, and its permission assumes integration's
identity check succeeded.
