# Authorization text audit

The complete guide diff from 35f9501d to the pinned 954f2334 text retains every
changed sentence (66 hunks across 34 topic files); this table classifies every
hunk by its new guide line. Clause numbers refer to CONTRACT.md. "Modeled" means
the model represents the rule; "unrealized" means the contract states it and the
model does not represent it; "outside" means it confers or removes no
integration, landing, promotion, publication or acceptance permission. An
outside classification grants no modeled permission.

| old guide line | new guide line | route | authorization classification |
| --- | --- | --- | --- |
| 18 | 18 | identity-basics | C18/C40, unrealized: `antigravity` added to supported `ARC_HARNESS` values |
| 27 | 27 | identity-basics | C18, already modeled: `arc env` leaves `ARC_ACTOR` unset so an inferred session cannot silently satisfy declared-actor or independent-review policies |
| 125 | 128 | identity-events | Outside: read-only command inventory (`progress`, `milestone`, `workspace progress/milestones`) |
| 150 | 154 | identity-sessions | C18/C40, unrealized: Antigravity session detection (`ANTIGRAVITY_CONVERSATION_ID`, `T3CODE_HOME`, trailing effort split) |
| 234 | 242 | workspace | Outside: `workspace progress`, `workspace milestones`, and `workspace report` flags |
| 251 | 269 | workspace | Outside: library rows belong to `journal_dir` |
| 272 | 292 | workspace | Outside: `workspace report --progress` and `--milestones` |
| 284 | 308 | workspace | Outside: `workspace watch --progress` and `--milestones` |
| 418 | 446 | journal-lookup | Outside: `arc journal reopen` reverses journal consumptions; no ledger authorization |
| 550 | 603 | journal-lookup | Outside: `arc stats --by-model` (`arc-stats-by-model/2`) reporting |
| 757 | 821 | questions | Outside: discussion scaffold heading placement |
| 995 | 1061 | change-commands | C10, unrealized: a `resolved` disposition citing `--commit` stands only when that commit (after recorded rewrites) is an ancestor of head or matches a non-merge commit in `base..head` by exact Git patch-id and survives without being reverted |
| 1059 | 1133 | change-bundles | C39, unrealized: export omits unrelated `history-rewritten` events; import and `arc accept` skip unrelated contradicting rewrites with a warning and refuse relevant or intra-bundle contradictions |
| 1173 | 1254 | change-gates | C31, unrealized: busy-host waited-CPU prose cross-references `arc guide gate-costs` (closes E6) |
| 1302 | 1380 | change-integration | C44, unrealized: integration, provisional preparation and multi-change landings check the shipped (newest) patchset over `base..head` and target `..head` (not earlier patchsets), exiting 1; readiness lists `reserved-identity` and `check` exits 21 (closes E3) |
| 1384 | 1466 | change-integration | C10/C39, unrealized: default auto-stamping of missing projected role trailers (`[trailers] auto = true`, `--no-trailers`); fast-forward refuses commits reachable from another branch, tag or stacked open change (enforced in `--dry-run`) |
| 1500 | 1596 | change-integration | C20, settled (race unrealized): both readings of readiness must match the decision's target revision and merge tree (unless contribution mode hands off), else exit 1 writing nothing (closes E5) |
| 1523 | 1626 | change-landing | C41, unrealized: `arc land` auto-stamps per-layer missing projected role trailers bottom-to-top unless `--no-trailers` or `[trailers] auto = false` |
| 1667 | 1774 | change-landing | C41, unrealized: asserted integration adds `--derive-correspondence`, `mode: "squash"`, and parent/result tree matching |
| 2132 | 2242 | journal-records | Outside: `arc feedback <project>` tool-friction journal filings |
| 2160 | 2286 | journal-references | Outside: `arc journal append` optional `--body-file` and `--attach` |
| 2169 | 2295 | journal-references | Outside: journal raster attachments and `journal render` privacy/attachment handling |
| 2325 | 2469 | ending | Outside: `arc journal --global` includes `reopen` |
| 2385 | 2529 | ending | Outside: `arc checkpoint record --milestone` and `--series` |
| 2393 | 2538 | ending | Outside: checkpoints snapshot outstanding review debts and bound series/milestones |
| 2424 | 2572 | ending | Outside: `checkpoint show` reports series/milestone and debt progress since checkpoint |
| 2576 | 2728 | forge-observations | Outside: `forge observe --example` and offline `forge ingest` ("Admission never changes readiness") |
| 3093 | 3253 | debt-obligations | C22, settled: `arc review` records only on an open change and `arc audit` only on an integrated one, so an `integrate --debt` clears only with an audit (closes E4) |
| 3243 | 3407 | debt-recovery | C6/C22/C27, modeled: a guarded integration authorized by an independent approval of the shipped patchset (without an assessment denying clearance) retires earlier-patchset waivers so they create no shipped obligation; a waiver used to authorize stays owed |
| 3705 | 3877 | contributions | Outside: single-participant `Planned-by`/`Orchestrated-by` convention |
| 3725 | 3900 | contributions | Outside: `arc trailers` projects `Reviewed-by` from qualifying pre-integration Approved verdicts |
| 3739 | 3916 | contributions | Outside: rules for projecting `Reviewed-by` (never audits, non-approvals, findings-only, rejected self-approvals or waivers) |
| 3750 | 3938 | contributions | C10/C39, unrealized: trailer advice updates for auto-stamping and `--sync`; C45, modeled (validation and identity) / unrealized (commit reading): `arc-gate-trailers/1` (`Witness:`, `Change-size: interface`) refuses invalid declarations on `verify`, `check`, `integrate` and `land`, binds reuse identity, and passes `ARC_WITNESSES`, `ARC_CHANGE_SIZE`, `ARC_INVARIANTS` |
| 3834 | 4059 | rewrites-operations | Outside: `arc rewrite trailers --sync` |
| 3954 | 4185 | rewrites-evidence | C10/C39, unrealized: commits cited by finding dispositions by full OID are retained across rewrites |
| 4029 | 4261 | rewrites-evidence | C14/C32/C39, unrealized: commit-bound gate passes and matching budget raises now follow `signature_only` and `role_additions` rewrites alongside approvals and waivers; conflict diagnostics name both events |
| 4045 | 4280 | rewrites-evidence | Outside: `arc rewrite trailers --sync` named beside `--append` |
| 4487 | 4722 | rules-evidence | C14/C39, unrealized: `binds = "commit"` passes (including synthesized `--against` merges) follow `signature_only` and `role_additions` rewrites when destination is unchanged |
| 5264 | 5500 | rules-rounds | C31, unrealized: recording a budget suspension (`arc gates suspend`) is lead-only |
| 5292 | 5528 | exit-codes | C44, unrealized: `arc check` exits 21 for `reserved-identity` (closes E3) |
| 5424 | 5662 | files | C10/C39, unrealized: `[trailers] auto = true | false` default true (`false` wins across layers) |
| 5654 | 5894 | gates | C31/C45, unrealized (budget) / modeled (`invariants` identity): `interface_budget` and `invariants` keys in `[gates.<name>]` |
| 5667 | 5909 | gates | C12/C31/C45: unknown `.arc/gates.toml` keys refuse; `interface_budget >= budget`; `invariants` reads target's list and binds reuse |
| 5693 | 5937 | gates | C31, modeled: an overrun passes under the busy-host rule or an active budget suspension; `--parallel` runs subject to budget refusal |
| 5715 | 5958 | gates | C31, unrealized: busy-host rule body moved to `gate-costs`; store format 12 retained (closes E6) |
| 5764 | 5976 | gates | C31/C32/C33, modeled: `arc gates suspend` / `resume` — bounded <= 24h, store-local only, accepts over-budget integration passes while active, never lifts failures / missing budgets / excessive sums / operator ceiling / publication, never seeds references / raises / base passes; store format 13 |
| 5855 | 6092 | gate-confinement | C43, modeled (resolution and identity) / unrealized (enforcement): open-change `[confine]` resolution settled — destination + operator; head governs only when neither declares a table, else head roots are ignored (never refused) and `required = true` on any side enforces; closed change uses destination's current table (closes E2) |
| 5883 | 6126 | gate-confinement | Outside: `CACHEDIR.TAG` staging on absent Cargo `target` directory ("never authorizes artifact cleanup on its own") |
| 5971 | 6221 | gate-costs | C31/C32/C33, unrealized (counters) / modeled (suspension non-seeding): canonical busy-host rule Version 2 (with waited-CPU 5% coverage condition; Version 1 without it) and suspended runs excluded from references, raise evidence and base-pass seeds (closes E6) |
| 5987 | 6279 | gate-costs | Outside: `arc workspace gates` reports arc's own time and landing time |
| 6005 | 6298 | gate-costs | Outside: paid total overflow handling and landing-time accounting ("reported, never budgeted") |
| 6021 | 6333 | gate-costs | C31, modeled: `[budget]` table enforcement keys settled — enforces when it lacks `landing`, or sets `total`, `raise`, `raise_per` or `exclude` to non-default beside `landing` (closes E1) |
| 6206 | 6523 | gate-rounds | Outside: landing time note ("the bound judges gate time alone") |
| 6288 | 6606 | gates-together | C16/C37, unrealized: `--parallel` runs each gate in an isolated temporary detached worktree at HEAD (requiring a clean worktree), observing cleanliness per gate so clean passes gate integration without batch measurement |
| 6341 | 6662 | gate-raises | C32, modeled: raise evidence must be recorded under no budget suspension (as well as unexcused) |
| 6396 | 6718 | gate-raises | C32/C39, unrealized: raise head matching now follows `signature_only` and `role_additions` rewrites when tree, diff and destination are unchanged |
| 6661 | 6986 | progress, milestones | Outside: pull-only `arc progress` and `arc milestone` work tracking (never pushed into `status`, `check`, `catchup` or hooks) |
| 6703 | 7279 | schemas | Outside: `arc-feedback/1`, `arc-feedback-list/1` |
| 6719 | 7297 | schemas | Outside: `arc-stats-by-model/2` |
| 6733 | 7311 | schemas | Outside: workspace report progress/milestones fields and progress/milestone schemas |
| 6766 | 7348 | schemas | Outside: optional `invocation_id`, `invocation_elapsed_ms`, `invocation_gated_ms` timing stamps |
| 6782 | 7373 | schemas | Outside: `arc forge ingest` schema listing |
| 6796 | 7387 | schemas | C45: `arc-gate-trailers/1` schema listing |
| 6806 | 7398 | schemas | Outside: additive `journal-events/2` and attachment bundle fields |
| 6833 | 7432 | schemas | C31, unrealized: store format 13 for budget suspensions and runs recorded under them |
| 7018 | 7618 | identity-options | C20: `cat-file --batch-command` caching outside authorization; target-check rule moved to `change-integration` (closes E5) |

