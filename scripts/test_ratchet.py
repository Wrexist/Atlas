"""Regression checks for ratchet.py, so a CI ratchet cannot pass a regression."""
import importlib.util
import json
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

    def test_unknownMetric_exitsWithUsageError(self):
        self.assertEqual(ratchet.main(["ratchet.py", "no_such_metric", "1"]), 2)

    def test_committedBaselines_haveValidDirections(self):
        for name, entry in json.loads(ratchet.BASELINES.read_text()).items():
            self.assertIn(entry["better"], ("lower", "higher"), name)


if __name__ == "__main__":
    unittest.main()
