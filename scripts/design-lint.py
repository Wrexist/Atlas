#!/usr/bin/env python3
"""Visual-craft checker for the Atlas SwiftUI codebase.

SwiftLint catches Swift-level problems; this catches *design-system* ones,
which are the failures that actually reach users as an app that looks
assembled by different people. Each rule below exists because the codebase
had real instances of it.

Run it directly (`python3 scripts/design-lint.py`) or via CI, which fails on
any error-severity finding. `--all` also prints warnings.

Rules are deliberately conservative: a rule that cries wolf gets suppressed
and then stops protecting anything. Where a pattern has legitimate uses, the
file or construct is allowlisted explicitly rather than the rule being
softened.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
from dataclasses import dataclass

REPO = pathlib.Path(__file__).resolve().parent.parent
FEATURES = REPO / "Peptide" / "Features"
DESIGN_SYSTEM = REPO / "Peptide" / "DesignSystem"

# Surfaces whose palette encodes a real-world concept rather than the brand,
# or which are composited onto a permanently dark backdrop (share cards,
# anatomy, photo viewers). Documented in ColorTheme.swift.
DOMAIN_PALETTE_FILES = {
    "WhatsNewPage.swift", "MuscleMapView.swift", "CycleCardView.swift",
    "ProtocolNotesTimeline.swift", "AvatarPreset.swift", "HabitEditSheet.swift",
    "BarcodeScanFlow.swift", "ShareCardSheet.swift", "AnatomyDebugView.swift",
    "ProgressPhotoViewer.swift", "ProgressPhotoCompareView.swift",
    "PaywallPhoneMockupRow.swift", "CompoundVial.swift",
}

# The 8-point grid, plus the half-step (2) and the odd-but-intentional 6 used
# for tiny icon insets. Anything else is a number someone eyeballed.
GRID = {0, 2, 4, 6, 8, 12, 16, 20, 24, 32, 40, 48, 56, 64}

PLACEHOLDER_COPY = re.compile(
    r'"(?:[^"]*\b(?:lorem ipsum|placeholder text|dummy|foo bar|coming soon|tbd|todo:)\b[^"]*)"',
    re.IGNORECASE,
)


@dataclass
class Finding:
    path: pathlib.Path
    line: int
    rule: str
    message: str
    severity: str  # "error" | "warning"

    def format(self) -> str:
        rel = self.path.relative_to(REPO)
        return f"{rel}:{self.line}: {self.severity}: [{self.rule}] {self.message}"


def swift_files(root: pathlib.Path):
    for path in sorted(root.rglob("*.swift")):
        yield path, path.read_text()


def strip_comments(source: str) -> str:
    """Blank out comments so rules don't fire on prose that describes them."""
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    return re.sub(r"//[^\n]*", "", source)


def line_of(source: str, index: int) -> int:
    return source.count("\n", 0, index) + 1


# --------------------------------------------------------------------------
# Rules
# --------------------------------------------------------------------------

def rule_raw_colour(path, source, code) -> list[Finding]:
    """Feature views must resolve colour through AppColor, or light mode and
    the brand themes silently skip that screen."""
    if path.name in DOMAIN_PALETTE_FILES or FEATURES not in path.parents:
        return []
    out = []
    for m in re.finditer(r"Color\((?:hex:\s*0x|red:\s*[\d.])", code):
        out.append(Finding(path, line_of(code, m.start()), "raw-colour",
                           "raw Color literal; use an AppColor token", "error"))
    for m in re.finditer(r"Color\.(?:white|black)\b", code):
        # A drop shadow and a modal dimming scrim are black in both schemes —
        # that's what a shadow *is*. Only ink and fills need to adapt.
        context = code[max(0, m.start() - 60):m.start()]
        if re.search(r"\.shadow\(\s*color:\s*$|shadow\(color:\s*$", context):
            continue
        if re.search(r"^\s*$", context.split("\n")[-1]) and "ignoresSafeArea" in code[m.end():m.end() + 120]:
            continue
        out.append(Finding(path, line_of(code, m.start()), "raw-colour",
                           "Color.white/.black doesn't adapt; use AppColor.onAccent "
                           "(on an accent fill) or AppColor.textPrimary", "error"))
    return out


