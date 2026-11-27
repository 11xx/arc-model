"""Run through arc-model-sandbox; exercise the public claims settled or added at 954f2334.

Model claims (C6/C27, C31-C33, C43, C45) compare the model's answer with arc's.
Contract claims (C10, C37, C44) check settled clauses outside the pure model.
Observations record what arc did where the contract leaves a question open (F1-F6).
"""
import json
import os
from pathlib import Path
import subprocess
import sys

binary = str(Path(sys.argv[1]).resolve())
root = Path.cwd()
repo = root / "repo"
repo.mkdir()
operator_policy = repo / ".git/arc/operator-policy.toml"
rows = []
EMAIL = "tester@arc-model.internal"


def run(args, cwd=repo, expected=0, env=None):
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True,
                            env=None if env is None else {**os.environ, **env})
    if expected is not None and result.returncode != expected:
        raise SystemExit(json.dumps({"rows": rows, "command": args[1:], "expected": expected,
                                     "exit": result.returncode, "out": result.stdout,
                                     "err": result.stderr}, indent=2))
    return result


def git(*args, cwd=repo, email=EMAIL, committer=None):
    env = None if committer is None else {"GIT_COMMITTER_EMAIL": committer}
    return run(["git", "-c", "user.name=Tester", "-c", "user.email=" + email,
                "-c", "commit.gpgsign=false", *args], cwd=cwd, env=env).stdout.strip()


def arc(*args, cwd=repo, actor="author", expected=0, env=None):
    return run([binary, *args, "--actor", actor], cwd=cwd, expected=expected, env=env)


def claim(kind, name, model, observed, detail=""):
    rows.append({"kind": kind, "claim": name, "expected": model, "arc": observed,
                 "agreed": model == observed, "detail": detail.strip()[-400:]})


def observe(name, observed, detail=""):
    rows.append({"kind": "observation", "claim": name, "arc": observed, "detail": detail.strip()[-400:]})


def check_json(change, cwd):
    result = arc("check", change, "--json", cwd=cwd, expected=None)
    try:
        parsed = json.loads(result.stdout)
    except Exception:
        parsed = None
    return result.returncode, parsed, result.stdout + result.stderr


def owed(change, cwd):
    listed = json.loads(arc("query", "--debt", "--json", cwd=cwd).stdout)
    return any(change in json.dumps(item) for item in listed)


def assessment(path, independence, identities, qualifiers):
    path.write_text(json.dumps({
        "schema": "agent-routing-assessment/1", "independence": independence,
        "qualifiers": qualifiers, "route_version": "rv1", "debt_kind": "ineligible-review",
        "floor": 2, "authors": [],
        "reviewer": {"identities": identities, "effort": "high", "model": identities[0],
                     "family": "lab-b", "review_tier": 2},
    }))
    return str(path)


def begin(change, files, message="edit"):
    work = root / change
    arc("begin", change, "--worktree", str(work))
    for name, text in files.items():
        (work / name).parent.mkdir(parents=True, exist_ok=True)
        (work / name).write_text(text)
    git("add", ".", cwd=work)
    git("commit", "-qm", message, cwd=work)
    return work


# Base repository
git("init", "-q", "-b", "master")
(repo / ".arc").mkdir()
(repo / ".arc/policy.toml").write_text("[policy]\nforbid_self_approval = false\n")
(repo / ".arc/gates.toml").write_text("[gates.check]\ncommand = 'true'\n")
(repo / "README.md").write_text("fixture\n")
git("add", ".")
git("commit", "-qm", "fixture")

# --- 1. C31: Budget suspensions ---
# Configure a slow-ish passing gate that exceeds a 10ms budget, plus a failing control via env.
(repo / ".arc/gates.toml").write_text(
    "[budget]\ntotal = '5s'\n\n"
    "[gates.slow]\ncommand = 'sleep 0.04; test -z \"$FORCE_FAIL\"'\nbudget = '10ms'\n"
)
git("add", ".arc/gates.toml")
git("commit", "-qm", "budgeted gate")

work = begin("susp", {"susp.txt": "edit\n"})
arc("snapshot", "susp", "--solo", cwd=work)
arc("review", "susp", "--verdict", "approved", "--body", "read", actor="reviewer", cwd=work)

