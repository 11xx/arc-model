# arc-model contract

The rules the model answers to. Each clause states a rule of arc's
integration authorization, whether the rule is settled, where it comes
from, and the model functions that realize it. The model is checked against
this text; arc's implementation is not a source for it.

## How to read a clause

- **Rule** is what a history, together with what is observed when the
  question is asked, must answer.
- **Status** is *settled*, or *unsettled* with every reading stated. A
  clause is unsettled where arc's public documentation is silent, where two
  documents disagree, or where the documentation at the comparison revision
  and later documentation differ. An unsettled clause names the reading the
  model takes; that reading is a choice, not a finding.
- **Source** names the section of arc's public documentation the rule comes
  from — its `README.md`, a page under `docs/`, the guide `arc` prints with
  no arguments, or a command's `--help` — or says the contract makes the
  decision itself.
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
be approved.

**Source.** `docs/changes.md`, "The model" (patchset, brief).

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

**Source.** `README.md`, "One change, end to end"; `docs/changes.md`, "The
model" (approval staleness, `arc integrate`); `docs/gates.md`, "Exit codes"
(a missing branch).

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

**Source.** `docs/changes.md`, "The model" (a change behind its target must
evaluate the merge; evidence binds to the tree); `docs/gates.md`, "Exit
codes" (11, 14).

**Realized by.** `evaluateDeclared`, `gateEvidence`.

### C4. Contributors and reviewer independence

**Rule.** The effective author of an event is the subject it was recorded
on behalf of, otherwise its actor. A patchset's contributor set is the set
declared for it, or, where none was declared, its effective author alone.
Where independent review is required, an approval is rejected when its
effective author is a contributor to the patchset it approves, or when arc
assumed the reviewing identity rather than anyone declaring it.
Independence is judged against the patchset the verdict binds to, never
against a later one. A rejected self-approval is no approval (C5), and a
waiver bound to the same patchset can rescue it (C6).

**Status.** Unsettled: when independent review is required.

