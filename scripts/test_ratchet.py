"""Regression checks for ratchet.py, so a CI ratchet cannot pass a regression."""
import importlib.util
import json
import re
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("ratchet", Path(__file__).with_name("ratchet.py"))
ratchet = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ratchet)

LOWER = {"baseline": 10, "better": "lower"}
HIGHER = {"baseline": 25.0, "better": "higher"}


class VerdictTests(unittest.TestCase):
    def test_lowerIsBetter_valueAboveBaseline_fails(self):
        self.assertFalse(ratchet.verdict("warnings", 11, LOWER)[0])

    def test_lowerIsBetter_valueBelowBaseline_passesAndAsksToTighten(self):
        ok, message = ratchet.verdict("warnings", 9, LOWER)
        self.assertTrue(ok)
        self.assertIn("Tighten", message)

    def test_higherIsBetter_valueBelowBaseline_fails(self):
        self.assertFalse(ratchet.verdict("coverage", 24.9, HIGHER)[0])

    def test_higherIsBetter_valueAtBaseline_passes(self):
        self.assertTrue(ratchet.verdict("coverage", 25.0, HIGHER)[0])

    def test_unrecordedBaseline_passesWithWarning(self):
        ok, message = ratchet.verdict("coverage", 30, {"baseline": None, "better": "higher"})
        self.assertTrue(ok)
        self.assertIn("::warning::", message)

    def test_unrecordedBaseline_withRequireBaseline_fails(self):
        ok, message = ratchet.verdict("coverage", 30, {"baseline": None, "better": "higher"},
                                      require_baseline=True)
        self.assertFalse(ok)
        self.assertIn("::error::", message)

    def test_requireBaselineFlag_withRecordedBaseline_stillGatesOnValue(self):
        entries = json.loads(ratchet.BASELINES.read_text())
        baseline = entries["line_coverage_pct"]["baseline"]
        self.assertEqual(ratchet.main(["ratchet.py", "--require-baseline", "line_coverage_pct", str(baseline)]), 0)
        self.assertEqual(ratchet.main(["ratchet.py", "--require-baseline", "line_coverage_pct", str(baseline - 0.1)]), 1)

    def test_metricsRequiredInPRChecks_haveRecordedBaselines(self):
        workflow = Path(__file__).parent.parent / ".github/workflows/pr-checks.yml"
        required = re.findall(r"ratchet\.py --require-baseline (\w+)", workflow.read_text())
        self.assertTrue(required)
        entries = json.loads(ratchet.BASELINES.read_text())
        for name in required:
            self.assertIsNotNone(entries[name]["baseline"], name)

    def test_committedBaselines_nameTheirSource(self):
        for name, entry in json.loads(ratchet.BASELINES.read_text()).items():
            self.assertTrue(entry.get("source"), name)

    def test_unknownMetric_exitsWithUsageError(self):
        self.assertEqual(ratchet.main(["ratchet.py", "no_such_metric", "1"]), 2)

    def test_committedBaselines_haveValidDirections(self):
        for name, entry in json.loads(ratchet.BASELINES.read_text()).items():
            self.assertIn(entry["better"], ("lower", "higher"), name)


if __name__ == "__main__":
    unittest.main()
