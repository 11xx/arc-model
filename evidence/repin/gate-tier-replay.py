"""Run through arc-model-sandbox; compare C12/C14/C30's public claims."""
import json
import pathlib
import subprocess
import sys

binary = str(pathlib.Path(sys.argv[1]).resolve())
root = pathlib.Path.cwd()
repo = root / "repo"
repo.mkdir()
rows = []


def run(args, expected=0, cwd=repo):
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True)
    if expected is not None and result.returncode != expected:
        raise SystemExit(json.dumps({"command": args, "expected": expected,
                                     "exit": result.returncode, "stdout": result.stdout,
                                     "stderr": result.stderr}))
    return result


def git(*args, cwd=repo):
    return run(["git", "-c", "user.name=Tester", "-c", "user.email=tester@arc-model.internal",
                "-c", "commit.gpgsign=false", *args], cwd=cwd).stdout.strip()


def arc(*args, expected=0, cwd=repo):
    return run([binary, *args, "--actor", "tester"], expected=expected, cwd=cwd)


def check(name, condition):
    rows.append({"claim": name, "agreed": bool(condition)})
    if not condition:
        raise SystemExit(json.dumps(rows, indent=2))


git("init", "-q", "-b", "master")
(repo / ".arc").mkdir()
(repo / ".arc/policy.toml").write_text("[policy]\nforbid_self_approval = false\n")
(repo / ".arc/gates.toml").write_text('''[gates.integrate]
command = 'test ! -e "$HOME/fail"'
events = ["integration"]
[gates.publish]
command = 'test ! -e "$HOME/fail"'
events = ["publication"]
[gates.both]
command = 'test ! -e "$HOME/fail"'
''')
(repo / "README.md").write_text("fixture\n")
git("add", ".")
git("commit", "-qm", "fixture")
initial_revision = git("rev-parse", "HEAD")

# A publication guard can run before any change or verdict exists.
standalone = arc("publication", "--target", "master", "--profile", "local", "--revision", initial_revision)
check("publication standalone without a change", standalone.returncode == 0)
git("commit", "--allow-empty", "-qm", "same tree at a new revision")
moved = arc("publication", "--target", "master", "--revision", initial_revision, expected=None)
check("publication queued revision refuses a moved same-tree branch", moved.returncode != 0)

work = root / "work"
arc("begin", "work", "--worktree", str(work))
(work / "work.txt").write_text("edit\n")
git("add", ".", cwd=work)
git("commit", "-qm", "edit", cwd=work)
arc("snapshot", "work", "--solo", cwd=work)
arc("review", "work", "--verdict", "approved", "--body", "review", cwd=work)
arc("verify", "work", "--all", "--event", "publication", cwd=work)
before = arc("check", "work", "--json", expected=5, cwd=work)
check("publication evidence does not satisfy integration", not json.loads(before.stdout)["ready"])
arc("verify", "work", "--all", "--event", "integration", cwd=work)
after = arc("check", "work", "--json", cwd=work)
check("integration tier passes independently of publication-only requirements", json.loads(after.stdout)["ready"])

(root / "home/fail").write_text("fail publication\n")
rerun = ["--rerun"] if "--rerun" in arc("verify", "--help", cwd=work).stdout else []
failed_verification = arc("verify", "work", "--all", "--event", "publication", *rerun, expected=None, cwd=work)
if failed_verification.returncode == 0:
    raise SystemExit("a failing declared publication gate returned success")
after_failed_publication = arc("check", "work", "--json", cwd=work)
check("newer publication failure does not hide integration pass", json.loads(after_failed_publication.stdout)["ready"])
failed_guard = arc("publication", "--target", "master", "--profile", "local", expected=None)
check("standalone publication fails when a required gate fails", failed_guard.returncode != 0)
print(json.dumps(rows, indent=2))
