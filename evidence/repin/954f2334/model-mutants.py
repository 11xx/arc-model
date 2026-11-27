"""From the project root, kill eight precise faults for 954f2334 and restore all sources."""
from pathlib import Path
import os
import subprocess

cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "arc-model/repin/954f2334"
cache.mkdir(parents=True, exist_ok=True)
budget = Path("src/Arc/Model/Budget.hs")
declaration = Path("src/Arc/Model/Declaration.hs")
coverage = Path("src/Arc/Model/Coverage.hs")
original = {p: p.read_text() for p in (budget, declaration, coverage)}
mutants = [
    ("suspension-ignores-locality", {budget: [
        ("  =  suspension.origin == LocalLedger\n", "  =  True\n")]},
        "suspension/locality: imported suspension accepts nothing"),
    ("suspension-permits-publication", {budget: [
        ("        Publication -> BudgetRefused BudgetRefusedOverBudget\n",
         "        Publication -> case newest (filter (suspensionCovers now gate) suspensions) of\n"
         "          Just active -> BudgetSuspended active.suspensionId\n"
         "          Nothing     -> BudgetRefused BudgetRefusedOverBudget\n")]},
        "suspension/publication: publication judges strictly despite active suspension"),
    ("suspension-lifts-failure", {budget: [
        ("  | result /= GatePass                          = BudgetRefused (BudgetRefusedGateOutcome result)\n",
         "  | result == GateNotAdmitted                   = BudgetRefused (BudgetRefusedGateOutcome result)\n")]},
        "suspension/strict: failing gate still fails under active suspension"),
    ("suspension-seeds-reference", {budget: [
        ("eligibleAsWorkReference result timing recordedUnderSuspension\n"
         "  = result == GatePass && timing == RunWithinBudget && not recordedUnderSuspension\n",
         "eligibleAsWorkReference result timing _recordedUnderSuspension\n"
         "  = result == GatePass && timing == RunWithinBudget\n")]},
        "suspension/seed: run recorded under suspension never becomes a work reference"),
    ("budget-table-landing-enforces", {budget: [
        ("  =  not table.hasLanding\n", "  =  True\n")]},
        "budget-table/E1: landing-only table does not enforce"),
    ("confinement-admits-head-roots", {declaration: [
        ("  { writes   = Set.union (rootsOf destination) (rootsOf operator)\n",
         "  { writes   = Set.unions [rootsOf destination, rootsOf operator, rootsOf headConfine]\n")]},
        "confinement/E2: head widening roots are ignored while head required=true enforces"),
    ("earlier-waiver-not-retired", {coverage: [
        ("  Just record -> case waiverRetiredBy state debt of\n"
         "    Just event -> StandingRetired event\n"
         "    Nothing    -> maybe StandingOwed StandingDischarged (answering record)\n",
         "  Just record -> maybe StandingOwed StandingDischarged (answering record)\n")]},
        "debt/retire: independent approval of shipped ps-02 retires ps-01 ineligible-review waiver"),
    ("gate-trailers-outside-identity", {declaration: [
        ("  , gateTrailers   = declaration.gateTrailers\n", "  , gateTrailers   = Nothing\n")]},
        "gate-trailers/identity: changing Witness or Change-size trailer invalidates pass at same tree"),
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
    Path("evidence/repin/954f2334/model-mutants.txt").write_text("\n".join(summary) + "\n")
