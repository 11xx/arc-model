"""From the project root, kill four precise faults and restore all sources."""
from pathlib import Path
import os
import subprocess

cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "arc-model/repin/35f9501d"
cache.mkdir(parents=True, exist_ok=True)
declaration = Path("src/Arc/Model/Declaration.hs")
coverage = Path("src/Arc/Model/Coverage.hs")
original = {p: p.read_text() for p in (declaration, coverage)}
mutants = [
    ("confinement-outside-identity", {declaration: [
        ("  , confinement    = declaration.confinement\n", "  , confinement    = Nothing\n")]},
        "confinement/identity: an unconfined pass does not answer a confined declaration"),
    ("verdict-never-clears", {coverage: [
        ("  [ ReadByVerdict v.event | v <- state.verdicts, verdictClears state debt v ]\n  <> ", "  ")]},
        "debt/ineligible-verdict: an assessed verdict on the shipped patchset clears"),
    ("verdict-binding-ignored", {coverage: [
        ("    && assessmentBinding state debt verdict.model assessment == Bound\n", "")]},
        "debt/ineligible-verdict: an unbound assessment leaves it owed"),
    ("verdict-ineligible-discharges", {coverage: [
        ("      , assessmentAllows v.assessment\n      , verdictIsIndependent state v == Just ()\n",
         "      , verdictIsIndependent state v == Just ()\n")]},
        "debt/ordinary-verdict: an ineligible assessment leaves ordinary debt owed"),
]
summary = []
try:
    for name, changes, predicted in mutants:
        for path, content in original.items():
            path.write_text(content)
        for path, replacements in changes.items():
            content = original[path]
            for before, after in replacements:
                if content.count(before) != 1:
                    raise SystemExit("mutation anchor absent or ambiguous: " + name)
                content = content.replace(before, after)
            path.write_text(content)
        result = subprocess.run(["cabal", "v2-test", "spec", "--test-show-details=direct", "-j1",
                                 "+RTS", "-M1g", "-RTS"],
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
    Path("evidence/repin/35f9501d/model-mutants.txt").write_text("\n".join(summary) + "\n")
