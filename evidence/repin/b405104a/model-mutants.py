"""From the project root, kill five precise faults and restore all sources."""
from pathlib import Path
import os
import subprocess

cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "arc-model/repin/b405104a"
paths = [Path("src/Arc/Model") / name for name in
         ["Gate.hs", "GatePlan.hs", "Coverage.hs", "Discharge.hs"]]
original = {p: p.read_text() for p in paths}
gate, selector, coverage, discharge = paths
mutants = [
    ("admission-as-pass", {gate: [
        ("Observed GateNotAdmitted -> Left (GateWasNotAdmitted gate event)",
         "Observed GateNotAdmitted -> Right reading")]}, "admission/newest"),
    ("bypass-as-execution", {gate: [
        ("filter ((/= Bypassed) . (.execution)) history", "history"),
        ("(Bypassed, _)                        -> BypassRecorded",
         "(Bypassed, _)                        -> environmentCoverage v")]}, "bypass/integration"),
    ("acknowledgment-ignored", {selector: [
        ("SelectionComplete acknowledged affected", "SelectionComplete _acknowledged affected"),
        ("  , acknowledged == SelectorRequest delta known\n", "")]}, "selector/acknowledgment: a different delta"),
    ("comment-as-judgment", {coverage: [
        ("      , a.kind /= CommentOnly\n", ""),
        ("    && audit.kind /= CommentOnly\n", ""),
        (", a.kind /= CommentOnly, assessmentAllows a", ", assessmentAllows a"),
        ("      , v.kind /= CommentOnly\n", "")],
        discharge: [("clears       = audit.kind /= CommentOnly", "clears       = True")]},
        "debt/comment-only"),
    ("ineligible-ignored", {coverage: [
        ("assessmentAllows audit = maybe True ((== Eligible) . (.independence)) audit.assessment",
         "assessmentAllows _audit = True")],
        discharge: [("&& maybe True ((== Eligible) . (.independence)) audit.assessment", "&& True")]},
        "debt/ineligible"),
]
summary = []
try:
    for name, changes, predicted in mutants:
        for path, content in original.items():
            path.write_text(content)
        for path, replacements in changes.items():
            content = original[path]
            for before, after in replacements:
                if before not in content:
                    raise SystemExit("mutation anchor absent: " + name)
                content = content.replace(before, after)
            path.write_text(content)
        result = subprocess.run(["cabal", "v2-test", "spec", "--test-show-details=direct", "-j1"],
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (cache / ("mutant-" + name + ".log")).write_text(result.stdout)
        failures = [line for line in result.stdout.splitlines() if line.startswith("[FAIL]")]
        if result.returncode == 0 or not any(predicted in line for line in failures):
            raise SystemExit("fault did not fail for the predicted semantic reason: " + name)
        summary.append(name + ": exit " + str(result.returncode) + "; predicted rejection: " + predicted)
        summary.extend(failures)
        print(summary[-len(failures)-1], flush=True)
finally:
    for path, content in original.items():
        path.write_text(content)
    Path("evidence/repin/b405104a/model-mutants.txt").write_text("\n".join(summary) + "\n")
