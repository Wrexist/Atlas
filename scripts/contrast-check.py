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
MODEL_COLORS = REPO / "Peptide" / "DesignSystem" / "Theme" / "ModelColors.swift"
HABIT = REPO / "Peptide" / "Models" / "Habit.swift"
WATCH_PALETTE = REPO / "Shared" / "WatchPalette.swift"

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


def extension_block(path: pathlib.Path, type_name: str) -> str:
    """The body of `extension <type_name> {` up to the next top-level brace."""
    source = path.read_text()
    start = source.index(f"extension {type_name} {{")
    end = source.find("\n}\n", start)
    return source[start:end]


def parse_categories(path: pathlib.Path) -> dict[str, tuple[int, int]]:
    """PeptideCategory case -> (light, dark)."""
    return {
        m.group(1): (int(m.group(2), 16), int(m.group(3), 16))
        for m in re.finditer(
            r"case \.(\w+):\s*Color\(light:\s*0x([0-9A-Fa-f]{6}),\s*dark:\s*0x([0-9A-Fa-f]{6})",
            extension_block(path, "PeptideCategory"),
        )
    }


def parse_tiers() -> dict[str, tuple[int, int]]:
    """Momentum tier -> (light, dark). The dark half is the Watch's shared hex."""
    dark = {
        m.group(1): int(m.group(2), 16)
        for m in re.finditer(r'case "(\w+)": return 0x([0-9A-Fa-f]{6})', WATCH_PALETTE.read_text())
    }
    bronze = re.search(r"default: return 0x([0-9A-Fa-f]{6})", WATCH_PALETTE.read_text())
    dark["bronze"] = int(bronze.group(1), 16)
    return {
        m.group(1): (int(m.group(2), 16), dark[m.group(1)])
        for m in re.finditer(
            r"case \.(\w+):\s*Color\(light:\s*0x([0-9A-Fa-f]{6}),\s*dark:\s*UInt\(tintHex\)",
            extension_block(MODEL_COLORS, "MomentumEngine.Tier"),
        )
    }


def parse_habit_tints() -> dict[str, tuple[int, int]]:
    """Habit swatch identity hex -> (light, dark)."""
    return {
        f"0x{m.group(1).upper()}": (int(m.group(2), 16), int(m.group(3), 16))
        for m in re.finditer(
            r"Swatch\(hex:\s*0x([0-9A-Fa-f]{6}),\s*light:\s*0x([0-9A-Fa-f]{6}),\s*dark:\s*0x([0-9A-Fa-f]{6})\)",
            HABIT.read_text(),
        )
    }


def blend(fg: int, bg: int, alpha: float) -> int:
    """`fg.opacity(alpha)` composited over an opaque `bg`."""
    out = 0
    for shift in (16, 8, 0):
        f, b = (fg >> shift) & 0xFF, (bg >> shift) & 0xFF
        out |= round(f * alpha + b * (1 - alpha)) << shift
    return out


