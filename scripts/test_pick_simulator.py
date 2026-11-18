"""Regression checks for pick-simulator.py."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("pick", Path(__file__).with_name("pick-simulator.py"))
pick = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pick)

RT = "com.apple.CoreSimulator.SimRuntime."
DEVICES = {
    RT + "watchOS-11-0": [{"name": "Apple Watch Series 10", "udid": "W"}],
    RT + "iOS-18-2": [{"name": "iPhone 16 Pro", "udid": "A"}, {"name": "iPhone 16", "udid": "B"}],
    RT + "iOS-26-0": [{"name": "iPhone 17 Pro", "udid": "C"}, {"name": "iPhone 16 Pro", "udid": "D"}],
    RT + "iOS-18-10": [{"name": "iPhone 16 Pro", "udid": "E"}],
}


def udid(devices, preferred):
    choice = pick.pick(devices, preferred)
    return choice[0]["udid"] if choice else None


class PickSimulatorTests(unittest.TestCase):
    def test_preferredModel_onNewestRuntime_isChosen(self):
        self.assertEqual(udid(DEVICES, ["iPhone 16 Pro"]), "D")

    def test_runtimeVersions_compareNumerically_notAsText(self):
        older = {k: v for k, v in DEVICES.items() if "26" not in k}
        self.assertEqual(udid(older, ["iPhone 16 Pro"]), "E")

    def test_missingPreferredModel_fallsBackToNewestRuntimeIPhone(self):
        self.assertEqual(udid(DEVICES, ["iPhone 99"]), "C")

    def test_preferenceOrder_isRespected(self):
        self.assertEqual(udid(DEVICES, ["iPhone 16", "iPhone 16 Pro"]), "B")

    def test_preferredModelOnlyBelowDeploymentTarget_fallsBackToSupportedIPhone(self):
        devices = {RT + "iOS-17-5": [{"name": "iPhone 15", "udid": "OLD"}],
                   RT + "iOS-18-0": [{"name": "iPhone 16", "udid": "NEW"}]}
        self.assertEqual(udid(devices, ["iPhone 15"]), "NEW")

    def test_onlyRuntimesBelowDeploymentTarget_returnsNone(self):
        self.assertIsNone(udid({RT + "iOS-17-5": [{"name": "iPhone 15", "udid": "OLD"}]}, ["iPhone 15"]))

    def test_noIPhone_returnsNone(self):
        self.assertIsNone(udid({RT + "watchOS-11-0": DEVICES[RT + "watchOS-11-0"]}, []))


if __name__ == "__main__":
    unittest.main()
