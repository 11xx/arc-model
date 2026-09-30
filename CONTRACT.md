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
  contract makes the decision itself.
- **Realized by** names the model functions that implement the rule. Each
  of them carries a comment naming the clause.

A disagreement between a clause and the model is recorded in `REPORT.md`,
under "Open decisions against the contract", and is adjudicated there, not
by editing either side to match.

## Scope

The contract covers the authorization of an existing arc revision, the one
`comparisonRevision` names. The proposed candidate protocol
(`Arc.Candidate.*`) states semantics no arc revision implements and has its
own open decisions in `REPORT.md`; it is outside this contract. So are Git
effects, durability, locking, forks, and the other items `REPORT.md` lists
under "Known unsupported semantics".

## Clauses

### C1. Patchset identity

**Rule.** A patchset is an immutable snapshot of a change's branch: a base,
a head revision, the head's tree, the contributors whose work it carries,
and the brief in force when it was recorded. Verdicts, waivers, and probe
evidence bind to a patchset, never to a branch name. The latest recorded
patchset is the one an integration would ship. A change with no patchset has
nothing to authorize and is refused.

**Status.** Settled. The refusal of a change with no patchset is a decision
the contract makes: approvals bind to patchsets, so without one nothing can
be approved. The guide lets a patchset's contributors be amended until the
first verdict on it; after that they are fixed, which is all C4 reads.

**Source.** `arc snapshot --help` (`--base`, `--brief-version`,
`--contributors`, `--amend`); the guide, "Rules that change what you do" (a
verdict binds to the exact approved patchset head) and "When no independent
reviewer is reachable" (coverage is measured against the final patchset;
attribution is repaired only before any verdict); `README.md`, "One change,
end to end" (`arc integrate` merges only the patchset a verdict approved).

**Realized by.** `effectiveContributors`, `latestPatchset`,
`patchsetById`, `evaluateDeclared`.

### C2. The observed head

**Rule.** An integration is refused unless the branch head observed when
the question is asked equals the latest patchset's head: any new commit
invalidates what was decided about the old head. A change whose branch is
gone has no head, and is refused on that ground rather than compared with
anything.

**Status.** Settled. arc reports a moved head as no valid approval and gates
not green, since both bind to the head; the model names the moved head as
its own ground. That is vocabulary, and C23 makes it presentation.

**Source.** `README.md`, "One change, end to end" (a new commit makes the
approval stale); the guide, "Rules that change what you do" (any new commit
makes the approval stale) and "Exit codes" (6, a missing branch).

**Realized by.** `evaluateDeclared`, `execute`.

### C3. The exact evaluated tree

**Rule.** The tree an integration would ship is the one gate evidence must
answer. Where the head already contains its target, that is the head's own
tree. Where the head is behind a target that moved and the two merge
cleanly, it is the merge's tree, which neither branch committed, and a
change none of whose required gates was evaluated at that tree is refused
(`merged-tree-unevaluated`). Where the merge does not resolve, there is no
single tree to evaluate and the change is refused as needing a rebase.

**Status.** Settled.

**Source.** The guide, "Rules that change what you do" (gate evidence binds
to a tree; a change behind its target is refused with
`merged-tree-unevaluated` until the merge is evaluated) and "Exit codes" (11,
14); `arc verify --help`, `--against`.

**Realized by.** `evaluateDeclared`, `gateEvidence`.

### C4. Contributors and reviewer independence

**Rule.** The effective author of an event is the subject it was recorded
on behalf of, otherwise its actor. A patchset's contributor set is the set
declared for it when nonempty, otherwise its effective author alone.
Where independent review is required, an approval is rejected when its
effective author is a contributor to the patchset it approves, or when arc
assumed the reviewing identity rather than anyone declaring it.
Independence is judged against the patchset the verdict binds to, never
against a later one. A rejected self-approval is no approval (C5), and a
waiver bound to the same patchset can rescue it (C6).

**Status.** Settled on the effective author and contributor fallback.
Unsettled on when independent review is required.