# Ink tokens and the threshold each is held to. Tokens that only ever colour a
# glyph, chart stroke or border are non-text under WCAG and get the 3:1 bar;
# anything that sets running text gets 4.5:1.
TEXT_INKS = ["textPrimary", "textSecondary", "textTertiary", "cycleWashout"]
UI_INKS = [
    "destructive", "warning", "positive", "negative", "belowRange", "recap",
    "streak", "achievement", "perceivedEffort",
    "macroProtein", "macroProteinLight", "macroWater", "macroWaterLight",
    "macroCarbs", "macroFat",
    "metricHeartRate", "metricHRV", "metricSleep", "metricActivity",
    "ringRecoveryStart", "ringRecoveryEnd", "ringSleepStart", "ringSleepEnd",
    "mealBreakfast", "mealLunch", "mealDinner", "mealSnack",
    "outcomeEnergy", "outcomeSleepQuality", "outcomeRecovery", "outcomeMood", "outcomeFocus",
]
# Lab category inks set the 11pt short name on their own 0.2 tile.
LAB_INKS = [
    "labSexHormones", "labGrowth", "labThyroid", "labMetabolic",
    "labLipids", "labOrganHealth", "labOther",
]
SURFACES = ["background", "surfaceElevated", "surfaceSecondary"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", action="store_true", help="also print passing pairs")
    args = parser.parse_args()

    tokens = parse_tokens(COLOR_THEME)
    ramps = parse_ramps(APP_THEME)
    missing = [n for n in TEXT_INKS + UI_INKS + LAB_INKS + SURFACES if n not in tokens]
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

    # washInk is the ink on the accent's own wash: `.tinted` Badge fills at
    # 0.2, `.primary` GlassButton and selected `.glass` GlassChip at 0.18.
    # Test the heavier one.
    for scheme_index, scheme in enumerate(("light", "dark")):
        for ramp, stops in ramps.items():
            for surface in SURFACES:
                wash = blend(stops["primary"][scheme_index], tokens[surface][scheme_index], 0.2)
                ratio = contrast(stops["washInk"][scheme_index], wash)
                rows.append((scheme, f"{ramp}.washInk", "on", f"{surface}+wash",
                             ratio, AA_TEXT, ratio >= AA_TEXT))

    # Tinted text on its own wash: PeptideCategory colours set 11-13pt badge
    # and chip text on a 0.15-0.2 wash, lab inks the 11pt short name on a 0.2
    # tile, habit tints the 11pt weekly count on a 0.12 wash. All of it is
    # small text, so both schemes are held to 4.5:1 on the heaviest wash.
    washed_inks = (
        [(f"category.{n}", pair, 0.2) for n, pair in parse_categories(MODEL_COLORS).items()]
        + [(n, tokens[n], 0.2) for n in LAB_INKS]
        + [(f"habit.{n}", pair, 0.12) for n, pair in parse_habit_tints().items()]
    )
    for name, pair, alpha in washed_inks:
        for scheme_index, scheme in enumerate(("light", "dark")):
            ink = pair[scheme_index]
            for surface in SURFACES:
                wash = blend(ink, tokens[surface][scheme_index], alpha)
                ratio = contrast(ink, wash)
                rows.append((scheme, name, "on", f"{surface}+wash",
                             ratio, AA_TEXT, ratio >= AA_TEXT))

    # Momentum tier tints print the "Level N · Gold" line straight on a surface.
    for tier, pair in parse_tiers().items():
        for scheme_index, scheme in enumerate(("light", "dark")):
            for surface in SURFACES:
                ratio = contrast(pair[scheme_index], tokens[surface][scheme_index])
                rows.append((scheme, f"tier.{tier}", "on", surface,
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
            # The fill itself is a UI component (WCAG 1.4.11): it has to
            # separate from the surfaces it sits on, not just carry its ink.
            for surface in SURFACES:
                ratio = contrast(stops["dark"][scheme_index], tokens[surface][scheme_index])
                rows.append((scheme, f"{ramp}.accentFill", "on", surface,
                             ratio, AA_LARGE, ratio >= AA_LARGE))

    # Completion uses its own quiet surfaces rather than the app's glass ramp.
    for index, scheme in enumerate(("light", "dark")):
        for surface in ("recapBackground", "recapCard", "recapRaised"):
            for ink in ("recapText", "recapSecondary", "recapAction", "trainingPrimaryMuscle", "trainingSecondaryMuscle"):
                ratio = contrast(tokens[ink][index], tokens[surface][index])
                rows.append((scheme, ink, "on", surface, ratio, AA_TEXT, ratio >= AA_TEXT))
        ratio = contrast(tokens["recapButtonInk"][index], tokens["recapButton"][index])
        rows.append((scheme, "recapButtonInk", "on", "recapButton", ratio, AA_TEXT, ratio >= AA_TEXT))

    failures = [r for r in rows if not r[6]]
    for scheme, ink, _, bg, ratio, threshold, ok in (rows if args.all else failures):
        mark = "pass" if ok else "FAIL"
        print(f"{mark}  {scheme:5}  {ink:26} on {bg:22} {ratio:5.2f}:1  (needs {threshold})")

    print(f"\n{len(rows)} pairs checked, {len(failures)} below AA", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