## Changed and added command help

| surface | authorization classification |
| --- | --- |
| `arc gates suspend --help`, `arc gates resume --help` | C31/C32/C33, modeled: bounded <= 24h store-local budget suspension and early termination; strict publication; failures and declaration errors still block |
| `arc check --help` | C44, unrealized: exit 21 `reserved-identity` added to exit-status precedence table (closes E3) |
| `arc integrate --help` | C44 (shipped patchset `reserved-identity`), C20 (readiness target/merge-tree agreement, exit 1; closes E5), C10/C39 (`--no-trailers` and default auto-stamping with shared-history refusal) |
| `arc land --help` | C41, unrealized: `--no-trailers` and default bottom-to-top per-layer auto-stamping |
| `arc verify --help` | C45 (`Witness:` / `Change-size:` / `invariants` reuse binding and env vars), C37 (`--parallel` isolated detached worktrees produce green gating evidence; refuses `--waive-dirty`). Note F1: still omits budget suspensions in the over-budget exit sentence |
| `arc close --help` | C41, unrealized: `--derive-correspondence`, `mode: "squash"`, and parent/result tree matching in `arc-correspondence/1` |
| `arc snapshot --help`, `arc done --help`, `arc rebase --help`, `arc review --help`, `arc squash --help` | C1/C4/C38, unrealized: when `--contributors` omits the invoking actor and `--on-behalf-of` is omitted, snapshot represents the first declared contributor as `on_behalf_of` |
| `arc receipt --help`, `arc env --help` | C18/C40, unrealized: Antigravity harness support (`ANTIGRAVITY_CONVERSATION_ID`, UUIDv4 native session IDs, `T3CODE_HOME`) |
| `arc trailers --help`, `arc rewrite trailers --help`, `arc instructions git --help` | Outside / C39: `Reviewed-by` projection, `--sync`, advisory single-participant checks |
| `arc gates --help`, `arc show --help`, `arc stats --help`, `arc workspace *` | Outside: reporting of budget suspensions, landing time, by-model stats, progress and milestones |
| `arc begin --help`, `arc brief --help`, `arc checkpoint record --help`, `arc forge *`, `arc feedback --help`, `arc journal *`, `arc progress *`, `arc milestone *`, `arc watch --help`, `arc --help` | Outside: progress/milestone tracking, feedback filings, journal reopen/attachments, offline forge ingest, v1 forge origin causes |