def rule_fixed_font(path, source, code) -> list[Finding]:
    """Font.system(size:) ignores the content-size category outright."""
    if path.name == "Typography.swift":
        return []
    out = []
    for m in re.finditer(r"\.system\(size:\s*(\d+(?:\.\d+)?)", code):
        if float(m.group(1)) <= 24:
            out.append(Finding(path, line_of(code, m.start()), "fixed-font",
                               f"{m.group(1)}pt is body scale and must use "
                               "AppFont.scaled(_:) to honour Dynamic Type", "error"))
    return out


def rule_glow(path, source, code) -> list[Finding]:
    """A shadow in a hue other than black is a glow. Glows read as 2018
    'gamer UI'; depth should come from the material, not from a halo."""
    out = []
    for m in re.finditer(r"\.shadow\(\s*color:\s*([^,]+),[^)]*radius:\s*(\d+(?:\.\d+)?)", code):
        colour, radius = m.group(1).strip(), float(m.group(2))
        if re.search(r"\.black|\.clear|Color\.black|AppShadow", colour):
            continue
        if radius >= 10:
            out.append(Finding(path, line_of(code, m.start()), "glow",
                               f"coloured shadow at radius {radius:g} reads as a glow; "
                               "use AppShadow or drop it", "warning"))
    return out


def balanced_args(code: str, open_index: int) -> str | None:
    """Text between the parens starting at `open_index`, respecting nesting.

    Naive `[^)]*` matching breaks on every multi-line or nested call, which
    makes a rule fire on correct code — and a rule that cries wolf gets
    suppressed rather than obeyed.
    """
    depth = 0
    for i in range(open_index, len(code)):
        if code[i] == "(":
            depth += 1
        elif code[i] == ")":
            depth -= 1
            if depth == 0:
                return code[open_index + 1:i]
    return None


def rule_untargeted_animation(path, source, code) -> list[Finding]:
    """`.animation(x)` without a value animates *every* change to the view —
    SwiftUI's equivalent of `transition: all`. Deprecated since iOS 15."""
    out = []
    for m in re.finditer(r"\.animation\(", code):
        # `TimelineView(.animation(minimumInterval:))` is a schedule, and
        # `$binding.animation(_:)` is a Binding transform — neither is the
        # deprecated view modifier.
        before = code[max(0, m.start() - 40):m.start()]
        if re.search(r"TimelineView\(\s*$", before) or re.search(r"\$\w+$", before):
            continue
        args = balanced_args(code, m.end() - 1)
        if args is None or "value:" in args or not args.strip():
            continue
        out.append(Finding(path, line_of(code, m.start()), "untargeted-animation",
                           "`.animation(_:)` without `value:` animates every change; "
                           "name the property that should animate", "error"))
    return out


def rule_placeholder_copy(path, source, code) -> list[Finding]:
    out = []
    for m in PLACEHOLDER_COPY.finditer(code):
        out.append(Finding(path, line_of(code, m.start()), "placeholder-copy",
                           f"placeholder string ships to users: {m.group(0)[:50]}", "error"))
    return out


def rule_hit_target(path, source, code) -> list[Finding]:
    """A control smaller than 44pt is hard to hit and fails an accessibility
    audit. Only flags frames inside a Button/tap-gesture label."""
    out = []
    for m in re.finditer(r"\.frame\(width:\s*(\d+),\s*height:\s*(\d+)\)", code):
        w, h = int(m.group(1)), int(m.group(2))
        if min(w, h) >= 44:
            continue
        window = code[max(0, m.start() - 600):m.start()]
        if not re.search(r"\bButton\b|onTapGesture", window):
            continue
        # An explicit contentShape/padding after the frame can still expand it.
        after = code[m.end():m.end() + 240]
        if "contentShape" in after or re.search(r"\.padding\(", after):
            continue
        out.append(Finding(path, line_of(code, m.start()), "hit-target",
                           f"{w}×{h} tap target is under Spacing.minimumHitTarget (44)",
                           "warning"))
    return out


def rule_off_grid_spacing(path, source, code) -> list[Finding]:
    """Padding and stack spacing come from Spacing so the rhythm is one
    decision, not two hundred."""
    out = []
    patterns = [
        r"\.padding\((?:\.\w+,\s*)?(\d+)\)",
        r"(?:VStack|HStack|LazyVStack|LazyHStack)\(\s*(?:alignment:[^,]+,\s*)?spacing:\s*(\d+)\)",
    ]
    for pattern in patterns:
        for m in re.finditer(pattern, code):
            value = int(m.group(1))
            if value in GRID:
                continue
            out.append(Finding(path, line_of(code, m.start()), "off-grid",
                               f"{value}pt is off the 8-point grid; use a Spacing token",
                               "warning"))
    return out


