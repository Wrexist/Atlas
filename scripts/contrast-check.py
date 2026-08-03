#!/usr/bin/env python3
"""WCAG contrast audit for the Atlas colour tokens.

Light mode has never been rendered on a device, so the one thing that can
still be established about it without a simulator is whether its ink/surface
pairs are legible. Contrast is arithmetic, not taste: this reads the hex
literals straight out of `ColorTheme.swift` and `AppTheme.swift`, resolves
each token per scheme, and reports every pair below its WCAG 2.1 AA
threshold.

Thresholds (WCAG 2.1):
  * 4.5:1  normal body text
  * 3.0:1  large text (>=24pt, or >=18.66pt bold) and non-text UI such as
           icons, borders and chart strokes

Run: python3 scripts/contrast-check.py [--all]
`--all` also prints the pairs that pass.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
COLOR_THEME = REPO / "Peptide" / "DesignSystem" / "Theme" / "ColorTheme.swift"
APP_THEME = REPO / "Peptide" / "DesignSystem" / "Theme" / "AppTheme.swift"

AA_TEXT = 4.5
AA_LARGE = 3.0


def channel(value: int) -> float:
    srgb = value / 255
    return srgb / 12.92 if srgb <= 0.04045 else ((srgb + 0.055) / 1.055) ** 2.4


def luminance(hex_value: int) -> float:
    r = channel((hex_value >> 16) & 0xFF)
    g = channel((hex_value >> 8) & 0xFF)
    b = channel(hex_value & 0xFF)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(fg: int, bg: int) -> float:
    a, b = luminance(fg), luminance(bg)
    lighter, darker = max(a, b), min(a, b)
    return (lighter + 0.05) / (darker + 0.05)


def parse_tokens(path: pathlib.Path) -> dict[str, tuple[int, int]]:
    """name -> (light, dark). `Color(hex:)` resolves to the same value twice."""
    source = path.read_text()
    tokens: dict[str, tuple[int, int]] = {}
    for m in re.finditer(
        r"(?:static let|let)\s+(\w+)\s*(?::\s*Color\s*)?=\s*Color\(light:\s*0x([0-9A-Fa-f]{6}),\s*dark:\s*0x([0-9A-Fa-f]{6})",
        source,
    ):
        tokens[m.group(1)] = (int(m.group(2), 16), int(m.group(3), 16))
    for m in re.finditer(
        r"(?:static let|let)\s+(\w+)\s*(?::\s*Color\s*)?=\s*Color\(hex:\s*0x([0-9A-Fa-f]{6})", source
    ):
        tokens.setdefault(m.group(1), (int(m.group(2), 16), int(m.group(2), 16)))
    return tokens


def parse_ramps(path: pathlib.Path) -> dict[str, dict[str, tuple[int, int]]]:
    """ramp name -> stop name -> (light, dark)."""
    source = path.read_text()
    ramps: dict[str, dict[str, tuple[int, int]]] = {}
    for m in re.finditer(r"static let (\w+Ramp) = Ramp\((.*?)\n    \)", source, re.DOTALL):
        stops: dict[str, tuple[int, int]] = {}
        for s in re.finditer(
            r"(\w+):\s*Color\(light:\s*0x([0-9A-Fa-f]{6}),\s*dark:\s*0x([0-9A-Fa-f]{6})", m.group(2)
        ):
            stops[s.group(1)] = (int(s.group(2), 16), int(s.group(3), 16))
        for s in re.finditer(r"(\w+):\s*Color\(hex:\s*0x([0-9A-Fa-f]{6})", m.group(2)):
            stops.setdefault(s.group(1), (int(s.group(2), 16), int(s.group(2), 16)))
        ramps[m.group(1)] = stops
    return ramps


# Ink tokens and the threshold each is held to. Tokens that only ever colour a
# glyph, chart stroke or border are non-text under WCAG and get the 3:1 bar;
# anything that sets running text gets 4.5:1.
TEXT_INKS = ["textPrimary", "textSecondary", "textTertiary"]
UI_INKS = [
    "destructive", "warning", "positive", "negative", "belowRange", "recap",
    "streak", "achievement", "perceivedEffort",
    "macroProtein", "macroProteinLight", "macroWater", "macroWaterLight",
    "metricHeartRate", "metricHRV", "metricSleep", "metricActivity",
    "ringRecoveryStart", "ringRecoveryEnd", "ringSleepStart", "ringSleepEnd",
]
SURFACES = ["background", "surfaceElevated", "surfaceSecondary"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", action="store_true", help="also print passing pairs")
    args = parser.parse_args()

    tokens = parse_tokens(COLOR_THEME)
    ramps = parse_ramps(APP_THEME)
    missing = [n for n in TEXT_INKS + UI_INKS + SURFACES if n not in tokens]
    if missing:
        print(f"could not parse tokens: {', '.join(missing)}", file=sys.stderr)
        return 2

    rows: list[tuple[str, str, str, str, float, float, bool]] = []
    for scheme_index, scheme in enumerate(("light", "dark")):
        for surface in SURFACES:
            bg = tokens[surface][scheme_index]
            for ink, threshold in (
                [(i, AA_TEXT) for i in TEXT_INKS] + [(i, AA_LARGE) for i in UI_INKS]
            ):
                ratio = contrast(tokens[ink][scheme_index], bg)
                rows.append((scheme, ink, "on", surface, ratio, threshold, ratio >= threshold))
            for ramp, stops in ramps.items():
                for stop in ("primary", "light", "highlight"):
                    if stop not in stops:
                        continue
                    ratio = contrast(stops[stop][scheme_index], bg)
                    rows.append((scheme, f"{ramp}.{stop}", "on", surface,
                                 ratio, AA_TEXT, ratio >= AA_TEXT))

    # onAccent is the ink printed on a filled accent surface. That fill is
    # `AppColor.accentFill`, which maps to the ramp's `dark` stop — `primary`
    # is the ink-on-background stop and is far too bright in the dark scheme.
    for scheme_index, scheme in enumerate(("light", "dark")):
        for ramp, stops in ramps.items():
            if "dark" not in stops:
                continue
            ratio = contrast(tokens["onAccent"][scheme_index], stops["dark"][scheme_index])
            rows.append((scheme, "onAccent", "on", f"{ramp}.accentFill",
                         ratio, AA_TEXT, ratio >= AA_TEXT))

    failures = [r for r in rows if not r[6]]
    for scheme, ink, _, bg, ratio, threshold, ok in (rows if args.all else failures):
        mark = "pass" if ok else "FAIL"
        print(f"{mark}  {scheme:5}  {ink:26} on {bg:22} {ratio:5.2f}:1  (needs {threshold})")

    print(f"\n{len(rows)} pairs checked, {len(failures)} below AA", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
