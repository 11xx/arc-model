# Authorization text audit

The complete guide diff from b405104a to the pinned 35f9501d text retains every
changed sentence; this table classifies every hunk by its new guide line. Clause numbers refer to CONTRACT.md.
"Modeled" means the model represents the rule; "unrealized" means the contract
states it and the model does not represent it; "outside" means it confers or
removes no integration, landing, promotion, publication or acceptance
permission. An outside classification grants no modeled permission.

| old guide line | new guide line | route | authorization classification |
| --- | --- | --- | --- |
| 14 | 14 | overview | Outside: run-time guide topics |
| 129 | 130 | identity-events | Outside: journal workbench listing is read-only |
| 592 | 593 | sandbox | Outside: inherited Git selectors are scrubbed from project commands; Git configuration health is diagnostic and never repairs or refuses |
| 618 | 641 | sandbox | Outside: sandbox clone of workbench content |
| 1112 | 1136 | change-gates | C43, unrealized: every gate runs under write confinement |
| 1147 | 1172 | change-gates | C31, unrealized: the busy-host rule's stated limits (outside work counts as other load, narrowed CPU sets) and the waited-CPU condition: a tree clock covering more than 5% less of the run's waited CPU than its reference's is not excused (E6) |
| 1262 | 1299 | change-integration | C44, unrealized: reserved commit addresses refuse snapshot and integration, including earlier recorded patchsets |
| 1547 | 1593 | change-landing | C31/C41, unrealized: landing refuses what the budget judge refuses, which now admits a busy-host excuse |
| 1738 | 1784 | change-finalization | C43, outside the model: changelog renderers run confined; changelog confers no authority |
| 2094 | 2140 | journal-references | Outside: pinned guide topics |
| 2162 | 2210 | journal-workbenches | Outside: journal workbenches |
| 2781 | 2916 | debt-review | C4, modeled: independence is required only inside the danger gate with forbid_self_approval on (closes D4) |
| 2866 | 3002 | debt-obligations | C21/C28, modeled for /1 without review_clearance: a plan refuses an assessment under which the read clears (closes D5) |
| 2932 | 3068 | debt-obligations | C22, modeled: an assessment binds to the read's model and the range's coordinates |
| 2981 | 3122 | debt-obligations | C22, modeled: an assessed verdict clears ineligible-review; an unassessed, ineligible or unbound verdict leaves it open (closes D1) |
| 3012 | 3154 | debt-obligations | C40: arc records coordinates; the boundary topic states what it never judges (closes D3) |
| 3120 | 3261 | debt-recovery | C22, modeled: audit or verdict alike needs its own eligible, bound assessment (closes D1) |
| 3287 | 3428 | debt-clearance | C22/C40: a person's read, not only an audit, answers the assessment requirement |
| 4113 | 4254 | candidates | C42, unrealized in the candidate model: verify's exit follows the budget judge (closes D2) |
| 4152 | 4294 | candidates | C31/C42, unrealized: promotion refuses what the budget judge refuses |
| 5262 | 5405 | files | Outside: the identity-health exception is diagnostic; C44 states it permits no reserved address |
| 5477 | 5621 | gates | Outside: `arc gates` reports `confine` |
| 5488 | 5632 | gates | Outside: budget history, initialization and measurement move to their topics |
| 5555 | 5671 | gates | C31, unrealized: which gates need a budget is stated in gate-costs |
| 5571 | 5687 | gates | C31, unrealized: a receipt the budget judge refuses needs explicit rerun |
| 5590 | 5707 | gates | C31, unrealized: the busy-host rule, its reference, retirement and format 12; run time includes process-group cleanup |
| 5616 | 5760 | gates | Outside: verify line presentation of an excuse |
| 5686 | 5831 | gates | C14/C43, modeled: confinement requires fresh identity; legacy evidence answers only unconfined, unscoped declarations |
| 5704 | 5848 | gate-confinement | C43: identity modeled; scope, resolution, roots, kernel enforcement and fallback unrealized |
| 5716 | 5960 | gate-costs | C31/C32, unrealized: CPU and instruction accounting, enforcement keys, removed-gate budgets and the two-step route; outside: the advisory landing budget, landing costs, `arc gates init`, `arc gates measure` |
| 5733 | 6078 | gate-costs | Outside: order of work and levers are guidance arc does not automate |
| 5791 | 6131 | gate-rounds | Outside: the method of a round confers no permission |
| 5884 | 6341 | gate-raises | C32, unrealized: raise evidence must be unexcused |
| 5986 | 6443 | base-passes | C33, unrealized: excused evidence establishes no baseline |
| 6227 | 6684 | schemas | Outside: catchup reports Git configuration health |
| 6247 | 6704 | schemas | Outside: workbench schema |
| 6275 | 6733 | schemas | Outside: workspace report and sandbox clone schemas |
| 6348 | 6806 | schemas | Outside: journal workbench and pin events |
| 6369 | 6832 | schemas | C31, unrealized: store format 12 |
| 6426 | 6890 | boundaries | C40: model ordering is scoped to the dated ladder (closes D3) |
| 6520 | 7016 | identity-options | C20: readiness must read the target revision and merge tree the decision observed; the model reads one observation set. Outside: Git launch counts and held Git answers |
| 6538 | 7044 | journal-resolution | Outside: journal binding outside Git |

## Changed command help

| surface | authorization classification |
| --- | --- |
| `arc snapshot --help` | C44, unrealized: reserved addresses in introduced commits refuse, whatever `--base` |
| `arc integrate --help` | C44, unrealized: recorded patchsets with reserved addresses refuse; C21: arc derives ineligible-review only under assessed clearance; a file under which the read would discharge is refused (closes D5) |
| `arc debt --help` | C21: the same derivation and refusal wording as integrate |
| `arc verify --help` | C31, unrealized: an over-budget raw pass exits 1 unless the busy-host rule accepts it |
| `arc candidate verify --help` | C42: exit 0 only when the budget judge accepts each pass (closes D2) |
| `arc changelog --help` | C43: renderers run confined; changelog confers no authority |
| `arc events --help`, `arc watch --help` | C43: operator handlers keep operator authority; no authorization |
| `arc doctor --help` | Outside: `preparation-unguarded` advice and Git identity, bare checkout and signing problems are diagnostics |
| `arc gates --help`, `arc workspace gates --help` | Outside: landing costs and paid preparation are reports |
| `arc gates init --help` | Outside: writes budgets for integration gates, publication-only on request |
| `arc gates measure --help` | Outside: prints tree CPU, instructions and other processes' share |
| `arc guide --help`, `arc catchup --help`, `arc workspace *`, `arc journal *`, `arc sandbox clone --help` | Outside: run-time guide topics, journals outside Git, workbenches, sandbox clone |
