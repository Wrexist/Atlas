#!/usr/bin/env python3
"""Tests for the two checkers in this directory.

These exist because of a real failure on this branch. `rule_glow` matched
only literal `.shadow(color:)`, so it could not see `AppShadow.accentGlow` —
the token every ring glow in the app actually uses — and it skipped any glow
anchored to a `.stroke()`. It reported **zero** while nine accent glows were
in the codebase, and that clean report was written into the audit as
evidence the rule was enforced.

A checker that is silently blind is worse than no checker: it converts an
unexamined area into a false assurance. So every rule gets a positive case
that must fire and a negative case that must not.

    python3 scripts/test_design_lint.py
"""

from __future__ import annotations

import importlib.util
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent


def _load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    mod = importlib.util.module_from_spec(spec)
    # @dataclass resolves annotations via sys.modules[cls.__module__]; without
    # this the import fails with an opaque AttributeError on None.
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


lint = _load("design_lint", "design-lint.py")
contrast = _load("contrast_check", "contrast-check.py")

# (rule, filename it must be judged as, source that MUST fire,
#                                       source that MUST NOT)
CASES = [
    ("rule_forced_color_scheme", "Foo.swift",
     'var body: some View { Text("hi").preferredColorScheme(.dark) }',
     'var body: some View { Text("hi").preferredColorScheme(theme.displayMode.preferredScheme) }'),

    ("rule_accent_gradient_fill", "Foo.swift",
     '.foregroundStyle(AppColor.onAccent)\n.background { Capsule().fill(LinearGradient(colors: [AppColor.accentPrimary, AppColor.accentLight], startPoint: .leading, endPoint: .trailing)) }',
     '.foregroundStyle(AppColor.onAccent)\n.background { Capsule().fill(AppColor.accentFill) }'),

    ("rule_unguarded_loop", "Foo.swift",
     '.onAppear { withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { x = true } }',
     '@Environment(\\.accessibilityReduceMotion) private var reduceMotion\n.onAppear { guard !reduceMotion else { return }\nwithAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { x = true } }'),

    ("rule_raw_colour", "Foo.swift",
     '.foregroundStyle(Color(hex: 0xFF0000))',
     '.foregroundStyle(AppColor.textPrimary)'),

    ("rule_fixed_font", "Foo.swift",
     'Text("a").font(.system(size: 13, weight: .bold))',
     'Text("a").font(AppFont.scaled(13, weight: .bold))'),

    ("rule_fixed_font", "Foo.swift",
     'Text("a").font(.system(size: 44, weight: .heavy))',
     'Text("a").font(AppFont.scaled(44, weight: .heavy, relativeTo: .largeTitle))'),

    ("rule_glow", "Foo.swift",
     'MetricRing().appShadow(AppShadow.accentGlow)',
     'MetricRing().appShadow(AppShadow.glassElevated)'),

    ("rule_glow", "Foo.swift",
     'Circle().trim(from: 0, to: p).stroke(tint, lineWidth: 8)\n.shadow(color: AppColor.accentPrimary, radius: 16, y: 4)',
     'Circle().fill(tint)\n.shadow(color: AppColor.accentPrimary, radius: 16, y: 4)'),

    ("rule_glow", "Foo.swift",
     'ZStack {\n  Circle().fill(accent.opacity(0.2)).frame(width: 84, height: 84).blur(radius: 18)\n  Image(systemName: "star")\n}',
     'ZStack {\n  Circle().fill(accent).frame(width: 84, height: 84)\n  Image(systemName: "star")\n}'),

    ("rule_placeholder_copy", "Foo.swift",
     'Text("Coming soon")',
     'Text("Log your first workout")'),

    ("rule_untargeted_animation", "Foo.swift",
     'Text("a").animation(.easeOut(duration: 0.2))',
     'Text("a").animation(.easeOut(duration: 0.2), value: count)'),

    ("rule_pure_neutral", "ColorTheme.swift",
     'static let ink = Color(light: 0x000000, dark: 0xFFFFFF)',
     'static let ink = Color(light: 0x111114, dark: 0xF7F7FA)'),
]


def run() -> int:
    failures: list[str] = []

    for rule_name, filename, positive, negative in CASES:
        rule = getattr(lint, rule_name)
        for label, source, want_hit in (("positive", positive, True),
                                        ("negative", negative, False)):
            path = lint.FEATURES / filename
            code = lint.blank_previews(lint.strip_comments(source))
            hits = rule(path, source, code)
            if bool(hits) != want_hit:
                failures.append(
                    f"{rule_name} [{label}] expected "
                    f"{'a finding' if want_hit else 'no finding'}, got {len(hits)}")

    # Preview scaffolding must never be judged as shipping UI.
    preview = '#Preview {\n    Text("x").preferredColorScheme(.dark)\n}'
    code = lint.blank_previews(lint.strip_comments(preview))
    if lint.rule_forced_color_scheme(lint.FEATURES / "Foo.swift", preview, code):
        failures.append("blank_previews: a #Preview body was judged as shipping code")

    # Contrast maths, against values checkable by hand.
    for fg, bg, expected in ((0xFFFFFF, 0x000000, 21.0),
                             (0x000000, 0x000000, 1.0),
                             (0x767676, 0xFFFFFF, 4.54)):
        got = contrast.contrast(fg, bg)
        if abs(got - expected) > 0.02:
            failures.append(f"contrast({fg:#08x},{bg:#08x}) = {got:.2f}, expected {expected}")

    # The real tokens must parse — a silent parse failure would report zero pairs.
    tokens = contrast.parse_tokens(contrast.COLOR_THEME)
    ramps = contrast.parse_ramps(contrast.APP_THEME)
    if len(tokens) < 20:
        failures.append(f"parse_tokens found only {len(tokens)} tokens")
    if len(ramps) < 5:
        failures.append(f"parse_ramps found only {len(ramps)} ramps")

    for f in failures:
        print(f"FAIL  {f}")
    total = len(CASES) * 2 + 1 + 3 + 2
    print(f"\n{total - len(failures)}/{total} passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(run())