- (i) A change that touches a declared danger path, or was raised with
  `arc begin --dangerous`, requires a verdict from somebody other than its
  author, whatever `forbid_self_approval` says (`docs/review.md`,
  "Dangerous surfaces"; the guide, "When no independent reviewer is
  reachable").
- (ii) Independence is required only where the change is dangerous *and*
  `forbid_self_approval` is on; with the policy off, a self-approval is
  recorded, counts, and leaves an independent-review debt owed
  (`docs/review.md`, "Policy" and "External verdicts": "On a dangerous path,
  it never satisfies `forbid_self_approval`").

The model reads (ii).

**Source.** `docs/identity.md`, "Identity" (effective author);
`docs/review.md`, "Policy", "Dangerous surfaces"; the guide, "When no
independent reviewer is reachable".

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

**Status.** Unsettled on two points.

- *A new patchset at an unchanged head.* Changing the brief records a new
  patchset without a new commit.
  - (i) The approval binds to the patchset, so it is stale on the new one,
    as a waiver is (`docs/review.md`, "What a debt records": a debt "stops
    applying the moment `ps-02` is snapshotted, exactly as an approval goes
    stale").
  - (ii) The approval is valid while the branch head equals the approved
    head (`docs/changes.md`, "The model": "a verdict is valid only while the
    branch head equals the approved patchset head").

  The model reads (i).
- *An approval after a recorded history rewrite.*
  - (i) An approval never survives a rewrite: only a content comparison
    could say a rewritten head is the same work (`docs/history.md` at the
    comparison revision).
  - (ii) An approval follows a recorded rewrite only when the successor
    differs from the approved head in nothing but its signature, as judged
    when the mapping was recorded; any other successor leaves it stale, and
    once a change has closed its approval follows every rewrite
    (`docs/history.md`, later revisions).
  - (iii) An approval follows every recorded rewrite, as patchsets, gate
    evidence, and waivers do.

  The model records no rewrite, so it takes none of the three; rewrites are
  unsupported.

**Source.** `docs/review.md`, "Verdicts"; `docs/changes.md`, "The model"
(approval staleness); `docs/history.md`, "History rewrites".

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

**Status.** Settled.

**Source.** `docs/review.md`, "Review coverage and post-integration
audits", "What a debt records"; `docs/changes.md`, "The model" (the
authorization basis records the debt declaration when that waiver let the
approval stand).

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

The documentation speaks of "the debt declaration", in the singular. The
model reads (i).

**Source.** `docs/review.md`, "What a debt records" (the waiver binds to
the exact patchset head); `docs/changes.md`, "The model" (the authorization
basis).

**Realized by.** `newestWaiver`, `debtsForPatchset`.

### C8. A refusing verdict is not waivable

**Rule.** A governing changes-requested or comment-only verdict on the
current patchset refuses the integration, and no debt clears it: a debt
records a missing review, and a refusal is a review that was given. A
refusal bound to an earlier patchset does not refuse the current one; the
new patchset is what answers it.

**Status.** Settled.

**Source.** `docs/review.md`, "Review coverage and post-integration audits"
("debt records a missing review and does not override a refusal"); the
guide, "When no independent reviewer is reachable"; `arc integrate --help`,
`--debt`.

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
  the rewrite, as other recorded revisions do (`docs/history.md`, "every
  derived reading answers in the revisions this repository holds"). (ii) It
  names the old revision and stops matching. Rewrites are unsupported in
  the model.

**Source.** `docs/review.md`, "External verdicts"; `docs/gates.md`, "Build
and gate declaration"; the guide, "When no independent reviewer is
reachable".

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

**Source.** `README.md`, "One change, end to end"; `docs/changes.md`, "The
model" (`arc integrate`, holds, claims), "Opening a change"; `docs/gates.md`,
"Exit codes".

**Realized by.** `findingResolved`, `openBlockingFindings`,
`evaluateDeclared`.

### C11. An iterating change and the missing approval (question c)

**Rule.** A change that declares it is iterating is refused on that ground
until the declaration is cleared.

**Status.** Unsettled: whether it also owes the missing-approval ground.

- (i) Iterating is one more ground. Every other ground still stands beside
  it, so an iterating change with no approval is refused on both.
- (ii) Iterating replaces the review request: `arc check` "reports the
  typed `iterating` blocker instead of requesting a review", and the review
  guidance applies only to non-iterating changes, so the missing approval is
  not reported while the change iterates.

The model reads (i).

**Source.** `docs/changes.md`, "Opening a change"; `docs/review.md`,
"Review coverage and post-integration audits" (`review_options` for a
"non-iterating change").

**Realized by.** `evaluateDeclared`.

### C12. Gate declarations

**Rule.** A gate is declared by name with a command, an optional timeout,
optional profiles, and an optional environment probe. Evidence is
recognized by the command and timeout it ran under, so a declaration edited
after its evidence was recorded is a check that has not run
(`declaration_changed`). Which gates are required follows the change's
profile; a change whose profile requires no gate owes no gate evidence and
integrates on its approval alone. A gate that is required but has no
declaration is refused like missing evidence. Two policy layers declaring
one gate name with a different command or a different environment probe are
in conflict. The check refuses, and no other ground is evaluated, because
there is no declaration set to evaluate against. Execution refuses too.

**Status.** Settled, except where declarations are read from:

- (i) The invoking checkout's `.arc/gates.toml`, together with the
  operator's gates (`docs/gates.md` at the comparison revision).
- (ii) `.arc/gates.toml` committed on the change's target branch at its
  current head, together with the operator's gates, plus gates the change's
  own head declares under names the target does not. A change can add gates
  but can neither delete nor weaken one, and a target that cannot be
  resolved leaves the change blocked (`docs/gates.md`, later revisions).

The model takes the effective declaration set, the required gates, and the
conflicting names as observations, so it is neutral between the readings.
That a required gate with no declaration is refused is a decision the
contract makes: an unknown is never success (C13).

**Source.** `docs/gates.md`, "Build and gate declaration";
`docs/configuration.md`, "Repository policy"; `docs/changes.md`, "The model"
(a gate is green for the declaration it ran).

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
attested. Falsification is advisory and never blocks. A gate is
discriminating when any passing evidence for it at the counted revision
names a falsification, not only the newest run.

**Status.** Settled. That an unreadable record is not a result is a
decision the contract makes; the documentation does not describe unreadable
records.

**Source.** `docs/gates.md`, "Build and gate declaration" (attested
evidence, retention, `discrimination`); `docs/changes.md`, "The model"
(evidence binds to the tree; a gate is green for the declaration it ran).

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

**Status.** Settled for the rule above. Unsettled for which record answers
among several that all match the evaluated tree, declaration, and
environment:

- (i) The newest decides: a later failing, dirty, or unreadable run
  replaces an earlier pass (`docs/gates.md`: evidence already recorded
  "cannot be repaired by cleaning; only a fresh run replaces it").
- (ii) Any matching record that passed and counts suffices.

The model reads (i).

**Source.** `docs/changes.md`, "The model" (evidence binds to the tree;
"two commits with one tree are one evaluation"; an unchanged tree reads
"inherited from `<revision>`"); `docs/gates.md`, "Build and gate
declaration".

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

**Source.** `docs/changes.md`, "The model" (a gate may declare the
environment its evidence applies to).

**Realized by.** `readGate`, `gateEvidence`.

### C16. Dirty worktrees and the dirty-tree waiver

**Rule.** Evidence that arc ran on a worktree holding uncommitted changes is
recorded and does not count: no checkout of its revision reproduces the tree
it read. Evidence whose worktree state is unknown does not count either.
Attested evidence carries its own execution context and no worktree state.
A dirty-tree waiver, declared with a reason, lets dirty evidence count; it
binds to the head it was declared at, and the next commit ends it.

**Status.** Settled, except:

- *Several waivers at different heads.* (i) Only the newest is in force.
  (ii) Each covers the head it names. The model reads (i).
- *Dirty evidence evaluated at a later commit with the same tree.* (i) The
  waiver covers evidence recorded at its head wherever that evidence
  answers (C14). (ii) The next commit ends the waiver, so it no longer
  covers that evidence. The model reads (i).

**Source.** `arc verify --help`, `--waive-dirty`; `docs/gates.md`, "Build
and gate declaration" (dirty evidence, unknown cleanliness, attested
evidence).

**Realized by.** `dirtyTreeWaiver`, `readGate`, `gateEvidence`.

### C17. Acceptance probes

**Rule.** Every acceptance probe declared on the brief a patchset binds to
blocks until evidence bound to that brief fails at the brief's base
(baseline) and passes at the patchset's head (final). The pair proves
discrimination, not relevance.

**Status.** Settled, except:

- *A brief whose base is the head, or that names no base.* (i) Nothing can
  fail at the base apart from the head, and a failure and a pass at one
  revision contradict each other, so the probe cannot be discharged. (ii) A
  baseline failure and a final pass satisfy the rule as written, whatever
  revisions they share. The model reads (i).
- *Several runs of one probe in one phase at one revision.* (i) The newest
  decides. (ii) Any run with the expected result suffices. The model reads
  (i).

**Source.** `docs/workspace.md`, "Acceptance probes"; `docs/changes.md`,
"The model" (brief).

**Realized by.** `briefOf`, `newestProbeRun`, `probeRefusals`.

### C18. Declared actors

**Rule.** Under `require_declared_actor`, an event whose effective author
nobody claimed is refused. `integrate` checks this before it merges.
Reading is unaffected, so a readiness check does not refuse an undeclared
invoker. A declared `--on-behalf-of` subject satisfies the policy.

**Status.** Settled.

**Source.** `docs/review.md`, "Contributing to a repository you do not
own" (the `require_declared_actor` paragraph); `docs/identity.md`,
"Identity".

**Realized by.** `evaluateDeclared`.

### C19. The decision basis

**Rule.** A permission names what it rests on: the patchset, its head, the
evaluated tree, the target branch and where it stood, the policy, the
authorization (the approving verdict, the debt when the waiver let the
approval stand, or the external decision), one covered passing evaluation
per required gate, each prerequisite's closure, and the blocking-finding and
hold vectors that had to be empty. A refusal names the facts that stood in
the way.

**Status.** Settled.

**Source.** `docs/changes.md`, "The model" (the authorization basis a
guarded merge records).

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
  down. The model reads (ii).
- *A refused decision in a store without authority.* Both refuse; which
  refusal answers first is not stated. (i) The missing authority answers,
  since the store is refused before readiness is read. (ii) The decision's
  own refusal answers. The model reads (ii).

**Source.** `docs/changes.md`, "The model" (`arc integrate`, the
authorization basis, "readiness is recomputed and the basis rebuilt");
`docs/replicas.md`, "Move authority"; `docs/review.md`, "Policy".

**Realized by.** `execute`, `recordIntegration`.

### C21. Debt kinds and the owed review

**Rule.** A debt names what kind of review is missing: `nothing-read`,
`merge-resolution-unread`, `repair-unread`, `contributor-only`, or
`independent-review`. A declared kind wins over the derived one. The ledger
cannot tell a merge resolution from a repair, so those two kinds are never
derived. Where no kind is declared, a debt on a change with no verdict on
any patchset is `nothing-read`, and one whose shipped patchset carries
verdicts only from its contributors is `contributor-only`. The
owed-review projection reports, for the latest patchset, a covering read, a
standing refusal (C8), a waiver in force (C6), or the kind of review still
owed.

**Status.** Settled, except for the derived kind of a debt on a patchset
with no verdict of its own when earlier patchsets of the change carry
verdicts. The documented derived kinds do not cover it. (i)
`nothing-read`. (ii) `independent-review`, the general case. (iii) No
derived kind; only a declaration answers. The model reads (i).

**Source.** `docs/review.md`, "What a debt records"; `arc debt --help`,
`--kind`.

**Realized by.** `debtKindFor`, `reviewObligation`.

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
  elsewhere. (ii) It is always refused (`docs/review.md`, "What a debt
  records": "an approving audit must come from another identity"). (iii) An
  assumed auditor is refused whatever the policy, and a declared contributor
  is recorded without effect (`docs/review.md`, the `require_declared_actor`
  paragraph). The model reads (i).
- *Approval beside a later negative audit.* Whether a later negative audit
  withdraws an approval that shipped: (i) the approval stands and the
  audit's verdict is its own fact; (ii) the approval is withdrawn. The model
  reads (i).
- *A repair after a fulfilling audit.* (i) It starts a fresh obligation.
  (ii) The fulfilled read survives. The model reads (i).

**Source.** `docs/review.md`, "Review coverage and post-integration
audits", "What a debt records"; the guide, "When no independent reviewer is
reachable" (discharge; "discharging the debt does not mean approval").

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
precedence among them. An order stated without a reason would be a second
semantics that nothing constrains. Refusals at execution (C20) are a
separate question and remain unsettled there.

**Source.** A decision the contract makes; `docs/gates.md`, "Exit codes";
`docs/changes.md`, "Context awareness" (`check --json` reports every
blocker).

**Realized by.** `evaluate`, `refusals`, `decide`.