# Over-budget run fails verify (exit 1) and is not ready
v_over = arc("verify", "susp", "--all", "--rerun", cwd=work, expected=None)
code_before, parsed_before, detail_before = check_json("susp", work)
claim("model", "C31: over-budget pass is refused without suspension",
      False, parsed_before is not None and parsed_before["ready"], detail_before)

# Suspension > 24h is refused
too_long = arc("gates", "suspend", "--for", "25h", "--reason", "too long", cwd=work, expected=None)
claim("model", "C31: suspension exceeding 24h is refused", True, too_long.returncode != 0, too_long.stderr)

# Implementer role cannot record a suspension
impl_susp = arc("gates", "suspend", "--for", "1h", "--reason", "role test",
                cwd=work, expected=None, env={"ARC_ROLE": "implementer"})
claim("contract", "C31: non-lead role cannot record a budget suspension",
      True, impl_susp.returncode != 0, impl_susp.stderr)

# Gate-scoped suspension for another gate does not lift slow's refusal
arc("gates", "suspend", "--for", "1h", "--reason", "other gate only", "other", cwd=work)
_, parsed_other, detail_other = check_json("susp", work)
claim("model", "C31: suspension scoped to another gate does not lift refusal",
      False, parsed_other is not None and parsed_other["ready"], detail_other)
arc("gates", "resume", cwd=work)

# Wildcard suspension accepts the earlier over-budget receipt as of moment of judgment
arc("gates", "suspend", "--for", "1h", "--reason", "loaded host", cwd=work)
_, parsed_during, detail_during = check_json("susp", work)
claim("model", "C31: active local suspension accepts earlier over-budget pass for integration",
      True, parsed_during is not None and parsed_during["ready"], detail_during)

# Publication judges strictly despite active suspension
pub_during = arc("publication", "--target", "master", cwd=repo, expected=None)
claim("model", "C31: publication judges strictly despite active budget suspension",
      True, pub_during.returncode != 0, pub_during.stdout + pub_during.stderr)

# A failing gate still fails under active suspension
arc("verify", "susp", "--all", "--rerun", cwd=work, expected=None, env={"FORCE_FAIL": "1"})
_, parsed_fail, detail_fail = check_json("susp", work)
claim("model", "C31: failing gate still fails under active suspension",
      False, parsed_fail is not None and parsed_fail["ready"], detail_fail)

# Re-record over-budget pass under suspension, verify exits 0 (observe F1!), then resume ends it
v_under = arc("verify", "susp", "--all", "--rerun", cwd=work, expected=None)
observe("F1 observation: arc verify exit status on over-budget pass during active suspension",
        v_under.returncode, v_under.stdout + v_under.stderr)
_, parsed_under, detail_under = check_json("susp", work)
claim("model", "C31: over-budget pass recorded under suspension is accepted while active",
      True, parsed_under is not None and parsed_under["ready"], detail_under)

# Resume ends the suspension -> same receipt is refused again
arc("gates", "resume", cwd=work)
_, parsed_after, detail_after = check_json("susp", work)
claim("model", "C31: resuming suspension refuses the same earlier receipt again",
      False, parsed_after is not None and parsed_after["ready"], detail_after)

# --- 2. C31 (E1): [budget] enforcement keys ---
(repo / ".arc/gates.toml").write_text("[budget]\nlanding = '5s'\n\n[gates.check]\ncommand = 'true'\n")
git("add", ".arc/gates.toml")
git("commit", "-qm", "landing-only budget table")
work_e1 = begin("budget-e1", {"e1.txt": "e1\n"})
arc("snapshot", "budget-e1", "--solo", cwd=work_e1)
arc("review", "budget-e1", "--verdict", "approved", "--body", "read", actor="reviewer", cwd=work_e1)
arc("verify", "budget-e1", "--all", "--rerun", cwd=work_e1)
_, parsed_e1_ok, detail_e1_ok = check_json("budget-e1", work_e1)
claim("model", "C31/E1: landing-only [budget] table requires no individual gate budgets",
      True, parsed_e1_ok is not None and parsed_e1_ok["ready"], detail_e1_ok)

