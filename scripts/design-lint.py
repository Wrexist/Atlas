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

# The six body-text steps. Mirrors `AppFont.Scale`; anything above 24pt is a
# display glyph sized per screen and isn't part of the scale.
TYPE_SCALE = {8, 11, 13, 16, 20, 24}

# Rendered to a fixed export canvas rather than laid out in the app, so its
# proportions are its own — the 8-point rhythm doesn't govern a shared image.
FIXED_CANVAS_FILES = {"CycleCardView.swift", "ShareCardSheet.swift"}

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


def blank_previews(source: str) -> str:
    """Replace `#Preview { … }` bodies with blank lines.

    Preview scaffolding isn't shipping UI — a hardcoded 200pt spacer that
    positions a demo button says nothing about the app's rhythm — but line
    numbers still have to line up with the file, so the text is blanked
    rather than removed.
    """
    out = source
    for m in reversed(list(re.finditer(r"#Preview\b[^{]*\{", source))):
        depth, i = 0, m.end() - 1
        while i < len(source):
            if source[i] == "{":
                depth += 1
            elif source[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        span = source[m.start():i + 1]
        out = out[:m.start()] + re.sub(r"[^\n]", " ", span) + out[i + 1:]
    return out


def line_of(source: str, index: int) -> int:
    return source.count("\n", 0, index) + 1


def enclosing_block(code: str, index: int) -> tuple[int, str]:
    """The innermost `{ … }` containing `index`, as (brace position, text).

    Used by rules that need structural context — "is this VStack sitting in a
    ZStack next to a ScrollView?" — which no single regex can answer. The
    position is returned because the construct that owns a block is written
    *before* its brace, so the caller has to look back past it.
    """
    depth, start = 0, None
    for i in range(index - 1, -1, -1):
        if code[i] == "}":
            depth += 1
        elif code[i] == "{":
            if depth == 0:
                start = i
                break
            depth -= 1
    if start is None:
        return -1, ""
    depth = 0
    for i in range(start, len(code)):
        if code[i] == "{":
            depth += 1
        elif code[i] == "}":
            depth -= 1
            if depth == 0:
                return start, code[start:i + 1]
    return start, code[start:]


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
    """`Font.system(size:)` ignores the content-size category outright.

    Body scale must go through `AppFont.scaled(_:)`. Display sizes above the
    scale used to be exempt, on the theory that a 56pt headline is already
    large — but "already large" is not the same as "large enough for someone
    at Accessibility XXXL", where body copy grows past a fixed 26pt heading
    and the hierarchy inverts. Display *text* now needs
    `relativeTo: .largeTitle`, which grows it on a display curve rather than
    the body one. Glyphs and share cards keep fixed sizes: an SF Symbol is
    art, and a share card renders to a fixed export canvas.
    """
    if path.name == "Typography.swift":
        return []
    out = []
    lines = code.split("\n")
    for m in re.finditer(r"\.system\(size:\s*(\d+(?:\.\d+)?)", code):
        size = float(m.group(1))
        line = line_of(code, m.start())
        if size <= 24:
            out.append(Finding(path, line, "fixed-font",
                               f"{m.group(1)}pt is body scale and must use "
                               "AppFont.scaled(_:) to honour Dynamic Type", "error"))
            continue
        if path.name in FIXED_CANVAS_FILES:
            continue
        # Only Text carries the Dynamic Type contract; a symbol is a glyph.
        j = line - 1
        while j > 0 and not re.search(r"\b(Text|Image|Label)\(", lines[j]):
            j -= 1
        anchor = re.search(r"\b(Text|Image|Label)\(", lines[j])
        if not anchor or anchor.group(1) != "Text":
            continue
        out.append(Finding(path, line, "fixed-font",
                           f"{m.group(1)}pt display text is frozen against Dynamic "
                           "Type; use AppFont.scaled(_:relativeTo: .largeTitle)",
                           "error"))
    return out


def rule_glow(path, source, code) -> list[Finding]:
    """A coloured shadow behind a *glyph* is a halo — the neon look the
    craft rules exist to prevent.

    A coloured shadow under a *filled shape* is something else entirely:
    tinted elevation, which is how the accent medallions across the app read
    as floating. That idiom is used identically in a dozen places, so it's a
    system, not an accident, and the rule doesn't touch it.
    """
    out = []

    # `AppShadow.accentGlow` is a coloured glow by construction — accent at
    # 30%, radius 12. The old pattern only matched literal `.shadow(color:)`
    # and so was blind to every site that used the token, which is where the
    # glows actually live.
    for m in re.finditer(r"\.appShadow\(\s*AppShadow\.accentGlow\s*\)", code):
        out.append(Finding(path, line_of(code, m.start()), "glow",
                           "AppShadow.accentGlow is an accent halo; emphasis should "
                           "come from size, weight and contrast", "warning"))

    # Third form, and the one that hid longest: a blurred coloured disc
    # stacked behind a medallion. It is a halo built out of a shape rather
    # than a shadow, so neither of the patterns above could see it.
    if path.name not in FIXED_CANVAS_FILES:
        for m in re.finditer(r"\.blur\(radius:\s*(\d+)", code):
            if int(m.group(1)) < 12:
                continue
            before = code[max(0, m.start() - 260):m.start()]
            if not re.search(r"\.fill\(\s*(?:AppColor\.accent|accent|color|tint)", before):
                continue
            out.append(Finding(path, line_of(code, m.start()), "glow",
                               f"a blurred coloured disc at radius {m.group(1)} behind a "
                               "glyph is a halo built from a shape; emphasis comes from "
                               "size, weight and contrast", "warning"))

    for m in re.finditer(r"\.shadow\(\s*color:\s*([^,]+),[^)]*radius:\s*(\d+(?:\.\d+)?)", code):
        colour, radius = m.group(1).strip(), float(m.group(2))
        if re.search(r"\.black|\.clear|Color\.black|AppShadow", colour):
            continue
        if radius < 10:
            continue
        # What is the shadow attached to? Walk back to the nearest construct.
        # A stroked ring counts: a halo around an arc is the neon look this
        # rule exists for, and treating "not a fill, not a glyph" as "skip"
        # is what let nine accent glows sit under a clean report.
        before = code[max(0, m.start() - 500):m.start()]
        anchor = None
        for kind, pattern in (("shape", r"\.fill\(|\.background\s*\{|Image\(uiImage:|Image\(\""),
                              ("glyph", r"\bText\(|Image\(systemName:"),
                              ("stroke", r"\.stroke\(|\.strokeBorder\(|\.trim\(")):
            found = list(re.finditer(pattern, before))
            if found and (anchor is None or found[-1].start() > anchor[1]):
                anchor = (kind, found[-1].start())
        # A coloured shadow under a *filled* shape is tinted elevation, which
        # is a deliberate system here. Everything else is a halo.
        if anchor is None or anchor[0] == "shape":
            continue
        out.append(Finding(path, line_of(code, m.start()), "glow",
                           f"coloured shadow at radius {radius:g} behind a "
                           f"{anchor[0]} is a halo; contrast should come from the "
                           "ink, not a glow", "warning"))
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


def rule_placeholder_as_label(path, source, code) -> list[Finding]:
    """R5, second clause — a placeholder is not a label.

    SwiftUI uses a `TextField`'s first argument as its accessibility label,
    which is usually fine. It stops being fine when that argument is a bare
    number or a unit: six numeric fields in the nutrition and workout sheets
    announced themselves to VoiceOver as "0, text field", with the actual
    name sitting beside them in a separate `Text` the field never inherits.
    """
    out = []
    lines = code.split("\n")
    uninformative = re.compile(r'^"(\s*|0|0\.0|\d+|kg|lb|reps|g|mcg|mg|oz|ml)"$', re.I)
    for i, line in enumerate(lines):
        m = re.search(r'\b(?:TextField|SecureField)\(\s*("(?:[^"\\]|\\.)*")', line)
        if not m or not uninformative.match(m.group(1)):
            continue
        if "accessibilityLabel" in "\n".join(lines[i:i + 30]):
            continue
        out.append(Finding(path, i + 1, "placeholder-as-label",
                           f"{m.group(1)} is the only thing VoiceOver reads for this "
                           "field; add .accessibilityLabel", "error"))
    return out


def rule_unnamed_motion(path, source, code) -> list[Finding]:
    """R3, second clause — "explicit durations and easings".

    The first clause (an untargeted `.animation`) is `rule_untargeted_animation`.
    This is the other half: `withAnimation { }` with no argument takes
    SwiftUI's default, which is the same "author didn't decide what should
    move, or how fast" that `transition: all` signals in CSS. `AppAnimation`
    exists to name the motion; nine sites were bypassing it.
    """
    if path.name == "AnimationConstants.swift":
        return []
    out = []
    pattern = (r"withAnimation\s*\{|withAnimation\(\s*\)|"
               r"\.animation\(\s*\.(?:default|easeInOut|easeOut|easeIn)\s*[,)]|"
               r"\.animation\(\s*\.spring\(\s*\)")
    for m in re.finditer(pattern, code):
        out.append(Finding(path, line_of(code, m.start()), "unnamed-motion",
                           "animation with no explicit duration or easing; use an "
                           "AppAnimation constant so the motion is named", "error"))
    return out


def rule_placeholder_copy(path, source, code) -> list[Finding]:
    out = []
    for m in PLACEHOLDER_COPY.finditer(code):
        out.append(Finding(path, line_of(code, m.start()), "placeholder-copy",
                           f"placeholder string ships to users: {m.group(0)[:50]}", "error"))
    return out


def rule_hit_target(path, source, code) -> list[Finding]:
    """A control smaller than 44pt is hard to hit and fails an audit.

    The subtlety is *what* the frame belongs to. A 28pt icon tile inside a
    full-width row button is not a 28pt target — the row is the target, and
    flagging it would bury the handful of genuinely small controls. So the
    rule only fires when the flagged frame sizes the button's entire label:
    no stack, no Spacer, no infinite width anywhere in it.
    """
    out = []
    lines = code.splitlines()
    for m in re.finditer(r"\.frame\(width:\s*(\d+),\s*height:\s*(\d+)\)", code):
        w, h = int(m.group(1)), int(m.group(2))
        if min(w, h) >= 44:
            continue

        # Find the enclosing Button, and confirm the frame is actually inside
        # its label — the nearest preceding `Button` is often a context-menu
        # action or a sibling row, and a plain badge is not a tap target.
        head = code[:m.start()]
        bi = max(head.rfind("Button {"), head.rfind("Button("), head.rfind("onTapGesture"))
        if bi < 0 or m.start() - bi > 1200:
            continue
        label = code[bi:m.start()]
        if label.count("{") - label.count("}") < 1:
            continue
        if re.search(r"\b(?:H|V|Z)?Stack\b|Spacer\(\)|maxWidth:\s*\.infinity", label):
            continue

        # An explicit larger frame or contentShape afterwards already fixes it.
        after = code[m.end():m.end() + 900]
        if re.search(r"minimumHitArea|minimumHitTarget|\.frame\(width:\s*(?:4[4-9]|[5-9]\d)", after):
            continue
        out.append(Finding(path, line_of(code, m.start()), "hit-target",
                           f"{w}×{h} tap target is under Spacing.minimumHitTarget (44)",
                           "warning"))
    return out


def rule_off_grid_spacing(path, source, code) -> list[Finding]:
    """Padding and stack spacing come from Spacing so the rhythm is one
    decision, not two hundred."""
    if path.name in FIXED_CANVAS_FILES:
        return []
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
            # Sub-8pt values are optical, not structural: a badge with 8pt of
            # vertical padding is a tall badge. The grid governs layout
            # rhythm — stack spacing and card/screen padding — so the rule
            # starts where that rhythm does.
            if value < 8:
                continue
            out.append(Finding(path, line_of(code, m.start()), "off-grid",
                               f"{value}pt is off the 8-point grid; use a Spacing token",
                               "warning"))
    return out


def rule_low_contrast_ink(path, source, code) -> list[Finding]:
    """Text at under 50% opacity fails WCAG AA at small sizes, and the ramp
    already encodes the intended hierarchy — fading a token is how you end up
    with five greys that were each meant to be `textTertiary`.

    Only fires on *text*. A dashed chart reference line and a decorative
    particle are supposed to be faint; flagging those would make the rule
    noise, and noisy rules get muted.
    """
    out = []
    for m in re.finditer(r"\.foregroundStyle\(\s*AppColor\.\w+\.opacity\(0?\.([0-4]\d?)\)", code):
        before = code[max(0, m.start() - 300):m.start()]
        anchor = None
        for kind, pattern in (("other", r"RuleMark|LineMark|AreaMark|BarMark|Image\(|Circle\(|Capsule\(|Rectangle\("),
                              ("text", r"\bText\(")):
            found = list(re.finditer(pattern, before))
            if found and (anchor is None or found[-1].start() > anchor[1]):
                anchor = (kind, found[-1].start())
        if anchor is None or anchor[0] != "text":
            continue
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


def rule_raw_material(path, source, code) -> list[Finding]:
    """A hand-rolled `.fill(.ultraThinMaterial)` is the legacy glass recipe
    written out inline, and on iOS 26 it renders the iOS 15 material instead
    of Liquid Glass — the surface silently opts out of the design system.

    `.presentationBackground(.thinMaterial)` is exempt: that is the documented
    sheet API, not a bypass, and there is no glass equivalent for it.
    """
    if path.name == "GlassEffectCompat.swift":
        return []
    out = []
    for m in re.finditer(r"\.(?:fill|background)\(\s*\.(\w*[Mm]aterial)\s*\)", code):
        before = code[max(0, m.start() - 40):m.start()]
        if "presentationBackground" in before:
            continue
        out.append(Finding(path, line_of(code, m.start()), "raw-material",
                           f".{m.group(1)} bypasses the glass system; use "
                           "glassSurface / glassControl / glassSurfaceCapsule",
                           "error"))
    return out


SCROLL_CONTAINERS = re.compile(r"\b(?:ScrollView|List|TabView|Form)\b")

# What makes a floating footer a *defect* rather than decoration: it holds
# something the user is meant to reach.
INTERACTIVE = re.compile(r"\b(?:Button|Toggle|TextField|Picker|Stepper|Slider|Menu|NavigationLink)\b"
                         r"|\.onTapGesture\b")


def rule_floating_footer(path, source, code) -> list[Finding]:
    """`VStack { Spacer(); footer }` layered over a scroll view in a ZStack is
    a floating overlay: it reserves **zero** layout space, so the scrolling
    content ends at its own natural bottom and its last row stops permanently
    behind the footer.

    This shipped twice. In onboarding it parked the Gender row under the CTA
    with no way to scroll it clear — the field could not be reached at all.
    On the paywall the tier cards ran under the button. Neither was visible to
    any other rule, because every colour, font and spacing token was correct.

    Use `.pinnedFooter { … }`, which reserves the space via `safeAreaInset`
    and lands an opaque backdrop whose fade ends above the button.

    Scoped to footers that hold a control. A decorative overlay — the date
    chip floating over the photo pager — is the legitimate use of this shape
    and cannot strand anything, so firing on it would only teach people to
    ignore the rule.
    """
    out = []
    for m in re.finditer(r"\bVStack\b[^{\n]*\{\s*Spacer\(\)", code):
        brace, block = enclosing_block(code, m.start())
        if brace < 0:
            continue
        # Only the ZStack-overlay form is the bug. A `VStack { Spacer() }`
        # that *is* the layout — pushing its own content down — is fine, and
        # so is one inside a ScrollView, where it sizes to the content.
        owner = code[max(0, brace - 60):brace]
        if not re.search(r"\bZStack\b[^{]*$", owner):
            continue
        if not SCROLL_CONTAINERS.search(block):
            continue
        _, floating = enclosing_block(code, m.end())
        if not INTERACTIVE.search(floating):
            continue
        out.append(Finding(path, line_of(code, m.start()), "floating-footer",
                           "a VStack opening with Spacer() over a scroll view in a ZStack "
                           "floats without reserving space; use .pinnedFooter { }", "error"))
    return out


def rule_uncombined_row(path, source, code) -> list[Finding]:
    """A repeated list row that mixes an icon with text is one piece of
    information, but VoiceOver reads it as several — an icon stop, then each
    Text, in visual order.

    Only fires on *rows*: a view whose body is a top-level `HStack`. A large
    card is genuinely several things and combining it produces one unreadable
    sentence, so the rule leaves those alone.
    """
    out = []
    for m in re.finditer(r"struct (\w*(?:Row|Chip|Pill|Item))\b[^{]*:\s*View\s*\{", code):
        start = m.end() - 1
        depth, end = 0, start
        for i in range(start, len(code)):
            if code[i] == "{":
                depth += 1
            elif code[i] == "}":
                depth -= 1
                if depth == 0:
                    end = i
                    break
        block = code[start:end]
        if "accessibility" in block:
            continue
        if "Image(systemName:" not in block or "Text(" not in block:
            continue
        if not re.search(r"var body:[^{]*\{\s*HStack", block):
            continue
        out.append(Finding(path, line_of(code, m.start()), "uncombined-row",
                           f"{m.group(1)} reads as several VoiceOver stops; combine its "
                           "children and hide the decorative glyph", "warning"))
    return out



def rule_type_scale(path, source, code) -> list[Finding]:
    """R9 — hierarchy from weight and colour before size, on a small scale.

    The app carried thirty distinct point sizes, thirteen of them inside a
    12pt band. Below the display range there are six steps and nothing
    between them; see `AppFont.Scale`.
    """
    if path.name == "Typography.swift":
        return []
    out = []
    for m in re.finditer(r"(?:AppFont\.scaled\(|\.system\(size:\s*)(\d+(?:\.\d+)?)", code):
        v = float(m.group(1))
        if v > 24 or v in TYPE_SCALE:
            continue
        out.append(Finding(path, line_of(code, m.start()), "type-scale",
                           f"{v:g}pt is off the six-step body scale "
                           f"({', '.join(f'{s:g}' for s in sorted(TYPE_SCALE))})", "error"))
    return out


def rule_pure_neutral(path, source, code) -> list[Finding]:
    """R7 — no pure black on pure white.

    `#FFF`/`#000` read as unfinished; tuned near-neutrals are one of the
    cheapest things that separates a designed surface from a default one.
    """
    if path.name != "ColorTheme.swift":
        return []
    out = []
    for m in re.finditer(r"0x(?:FFFFFF|000000)\b", code):
        out.append(Finding(path, line_of(code, m.start()), "pure-neutral",
                           f"{m.group(0)} is a pure neutral; tune it a step off "
                           "(e.g. 0xFCFCFD / 0x0B0B0E)", "warning"))
    return out


def rule_motion(path, source, code) -> list[Finding]:
    """R12 — UI motion is 120–250ms and doesn't loop for decoration.

    Ambient background drift and explicit loading indicators are the
    exceptions, so only *short* repeating animations are flagged: those are
    attention-grabbing, not ambient.
    """
    # The shimmer *is* the loading indicator; looping is the whole point.
    if path.name == "ShimmerModifier.swift":
        return []
    out = []
    for m in re.finditer(r"repeatForever", code):
        before = code[max(0, m.start() - 260):m.start()]
        durations = [float(d) for d in re.findall(r"duration:\s*(\d*\.?\d+)", before)]
        if durations and durations[-1] >= 1.2:
            continue          # ambient drift or a deliberate breathing pulse
        out.append(Finding(path, line_of(code, m.start()), "motion",
                           "a short looping animation reads as decoration; loop only "
                           "ambient or loading motion", "warning"))
    return out


def rule_forced_color_scheme(path, source, code) -> list[Finding]:
    """R13 — shipping views don't hard-code a colour scheme.

    A literal `.preferredColorScheme(.dark)` on a sheet or editor overrides
    the user's appearance choice for that surface only, so picking Light
    turns the tabs light and snaps every sheet back to dark. The scheme is
    the app's to set once, from `ThemeManager.displayMode`. Previews are
    blanked before rules run, so demo scaffolding is unaffected.
    """
    out = []
    for m in re.finditer(r"\.preferredColorScheme\(\s*\.(dark|light)\b", code):
        out.append(Finding(path, line_of(code, m.start()), "forced-color-scheme",
                           f"hard-coded .{m.group(1)} scheme overrides the user's "
                           "appearance setting; drive it from "
                           "ThemeManager.displayMode.preferredScheme", "error"))
    return out


def rule_unguarded_loop(path, source, code) -> list[Finding]:
    """R12 — a looping animation must stop under Reduce Motion.

    WCAG 2.2.2 is about motion that never ends: a view that starts a
    `repeatForever` in `onAppear` and never checks
    `accessibilityReduceMotion` keeps moving for a user who asked the
    system to stop moving things. Declaring the environment value is
    enough to satisfy this — the guard itself is a judgement the rule
    can't make, but the file that never reads it definitely isn't
    making it.
    """
    if "repeatForever" not in code:
        return []
    if re.search(r"accessibilityReduceMotion|isReduceMotionEnabled", code):
        return []
    m = re.search(r"repeatForever", code)
    return [Finding(path, line_of(code, m.start()), "unguarded-loop",
                    "looping animation with no Reduce Motion check; gate it on "
                    "@Environment(\\.accessibilityReduceMotion)", "error")]


def rule_accent_gradient_fill(path, source, code) -> list[Finding]:
    """R1 + contrast — no accent gradient under `onAccent` ink.

    `accentPrimary` and `accentLight` are tuned as *ink on the background*,
    so in the dark scheme they are the brightest colours in the app. Filling
    a CTA with a gradient between them and printing near-white on top lands
    between 1.3:1 and 3.7:1 depending on the theme. `contrast-check` cannot
    see this because the fill is a gradient, not a token pair.

    Craft R1 independently rejects the same construct — a fade applied to
    buttons and pills alike is decoration standing in for a colour decision.
    `AppColor.accentFill` is the flat answer to both.
    """
    out = []
    for m in re.finditer(r"(?:Linear|Radial|Angular)Gradient", code):
        block = code[m.start():m.start() + 320]
        if not re.search(r"AppColor\.accent(?:Primary|Light)", block):
            continue
        before = code[max(0, m.start() - 500):m.start()]
        if not re.search(r"\.foregroundStyle\(\s*AppColor\.onAccent\s*\)", before):
            continue
        out.append(Finding(path, line_of(code, m.start()), "accent-gradient-fill",
                           "accent gradient under onAccent ink drops below 4:1 in the "
                           "dark scheme; fill with AppColor.accentFill", "error"))
    return out


RULES = [
    rule_forced_color_scheme,
    rule_accent_gradient_fill,
    rule_unguarded_loop,
    rule_raw_colour,
    rule_type_scale,
    rule_pure_neutral,
    rule_motion,
    rule_fixed_font,
    rule_glow,
    rule_untargeted_animation,
    rule_unnamed_motion,
    rule_placeholder_copy,
    rule_placeholder_as_label,
    rule_hit_target,
    rule_off_grid_spacing,
    rule_low_contrast_ink,
    rule_unlabelled_icon_button,
    rule_stacked_glass,
    rule_raw_material,
    rule_floating_footer,
    rule_uncombined_row,
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
            code = blank_previews(strip_comments(source))
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
