"""Run through arc-model-sandbox; exercise the modeled public changes."""
import json
import os
from pathlib import Path
import subprocess
import sys

binary = str(Path(sys.argv[1]).resolve())
root = Path.cwd()
repo = root / "repo"
repo.mkdir()
work = root / "work"
home = Path(os.environ["HOME"])
rows = []


def run(args, cwd=repo, expected=0):
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True)
    if expected is not None and result.returncode != expected:
        raise SystemExit(json.dumps({"command": args[1:], "expected": expected,
                                     "exit": result.returncode, "out": result.stdout,
                                     "err": result.stderr}))
    return result


def git(*args, cwd=repo):
    return run(["git", "-c", "user.name=Tester", "-c", "user.email=tester@example.invalid",
                "-c", "commit.gpgsign=false", *args], cwd=cwd)


def arc(*args, cwd=work, actor="author", expected=0):
    return run([binary, *args, "--actor", actor], cwd=cwd, expected=expected)


def check(claim, condition):
    rows.append({"claim": claim, "agreed": bool(condition)})
    if not condition:
        raise SystemExit(json.dumps(rows, indent=2))


def owed():
    return bool(json.loads(arc("query", "--debt", "--json").stdout))


git("init", "-q", "-b", "master")
(repo / ".arc").mkdir()
(repo / ".arc/policy.toml").write_text("[policy]\nforbid_self_approval = false\n")
(repo / ".arc/gates.toml").write_text(
    '[gates.check]\ncommand = \'exit "$(cat "$HOME/gate-code")"\'\n')
(repo / "README.md").write_text("fixture\n")
git("add", ".")
git("commit", "-qm", "fixture")
(home / "gate-code").write_text("0\n")
arc("begin", "work", "--worktree", str(work), cwd=repo)
(work / "work.txt").write_text("edit\n")
git("add", ".", cwd=work)
git("commit", "-qm", "edit", cwd=work)
arc("snapshot", "work", "--solo")
arc("debt", "work", "--reason", "independent review remains owed")
arc("verify", "work", "--all", "--rerun")
check("ordinary execution supplies the gate beside review debt",
      json.loads(arc("check", "work", "--json").stdout)["ready"])

(home / "gate-code").write_text("75\n")
unrun = arc("verify", "work", "--all", "--rerun", expected=1)
state = arc("show", "work", "--json").stdout
check("exit 75 is retained as not-admitted", "not-admitted" in state)
check("newest not-admitted blocks fallback to the older pass",
      not json.loads(arc("check", "work", "--json", expected=5).stdout)["ready"])
retired = arc("verify", "work", "--gate", "check", "--bypass", "historical escape", expected=None)
check("the retired bypass command refuses", retired.returncode != 0)
check("review debt and retired bypass do not waive an unrun gate",
      not json.loads(arc("check", "work", "--json", expected=5).stdout)["ready"])

(home / "gate-code").write_text("0\n")
arc("verify", "work", "--all", "--rerun")
arc("integrate", "work")
arc("audit", "work", "--verdict", "comment-only", "--body", "comment", actor="reader")
check("comment-only audit leaves ordinary debt owed", owed())
assessment = root / "assessment.json"
assessment.write_text(json.dumps({
    "schema": "agent-routing-assessment/1", "independence": "ineligible",
    "qualifiers": ["same-family"], "route_version": "rv1",
    "debt_kind": "ineligible-review", "floor": 2,
    "reviewer": {"identities": ["reader-model"], "effort": "high",
                 "model": "reader-model", "family": "lab-a", "review_tier": 2},
    "authors": [],
}))
arc("audit", "work", "--verdict", "approved", "--body", "findings only",
    "--assessment", str(assessment), "--model", "reader-model#high", actor="reader")
check("ineligible assessment leaves ordinary debt owed", owed())
arc("audit", "work", "--verdict", "changes-requested", "--body", "negative review",
    actor="reader")
check("independent changes-requested audit discharges the owed read", not owed())
print(json.dumps(rows, indent=2))