(repo / ".arc/gates.toml").write_text("[budget]\nlanding = '5s'\nraise = '10%'\n\n[gates.check]\ncommand = 'true'\n")
git("add", ".arc/gates.toml")
git("commit", "-qm", "enforcing budget table with non-default raise")
work_e1_enf = begin("budget-e1-enf", {"e1-enf.txt": "e1-enf\n"})
arc("snapshot", "budget-e1-enf", "--solo", cwd=work_e1_enf)
arc("review", "budget-e1-enf", "--verdict", "approved", "--body", "read", actor="reviewer", cwd=work_e1_enf)
arc("verify", "budget-e1-enf", "--all", "--rerun", cwd=work_e1_enf, expected=None)
_, parsed_e1_enf, detail_e1_enf = check_json("budget-e1-enf", work_e1_enf)
claim("model", "C31/E1: [budget] with non-default raise beside landing requires gate budgets",
      True, parsed_e1_enf is not None and not parsed_e1_enf["ready"] and bool(parsed_e1_enf.get("budget_errors")),
      json.dumps(parsed_e1_enf.get("budget_errors") if parsed_e1_enf else detail_e1_enf))

# Reset to simple gate without budget
(repo / ".arc/gates.toml").write_text("[gates.check]\ncommand = 'true'\n")
git("add", ".arc/gates.toml")
git("commit", "-qm", "reset plain gate")

# --- 3. C43 (E2): Open-change [confine] resolution ---
work_c = begin("confine-e2", {".arc/gates.toml": "[gates.check]\ncommand = 'true'\n\n[confine]\nwrites = ['target']\nrequired = false\n"})
arc("snapshot", "confine-e2", "--solo", cwd=work_c)
arc("review", "confine-e2", "--verdict", "approved", "--body", "read", actor="reviewer", cwd=work_c)
arc("verify", "confine-e2", "--all", "--rerun", cwd=work_c)
_, parsed_c1, detail_c1 = check_json("confine-e2", work_c)
claim("model", "C43/E2: change head adopts confinement when neither destination nor operator declares one",
      True, parsed_c1 is not None and parsed_c1["ready"], detail_c1)

# Now operator adds a table with writes=['target'], required=false; head widens writes=['target','extra'] and sets required=true
operator_policy.parent.mkdir(parents=True, exist_ok=True)
operator_policy.write_text("[confine]\nwrites = ['target']\nrequired = false\n")
(work_c / ".arc/gates.toml").write_text(
    "[gates.check]\ncommand = 'true'\n\n[confine]\nwrites = ['target', 'extra']\nrequired = true\n"
)
git("add", ".arc/gates.toml", cwd=work_c)
git("commit", "-qm", "head widens roots and sets required=true", cwd=work_c)
arc("snapshot", "confine-e2", "--solo", cwd=work_c)
arc("review", "confine-e2", "--verdict", "approved", "--body", "read2", actor="reviewer", cwd=work_c)
# Check is not refused for widening head roots; gate must rerun under required=true
v_widen = arc("verify", "confine-e2", "--all", "--rerun", cwd=work_c, expected=None)
_, parsed_c2, detail_c2 = check_json("confine-e2", work_c)
claim("model", "C43/E2: widening head roots are ignored (never refused) while head required=true applies",
      True, v_widen.returncode == 0 and parsed_c2 is not None and parsed_c2["ready"], v_widen.stderr + detail_c2)
operator_policy.unlink()

# --- 4. C6 / C27: Earlier-patchset waiver retirement ---
work_r = begin("retire-ok", {"r1.txt": "v1\n"})
arc("snapshot", "retire-ok", "--solo", cwd=work_r)
arc("review", "retire-ok", "--verdict", "approved", "--body", "self", "--model", "impl#high", actor="author", cwd=work_r)
arc("debt", "retire-ok", "--kind", "ineligible-review", "--qualifier", "same-model",
    "--reason", "ps-01 was self-reviewed", cwd=work_r)