def rule_low_contrast_ink(path, source, code) -> list[Finding]:
    """Text at under 55% opacity on a glass surface fails WCAG AA at small
    sizes. Tokens already encode the intended hierarchy."""
    out = []
    for m in re.finditer(r"\.foregroundStyle\(\s*AppColor\.\w+\.opacity\(0?\.([0-4]\d?)\)", code):
        frac = float("0." + m.group(1))
        out.append(Finding(path, line_of(code, m.start()), "low-contrast",
                           f"ink at {frac:g} opacity; use textSecondary/textTertiary "
                           "instead of fading a token", "warning"))
    return out


def rule_unlabelled_icon_button(path, source, code) -> list[Finding]:
    """A Button whose label is only an SF Symbol is an unlabelled control to
    VoiceOver — it announces the symbol name or nothing."""
    out = []
    lines = code.splitlines()
    for i, line in enumerate(lines):
        if not re.match(r"\s*(?:return )?Button\b", line):
            continue
        depth, started, end = 0, False, i
        for j in range(i, min(i + 70, len(lines))):
            for ch in lines[j]:
                if ch == "{":
                    depth += 1
                    started = True
                elif ch == "}":
                    depth -= 1
            end = j
            if started and depth <= 0:
                break
        block = "\n".join(lines[i:end + 1])
        tail = "\n".join(lines[end:end + 10])
        if "Image(systemName:" not in block:
            continue
        if re.search(r"\bText\(|\bLabel\(|Row\(|Card\(", block):
            continue
        if "accessibilityLabel" in block or "accessibilityLabel" in tail:
            continue
        out.append(Finding(path, i + 1, "unlabelled-icon-button",
                           "icon-only Button needs an accessibilityLabel", "error"))
    return out


def rule_stacked_glass(path, source, code) -> list[Finding]:
    """Painting the legacy translucent recipe *and* compositing glassEffect
    stacks two materials — the bug that made every control muddy on iOS 26."""
    out = []
    for m in re.finditer(r"\.liquidGlass\(", code):
        window = code[max(0, m.start() - 900):m.start()]
        if re.search(r"\.(?:background|overlay)\s*\{[^}]*(?:Capsule|RoundedRectangle|Circle)\(\)?[^}]*\.fill\(", window, re.DOTALL):
            out.append(Finding(path, line_of(code, m.start()), "stacked-glass",
                               "a filled shape under .liquidGlass stacks two materials; "
                               "route through glassSurface/glassControl", "warning"))
    return out


RULES = [
    rule_raw_colour,
    rule_fixed_font,
    rule_glow,
    rule_untargeted_animation,
    rule_placeholder_copy,
    rule_hit_target,
    rule_off_grid_spacing,
    rule_low_contrast_ink,
    rule_unlabelled_icon_button,
    rule_stacked_glass,
]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", action="store_true",
                        help="print warnings as well as errors")
    parser.add_argument("--rule", help="run a single rule by name")
    args = parser.parse_args()

    findings: list[Finding] = []
    for root in (FEATURES, DESIGN_SYSTEM):
        for path, source in swift_files(root):
            code = strip_comments(source)
            for rule in RULES:
                if args.rule and rule.__name__ != f"rule_{args.rule.replace('-', '_')}":
                    continue
                findings.extend(rule(path, source, code))

    errors = [f for f in findings if f.severity == "error"]
    warnings = [f for f in findings if f.severity == "warning"]

    for finding in errors:
        print(finding.format())
    if args.all:
        for finding in warnings:
            print(finding.format())

    by_rule: dict[str, int] = {}
    for finding in findings:
        by_rule[finding.rule] = by_rule.get(finding.rule, 0) + 1

    print(f"\n{len(errors)} error(s), {len(warnings)} warning(s)", file=sys.stderr)
    for rule, count in sorted(by_rule.items(), key=lambda kv: -kv[1]):
        print(f"  {count:4}  {rule}", file=sys.stderr)

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
