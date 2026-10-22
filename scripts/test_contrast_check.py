"""Regression checks for contrast-check.py, so it cannot go blind silently."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("contrast", Path(__file__).with_name("contrast-check.py"))
contrast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contrast)


class ContrastMathTests(unittest.TestCase):
    def test_black_on_white_is_maximum_ratio(self):
        self.assertAlmostEqual(contrast.contrast(0x000000, 0xFFFFFF), 21.0, places=2)

    def test_known_failing_pair_is_below_text_threshold(self):
        # #777777 on white is the textbook near miss: 4.48:1.
        self.assertLess(contrast.contrast(0x777777, 0xFFFFFF), contrast.AA_TEXT)

    def test_ratio_ignores_argument_order(self):
        self.assertEqual(contrast.contrast(0x336699, 0xF4F4F7), contrast.contrast(0xF4F4F7, 0x336699))


class TokenParsingTests(unittest.TestCase):
    def parse(self, source):
        with tempfile.NamedTemporaryFile("w", suffix=".swift", delete=False) as f:
            f.write(source)
        self.addCleanup(Path(f.name).unlink)
        return contrast.parse_tokens(Path(f.name))

    def test_light_dark_and_single_hex_tokens_parse(self):
        tokens = self.parse("""
            static let background = Color(light: 0xF4F4F7, dark: 0x101013)
            static let onAccent: Color = Color(hex: 0xFFFFFF)
        """)
        self.assertEqual(tokens["background"], (0xF4F4F7, 0x101013))
        self.assertEqual(tokens["onAccent"], (0xFFFFFF, 0xFFFFFF))

    def test_every_audited_token_resolves_in_the_real_theme(self):
        tokens = contrast.parse_tokens(contrast.COLOR_THEME)
        audited = contrast.TEXT_INKS + contrast.UI_INKS + contrast.SURFACES + ["onAccent"]
        self.assertEqual([name for name in audited if name not in tokens], [])

    def test_real_theme_ramps_parse(self):
        ramps = contrast.parse_ramps(contrast.APP_THEME)
        self.assertTrue(ramps, "No accent ramps parsed from AppTheme.swift")
        for name, stops in ramps.items():
            with self.subTest(ramp=name):
                self.assertIn("primary", stops)


if __name__ == "__main__":
    unittest.main()