(work_r / "r2.txt").write_text("v2\n")
git("add", "r2.txt", cwd=work_r)
git("commit", "-qm", "ps-02", cwd=work_r)
arc("snapshot", "retire-ok", "--solo", cwd=work_r)
arc("review", "retire-ok", "--verdict", "approved", "--body", "indep", "--model", "other#high", actor="reviewer", cwd=work_r)
arc("verify", "retire-ok", "--all", "--rerun", cwd=work_r)
arc("integrate", "retire-ok", cwd=work_r)
show_ret = json.loads(arc("show", "retire-ok", "--json", cwd=repo).stdout)
claim("model", "C6/C27: independent approval of shipped ps-02 retires ps-01 ineligible-review waiver",
      False, owed("retire-ok", repo), json.dumps(show_ret.get("debt")))
observe("F3 observation: debt field on show --json after earlier-patchset waiver retirement",
        show_ret.get("debt"))

# Contrast: ps-02 approval carries an ineligible assessment -> cannot retire ps-01 waiver
work_rd = begin("retire-denied", {"rd1.txt": "v1\n"})
arc("snapshot", "retire-denied", "--solo", cwd=work_rd)
arc("review", "retire-denied", "--verdict", "approved", "--body", "self", "--model", "impl#high", actor="author", cwd=work_rd)
arc("debt", "retire-denied", "--kind", "ineligible-review", "--qualifier", "same-model",
    "--reason", "ps-01 was self-reviewed", cwd=work_rd)
(work_rd / "rd2.txt").write_text("v2\n")
git("add", "rd2.txt", cwd=work_rd)
git("commit", "-qm", "ps-02", cwd=work_rd)
arc("snapshot", "retire-denied", "--solo", cwd=work_rd)
inel_file = assessment(root / "denied-retire.json", "ineligible", ["other"], ["same-family"])
arc("review", "retire-denied", "--verdict", "approved", "--body", "indep-inel",
    "--model", "other#high", "--assessment", inel_file, actor="reviewer", cwd=work_rd)
arc("verify", "retire-denied", "--all", "--rerun", cwd=work_rd)
arc("integrate", "retire-denied", cwd=work_rd)
show_rd = json.loads(arc("show", "retire-denied", "--json", cwd=repo).stdout)
claim("model", "C6/C27: approval with ineligible assessment cannot retire earlier-patchset waiver",
      True, owed("retire-denied", repo), json.dumps(show_rd.get("debt")))

# --- 5. C45: Gate trailers (Witness:, Change-size:) validation & reuse identity ---
work_t = begin("trailers", {"t.txt": "v1\n"}, message="feat: work\n\nWitness: alpha\nChange-size: interface")
arc("snapshot", "trailers", "--solo", cwd=work_t)
arc("review", "trailers", "--verdict", "approved", "--body", "read", actor="reviewer", cwd=work_t)
arc("verify", "trailers", "--all", "--rerun", cwd=work_t)
_, parsed_t1, detail_t1 = check_json("trailers", work_t)
claim("model", "C45: valid Witness and Change-size: interface trailers pass verify and check",
      True, parsed_t1 is not None and parsed_t1["ready"], detail_t1)

# Change Witness trailer at identical tree -> invalidates prior pass!
git("commit", "--amend", "-qm", "feat: work\n\nWitness: beta\nChange-size: interface", cwd=work_t)
arc("snapshot", "trailers", "--solo", cwd=work_t)
arc("review", "trailers", "--verdict", "approved", "--body", "read2", actor="reviewer", cwd=work_t)
_, parsed_t2, detail_t2 = check_json("trailers", work_t)
claim("model", "C45: changing Witness trailer at unchanged tree invalidates prior pass",
      False, parsed_t2 is not None and parsed_t2["ready"], detail_t2)

# Invalid gate trailer (>3 distinct witnesses) refuses verify and check
git("commit", "--amend", "-qm", "feat: work\n\nWitness: w1\nWitness: w2\nWitness: w3\nWitness: w4", cwd=work_t)
arc("snapshot", "trailers", "--solo", cwd=work_t)
arc("review", "trailers", "--verdict", "approved", "--body", "read3", actor="reviewer", cwd=work_t)
v_inv = arc("verify", "trailers", "--all", "--rerun", cwd=work_t, expected=None)
code_inv, parsed_inv, detail_inv = check_json("trailers", work_t)
claim("model", "C45: more than three distinct Witness trailers refuses verify and check",
      True, v_inv.returncode != 0 and code_inv != 0, v_inv.stderr + detail_inv)