- *When independent review is required.*
  - (i) A change that touches a declared danger path, or was raised with
    `arc begin --dangerous`, requires a verdict from somebody other than its
    author, whatever `forbid_self_approval` says (the guide, "When no
    independent reviewer is reachable": "A change touching a declared path
    needs a verdict from somebody other than its author"; `arc begin
    --help`, `--dangerous`).
  - (ii) Independence is required only where the change is dangerous *and*
    `forbid_self_approval` is on; with the policy off, a self-approval is
    recorded, counts, and leaves an independent-review debt owed (the same
    section: "Where `forbid_self_approval` is off, an approving verdict from
    the identity that wrote the work is recorded rather than refused").

  The model reads (ii).
**Source.** The guide, "When no independent reviewer is reachable":
"An event's effective author is its `--on-behalf-of` subject when set,
otherwise its actor. A patchset's effective contributors are its recorded
set when nonempty, otherwise its effective author alone." The same section
states that independence is judged against the patchset a reviewer read,
and an assumed reviewing identity cannot be the second party; `arc begin
--help`, `--dangerous`; each command's `--help`, `--on-behalf-of`.

**Realized by.** `effectiveActor`, `effectiveContributors`,
`authorizationFor`.

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

The model reads (i). An approval after a recorded history rewrite follows
the rewrite only when the successor differs from the approved head in nothing
but its signature, as judged when the mapping was recorded or imported, and
any other successor leaves it stale. What happens to the approval of a
change that has already closed is not stated. The model records no rewrite,
so rewrites are unsupported.

**Source.** The guide, "When no independent reviewer is reachable" (the
verdict chain, contested verdicts, provisional verdicts), "Rules that
change what you do" (staleness), and "History rewrites"; `arc review
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
integration's recorded basis names the debt only when the waiver is what
let the approval stand; a debt declared beside an approval that needed no
waiver authorized nothing and is not an authorization input.

**Status.** Settled, except where C5 and C19 are open. The
guide binds a debt to "the exact patchset head declared", which is C5's
question for a later patchset at the same head; the model reads the
patchset there too. That a debt declared after integration waives nothing
is a decision the contract makes: nothing is left to authorize. What the
recorded basis names is C19's.

**Source.** The guide, "When no independent reviewer is reachable" (the
debt "can stand in for an absent verdict or rescue a self-approval rejected
by repository policy"; it "binds to the exact patchset head declared, so
new work needs a new declaration"); `arc integrate --help`, `--debt`.

**Realized by.** `debtsForPatchset`, `newestWaiver`, `authorizationFor`,
`waiverUsed`, `debtsNotUsed`.

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

**Source.** The guide, "When no independent reviewer is reachable" (the
waiver binds to the exact patchset head declared).

**Realized by.** `newestWaiver`, `debtsForPatchset`.

### C8. A refusing verdict is not waivable

**Rule.** A governing changes-requested or comment-only verdict on the
current patchset refuses the integration, and no debt clears it: a debt
records a missing review, and a refusal is a review that was given. A
refusal bound to an earlier patchset does not refuse the current one; the
new patchset is what answers it.

**Status.** Settled.

**Source.** The guide, "When no independent reviewer is reachable" ("A
current `changes-requested` or `comment-only` verdict is its own next action
and offers no debt route: a waiver records a missing review, not a way past
a refusal"); `arc integrate --help`, `--debt`.

**Realized by.** `authorizationFor`, `reviewObligation`.

### C9. External verdicts

**Rule.** An external verdict records a decision made outside arc about an
exact revision. It gates only where that revision equals the current
patchset head. An external approval authorizes where independent review is
not required (C4) and no local changes-requested or comment-only verdict
refuses the current patchset. It never supersedes a local refusal, never
satisfies independent review, and is never an independent read for coverage
(C22), because arc cannot verify who decided. An external rejection of the
current head closes the change as abandoned.

**Status.** Settled, except:

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

**Source.** The guide, "When no independent reviewer is reachable" (an
external decision is recorded "beside, never as, a verdict arc witnessed";
an approval "gates only the revision it names and never alone on a
dangerous path"; it "never supersedes a local refusal"; "A change request
carries findings, and a rejection of the head closes the change"); `arc
external verdict --help`.

**Realized by.** `externalVerdictAt`, `authorizationFor`,
`coverageAfterIntegration`.

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

Claims are advisory liveness and refuse nothing.

**Status.** Settled.

**Source.** `README.md`, "One change, end to end" (no open blocking
finding, no active hold, every prerequisite integrated); the guide, "Rules
that change what you do" (claims are advisory, never locks) and "Exit
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
optional profiles, and an optional environment probe. The declarations in
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

**Status.** Settled, except which fields of a declaration its evidence
answers. The guide says the run "under the declared gate" decides, and that
two layers agreeing on command and probe combine with the shorter timeout.
(i) The command and the timeout: evidence run under another timeout is
under another declaration. (ii) The command alone, with the probe read
through C15. The model reads (i).

The model takes the effective declaration set, the required gates, and the
conflicting names as observations. That a required gate with no declaration
is refused is a decision the contract makes: an unknown is never success
(C13).

**Source.** The guide, "Run a change" (required gates are read from the
target branch plus the gates the change adds; `target-unreadable`; a
profile with no declared gate runs none), "When no independent reviewer is
reachable" (layers combine by name; the same name with a different command
or probe is a conflict that `arc check` and gate execution refuse), "Rules
that change what you do" (the run under the declared gate decides), and
"Files" (the `[gates.<name>]` table); `arc policy --help`.

**Realized by.** `declarationShape`, `evaluate`, `gateEvidence`,
`execute`.

### C13. The four gate readings

**Rule.** A required gate is read four ways, kept apart:

- **pass/fail**: what the run reported;
- **coverage**: whether the run answers the declaration, the evaluated
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

**Rule.** Evidence is keyed by the tree the run read, the declaration it
ran, and the environment it recorded. Two commits with one tree are one
evaluation, so evidence recorded at an earlier revision answers a later head
with the same tree. A record at another tree, under another declaration, or
from another environment never answers the gate at the evaluated tree, and
never hides a record that does. With an older pass at tree A and a newer run
at tree B, evaluated at A, the run at B says nothing: the answer comes from
the records at A.

Among several records under the key, the newest decides: a later failing,
dirty, or unreadable run replaces an earlier pass. A record at the
evaluated tree that carries no environment, for a gate that declares a
probe, is not under the key in force, so it answers nothing (C15) and hides
nothing.

**Status.** Settled.

**Source.** The guide, "Rules that change what you do": "Gate evidence
binds to a tree, not to a commit"; the gate line reads "`inherited from
<revision>` wherever the run that answered was against another commit
holding that tree"; "The newest run at the evaluated tree under the
declared gate and applicable environment decides; other runs cannot hide
it".

**Realized by.** `readGate`.

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

### C18. Declared actors

**Rule.** Under `require_declared_actor`, an event whose effective author
nobody claimed is refused. `integrate` checks this before it merges.
Reading is unaffected, so a readiness check does not refuse an undeclared
invoker. A declared `--on-behalf-of` subject satisfies the policy.

**Status.** Settled. The guide makes an undeclared identity "a refusal
instead of a record", so a command that records nothing refuses nothing,
and `integrate`, which records, refuses. That a declared subject satisfies
the policy follows C4's reading of the effective author.

**Source.** The guide, "Say who you are" (the `require_declared_actor`
paragraph) and "Files" (`[policy] require_declared_actor`).

**Realized by.** `evaluateDeclared`.

### C19. The decision basis

**Rule.** A permission names what it rests on: the patchset, its head, the
evaluated tree, the target branch and where it stood, the policy, the
authorization (the approving verdict, the debt when the waiver let the
approval stand, or the external decision), one covered passing evaluation
per required gate, each prerequisite's closure, and the blocking-finding and
hold vectors that had to be empty. A refusal names the facts that stood in
the way.

**Status.** Settled on the integration basis's contents. The guide also
names an approving verdict's provisional reason, an external approval when
consumed, normalized gate and policy values, and the danger determination.
The model's basis identifies verdicts and gate declarations and carries the
effective policy; it does not model provisional reasons or the provenance
of the danger determination. The coverage channel compares the
authorization slots only, not the full recorded basis.

Unsettled on whether declaration values in the basis are read committed or
uncommitted: (i) values from committed declaration files; (ii) values from
the checkout including local edits. The guide states what is recorded but
does not settle this observation boundary for every declaration layer. The
model takes declaration and policy values as observations, without choosing
how files supplied them. C12 specifies the target as the project source;
it does not settle the operator layer's observation boundary.

**Source.** The guide, "Run a change", the paragraph beginning "A guarded
integration records the shipped patchset and head": it enumerates the basis,
including "the normalized gate and policy values consumed, and the danger
determination", and records a debt only when its waiver supplied the
approval or let it stand. `integrate --dry-run` prints the basis; readiness
and the basis are rebuilt before merging. The facts C1 to C18 read name the
model's corresponding slots; the guide, "Exit codes", names refusals.

**Realized by.** `evaluateDeclared`, `authorizationFor`, `gateEvidence`.

### C20. Execution

**Rule.** Permission is not effect. A decision records nothing; only an
integration puts its basis in the ledger, and it records the basis it was
taken on. Before acting, readiness is computed again and the basis rebuilt,
and if the two differ nothing is written. A store paired with replicas acts
only while it holds integration authority; a readiness check does not
consult authority. A missing branch or conflicting declarations leave
nothing to act on.

**Status.** Settled, except:

- *Policy motion.* A policy that changes between a decision and the
  integration: (i) the integration re-decides under the policy in force when
  it runs, since integration reads policy from the target at its current
  head; (ii) the earlier decision's basis moved, and the integration stands
  down. The model reads (ii). Project policy is committed on the target, so
  moving it moves the target too (C12), and the change then evaluates a
  merge nobody evaluated (C3) under either reading; the readings part only
  where no gate is required, or where the operator's layer moves.
- *A refused decision in a store without authority.* Both refuse; which
  refusal answers first is not stated. (i) The missing authority answers,
  since the store is refused before readiness is read. (ii) The decision's
  own refusal answers. The model reads (ii).

**Source.** The guide, "Exit codes" (`integrate` refuses in `check`'s
vocabulary; exit 17 for a replica without authority), "Rules that change
what you do" (a single `integrate` checks that its merge carries the
evaluated tree and undoes it otherwise), "Pair replica stores" ("A paired
replica without authority is refused by `integrate`"), and "Files" (policy
is read from the change's target branch); `arc integrate --help`,
`--dry-run`.

**Realized by.** `execute`, `recordIntegration`.

### C21. Debt kinds and the owed review

**Rule.** A debt names what kind of review is missing: `nothing-read`,
`merge-resolution-unread`, `repair-unread`, `contributor-only`, or
`independent-review`. A declared kind wins over the derived one. The ledger
sees a merge resolution and a repair the same way, so only a declaration
names `merge-resolution-unread`; the ledger derives the other four. Where no
kind is declared, the kind of a debt on a patchset is:

- `nothing-read` where no patchset of the change carries a verdict;
- `contributor-only` where that patchset carries verdicts, all of them from
  its contributors;
- `repair-unread` where that patchset carries no verdict and an earlier
  patchset of the change carries an approval;
- `independent-review` otherwise.

The owed-review projection reports, for the latest patchset, a covering
read, a standing refusal (C8), a waiver in force (C6), or the kind of
review still owed, derived the same way for that patchset.

**Status.** Settled, except for a patchset with no verdict of its own when
earlier patchsets of the change carry verdicts and none of them is an
approval. No documented kind names that history. (i) `independent-review`,
the general case. (ii) No derived kind; only a declaration answers. The
model reads (i). `nothing-read` is not a reading: the documentation defines
it as no verdict on any patchset.

**Source.** The guide, "When no independent reviewer is reachable" (the
table of kinds; "Only the caller can say a resolution was what went unread,
because the ledger sees a repair and a merge resolution the same way";
`review_options`); `arc debt --help`, `--kind`.

**Realized by.** `debtKindFor`, `derivedKind`, `reviewObligation`.

### C22. Audits, and why a fulfilled read is not an approval

**Rule.** An audit is a review recorded after integration, anchored to the
revision that shipped. It is refused while the change is open. It never
rewrites the answer to what shipped on what review: the recorded
authorization of an integration is fixed when the integration is recorded.
Audit findings are a separate set from the shipped findings. Auditing into
changes-requested is open to anyone. An approving audit discharges an
obligation only when it comes from a declared identity that is not a
contributor to the shipped patchset. Any independent verdict on the shipped
revision, recorded after the debt, fulfils the owed read, whether it came
before the merge or in an audit after it. A fulfilled read is not an
approval: a negative audit can fulfil the read and leave its findings open,
and what the reader concluded stays in its verdict and findings.

**Status.** Settled, except:

- *A non-independent approving audit.* (i) It is refused where policy
  forbids self-approval, and recorded without discharging anything
  elsewhere (the guide: "Where `forbid_self_approval` is off, an approving
  verdict from the identity that wrote the work is recorded rather than
  refused, and `arc review` and `arc audit` both name the match"). (ii) It
  is always refused (the guide: "An approving audit must come from an
  identity other than the author"). (iii) An assumed auditor is refused
  whatever the policy, and a declared contributor is recorded without
  effect (the guide: an assumed reviewing identity "cannot be the second
  party"). The model reads (i).
- *Approval beside a later negative audit.* Whether a later negative audit
  withdraws an approval that shipped: (i) the approval stands and the
  audit's verdict is its own fact; (ii) the approval is withdrawn. The model
  reads (i).
- *A repair after a fulfilling audit.* (i) It starts a fresh obligation.
  (ii) The fulfilled read survives. The model reads (i).

**Source.** The guide, "When no independent reviewer is reachable" (an
audit "never rewrites what shipped with what review"; "anyone may audit
into `changes-requested`"; discharge; "discharging the debt does not mean
approval"); `arc audit --help`.

**Realized by.** `admitAudit`, `auditDischarges`, `auditIsIndependent`,
`coverageAfterIntegration`, `openAuditFindings`, `latestIntegration`,
`historicalAuthorization`.

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
precedence among them: `arc check --help` has the exit code name "the first
blocker", which fixes a display order and states no reason for it. An order
stated without a reason would be a second semantics that nothing
constrains. Refusals at execution (C20) are a separate question and remain
unsettled there.

**Source.** A decision the contract makes; the guide, "Exit codes"; `arc
check --help` (`--json` emits all blockers).

**Realized by.** `evaluate`, `refusals`, `decide`.
