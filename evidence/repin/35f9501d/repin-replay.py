"""Run through arc-model-sandbox; exercise the public claims this re-pin settles.

Model claims (C22, C27, C43) compare the model's answer with arc's. Contract
claims (C44) check a settled clause the model does not represent. Every
claim is recorded with arc's answer; the exit status is 1 when any disagrees.
Observations answer no claim: they record what arc did where the contract
leaves a question open.
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
home = Path(os.environ["HOME"])
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


def arc(*args, cwd=repo, actor="author", expected=0):
    return run([binary, *args, "--actor", actor], cwd=cwd, expected=expected)


def claim(kind, name, model, observed, detail=""):
    rows.append({"kind": kind, "claim": name, "expected": model, "arc": observed,
                 "agreed": model == observed, "detail": detail.strip()[-400:]})


def observe(name, observed, detail=""):
    rows.append({"kind": "observation", "claim": name, "arc": observed, "detail": detail.strip()[-400:]})


def ready(change, cwd):
    result = arc("check", change, "--json", cwd=cwd, expected=None)
    return json.loads(result.stdout)["ready"], result.stdout


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


def begin(change, files):
    work = root / change
    arc("begin", change, "--worktree", str(work))
    for name, text in files.items():
        (work / name).parent.mkdir(parents=True, exist_ok=True)
        (work / name).write_text(text)
    git("add", ".", cwd=work)
    return work


git("init", "-q", "-b", "master")
(repo / ".arc").mkdir()
(repo / ".arc/policy.toml").write_text("[policy]\nforbid_self_approval = false\n")
(repo / ".arc/gates.toml").write_text("[gates.check]\ncommand = 'true'\n")
(repo / "README.md").write_text("fixture\n")
git("add", ".")
git("commit", "-qm", "fixture")
rerun = ["--rerun"] if "--rerun" in arc("verify", "--help").stdout else []

# C43: an operator [confine] moves the declaration without moving any tree.
work = begin("confined", {"work.txt": "edit\n"})
git("commit", "-qm", "edit", cwd=work)
arc("snapshot", "confined", "--solo", cwd=work)
arc("review", "confined", "--verdict", "approved", "--body", "read", actor="reviewer", cwd=work)
arc("verify", "confined", "--all", *rerun, cwd=work)
answer, _ = ready("confined", work)
claim("model", "C43: an unconfined pass answers an unconfined declaration", True, answer)
operator_policy.parent.mkdir(parents=True, exist_ok=True)
operator_policy.write_text('[confine]\nwrites = ["target"]\nrequired = false\n')
answer, shown = ready("confined", work)
claim("model", "C43: an unconfined pass does not answer a confined declaration", False, answer, shown)
verified = arc("verify", "confined", "--all", *rerun, cwd=work, expected=None)
answer, shown = ready("confined", work)
claim("model", "C43: a pass under the same confinement answers it", True, answer, verified.stderr + shown)
operator_policy.write_text('[confine]\nwrites = ["target"]\nrequired = true\n')
answer, shown = ready("confined", work)
claim("model", "C43: a changed required flag leaves the earlier pass unanswering", False, answer, shown)
operator_policy.unlink()
answer, shown = ready("confined", work)
claim("model", "C43: the earlier unconfined pass answers the restored unconfined declaration", True, answer, shown)

# C22, C27: a verdict on the shipped patchset clears ineligible-review under
# its own eligible, bound assessment, and only then.
for change, identities, expect_owed in [("assessed", ["second-model"], False),
                                        ("unbound", ["somebody-else"], True)]:
    work = begin(change, {change + ".txt": "edit\n"})
    git("commit", "-qm", "edit", cwd=work)
    arc("snapshot", change, "--solo", cwd=work)
    arc("review", change, "--verdict", "approved", "--body", "first read",
        "--model", "reader-model#high", actor="reader", cwd=work)
    # the declaration names the latest verdict on the patchset: the first read
    arc("debt", change, "--kind", "ineligible-review", "--qualifier", "same-model",
        "--reason", "the first read is not independent", cwd=work)
    eligible = assessment(root / (change + "-eligible.json"), "eligible", identities, [])
    arc("review", change, "--verdict", "approved", "--body", "assessed read",
        "--model", "second-model#high", "--assessment", eligible, actor="second", cwd=work)
    arc("verify", change, "--all", *rerun, cwd=work)
    arc("integrate", change, cwd=work)
    detail = arc("query", "--debt", "--json", cwd=work).stdout
    name = ("C22: an eligible, bound assessed verdict on the shipped patchset clears ineligible-review"
            if not expect_owed else
            "C22: a verdict whose assessment does not describe its reader leaves ineligible-review owed")
    claim("model", name, expect_owed, owed(change, work), detail)

closed = arc("review", "assessed", "--verdict", "approved", "--body", "after closure",
             actor="third", cwd=repo, expected=None)
observe("C22 open question: arc review on a closed change", closed.returncode, closed.stdout + closed.stderr)

# C22: an ineligible assessment on a verdict leaves ordinary debt owed.
for change, ineligible, expect_owed in [("ordinary-ineligible", True, True),
                                        ("ordinary-plain", False, False)]:
    work = begin(change, {change + ".txt": "edit\n"})
    git("commit", "-qm", "edit", cwd=work)
    arc("snapshot", change, "--solo", cwd=work)
    arc("debt", change, "--reason", "independent review remains owed", cwd=work)
    extra = []
    if ineligible:
        extra = ["--assessment", assessment(root / (change + ".json"), "ineligible",
                                            ["third-model"], ["same-family"])]
    arc("review", change, "--verdict", "approved", "--body", "read", "--model", "third-model#high",
        *extra, actor="third", cwd=work)
    arc("verify", change, "--all", *rerun, cwd=work)
    arc("integrate", change, cwd=work)
    detail = arc("query", "--debt", "--json", cwd=work).stdout
    name = ("C22: a verdict carrying an ineligible assessment leaves ordinary debt owed"
            if ineligible else "C22: the same verdict unassessed discharges ordinary debt")
    claim("model", name, expect_owed, owed(change, work), detail)

# C44: reserved commit identities refuse snapshot; the model represents none.
work = begin("identities", {"plain.txt": "plain\n"})
git("commit", "-qm", "real identity", cwd=work)
base = git("rev-parse", "HEAD", cwd=work)
cases = [
    ("C44: a reserved author address refuses the snapshot", "reserved.txt", "tester@example.invalid", None),
    ("C44: a reserved committer address refuses the snapshot", "committer.txt", EMAIL, "tester@example.com"),
    ("C44: a subdomain of a reserved name refuses the snapshot", "subdomain.txt", "tester@mail.example.org", None),
]
for name, path, email, committer in cases:
    (work / path).write_text(path + "\n")
    git("add", ".", cwd=work)
    git("commit", "-qm", path, cwd=work, email=email, committer=committer)
    refused = arc("snapshot", "identities", "--solo", cwd=work, expected=None)
    claim("contract", name, True, refused.returncode != 0 and "reserved" in refused.stderr, refused.stderr)
    git("reset", "-q", "--hard", base, cwd=work)
(work / "reserved.txt").write_text("reserved\n")
git("add", ".", cwd=work)
git("commit", "-qm", "reserved", cwd=work, email="tester@example.test")
head = git("rev-parse", "HEAD", cwd=work)
refused = arc("snapshot", "identities", "--solo", "--base", head, cwd=work, expected=None)
claim("contract", "C44: a base override cannot hide an introduced reserved commit", True,
      refused.returncode != 0 and "reserved" in refused.stderr, refused.stderr)
git("reset", "-q", "--hard", base, cwd=work)
(work / ".arc").mkdir(exist_ok=True)
(work / ".arc/policy.toml").write_text(
    "[policy]\nforbid_self_approval = false\n[git]\nallow_local_identity = true\n")
git("add", ".", cwd=work)
git("commit", "-qm", "exception", cwd=work, email="tester@test.localhost")
refused = arc("snapshot", "identities", "--solo", cwd=work, expected=None)
claim("contract", "C44: the identity-health exception does not permit a reserved address", True,
      refused.returncode != 0 and "reserved" in refused.stderr, refused.stderr)
git("reset", "-q", "--hard", base, cwd=work)
accepted = arc("snapshot", "identities", "--solo", cwd=work, expected=None)
claim("contract", "C44: an address outside the reserved set records a patchset", True,
      accepted.returncode == 0, accepted.stderr)

print(json.dumps(rows, indent=2))
sys.exit(0 if all(row.get("agreed", True) for row in rows) else 1)