observe("F2 observation: arc check --json exit and output for invalid gate trailers",
        {"exit": code_inv, "parsed": parsed_inv}, detail_inv)

# --- 6. C37: --parallel isolated worktrees produce green gating evidence ---
work_p = begin("parallel-ok", {"p.txt": "p\n"})
arc("snapshot", "parallel-ok", "--solo", cwd=work_p)
arc("review", "parallel-ok", "--verdict", "approved", "--body", "read", actor="reviewer", cwd=work_p)
v_par = arc("verify", "parallel-ok", "--all", "--parallel", cwd=work_p, expected=None)
_, parsed_p, detail_p = check_json("parallel-ok", work_p)
claim("contract", "C37: --parallel on clean worktree produces green gating evidence",
      True, v_par.returncode == 0 and parsed_p is not None and parsed_p["ready"],
      f"verify_rc={v_par.returncode} stderr={v_par.stderr} stdout={v_par.stdout} check={detail_p}")

# --- 7. C10: Finding resolved --commit survival rule ---
work_f = begin("finding-survive", {"f.txt": "v1\n"})
arc("snapshot", "finding-survive", "--solo", cwd=work_f)
res_find = subprocess.run(
    [binary, "review", "finding-survive", "--verdict", "changes-requested", "--cause", "executor",
     "--actor", "reviewer", "--findings-json", "-"],
    input='[{"summary":"bug","body":"fix it","severity":"major","blocking":true}]',
    text=True, capture_output=True, cwd=work_f
)
if res_find.returncode != 0:
    raise SystemExit("failed to record finding: " + res_find.stderr)
fid = json.loads(arc("findings", "finding-survive", "--format", "json", cwd=work_f).stdout)["findings"][0]["id"]
(work_f / "f.txt").write_text("fixed\n")
git("add", "f.txt", cwd=work_f)
git("commit", "-qm", "fix bug", cwd=work_f)
fix_sha = git("rev-parse", "HEAD", cwd=work_f)
arc("snapshot", "finding-survive", "--solo", cwd=work_f)
arc("resolve", "finding-survive", fid, "--status", "resolved", "--commit", fix_sha,
    "--evidence", "fixed in commit", actor="reviewer", cwd=work_f)
arc("review", "finding-survive", "--verdict", "approved", "--body", "ok", actor="reviewer", cwd=work_f)
arc("verify", "finding-survive", "--all", "--rerun", cwd=work_f)
_, parsed_f1, detail_f1 = check_json("finding-survive", work_f)
claim("contract", "C10: resolved --commit stands while fix survives at head",
      True, parsed_f1 is not None and parsed_f1["ready"], detail_f1)

# Revert the fix -> finding reopens!
git("revert", "--no-edit", fix_sha, cwd=work_f)
arc("snapshot", "finding-survive", "--solo", cwd=work_f)
arc("review", "finding-survive", "--verdict", "approved", "--body", "re-read", actor="reviewer", cwd=work_f)
arc("verify", "finding-survive", "--all", "--rerun", cwd=work_f)
_, parsed_f2, detail_f2 = check_json("finding-survive", work_f)
claim("contract", "C10: reverting commit cited by resolved --commit reopens blocking finding",
      False, parsed_f2 is not None and parsed_f2["ready"], detail_f2)

# --- 8. C44: Reserved identity snapshot refusal ---
work_id = begin("reserved-id", {"id.txt": "ok\n"})
(work_id / "bad.txt").write_text("bad\n")
git("add", "bad.txt", cwd=work_id)
git("commit", "-qm", "bad identity", cwd=work_id, email="tester@example.invalid")
snap_bad = arc("snapshot", "reserved-id", "--solo", cwd=work_id, expected=None)
claim("contract", "C44: snapshot refuses reserved commit address",
      True, snap_bad.returncode != 0 and "reserved" in snap_bad.stderr, snap_bad.stderr)

print(json.dumps(rows, indent=2))
sys.exit(0 if all(row.get("agreed", True) for row in rows) else 1)
