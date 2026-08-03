#!/usr/bin/env python3
"""Check the numbers in user-facing copy against their source of truth.

This exists because of a real one. The App Store screen for the Atlas Score
claimed "LEVEL 14 · GOLD" and "1,240 pts to Level 15 · Diamond". The app's
own `MomentumEngine.Tier.forLevel` puts level 14 in Silver and Diamond at
level 70 — so the screenshot advertising the progression system described a
progression the app does not have.

Nothing caught it. Contrast maths passed, the lint rules passed, the layout
checks passed, the console was clean. A claim in copy is only wrong relative
to something else, and no checker was comparing the two.

These are the claims whose source is a file that changes: add an exercise
and "870+ exercises" is silently wrong. Assertions that are stable by
construction (screen dimensions, "18+") are not worth pinning.

    python3 scripts/check-copy-claims.py
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent


def dataset_count(name: str, key: str | None = None) -> int:
    data = json.loads((REPO / "Peptide" / "Resources" / name).read_text())
    if isinstance(data, list):
        return len(data)
    if key and key in data:
        return len(data[key])
    return len(next((v for v in data.values() if isinstance(v, list)), []))


def enum_case_count(path: str, enum: str, stop_at: str | None = None) -> int:
    source = (REPO / path).read_text()
    m = re.search(rf"enum {enum}[^{{]*\{{(.*?)\n\}}", source, re.S)
    if not m:
        raise SystemExit(f"could not find enum {enum} in {path}")
    body = m.group(1).split(stop_at)[0] if stop_at else m.group(1)
    return sum(
        len([x for x in c.split(",") if x.strip()])
        for c in re.findall(r"^\s*case\s+([\w, ]+)", body, re.M)
    )


def copy_says(pattern: str) -> list[tuple[str, str]]:
    """Every user-facing string matching `pattern`, with its file."""
    found = []
    for root in ("Peptide/Features", "Peptide/DesignSystem"):
        for p in sorted((REPO / root).rglob("*.swift")):
            for m in re.finditer(pattern, p.read_text()):
                found.append((str(p.relative_to(REPO)), m.group(0)))
    return found


def marketing_says(pattern: str) -> list[tuple[str, str]]:
    """Same, for the App Store screens — where the tier error actually was."""
    found = []
    base = REPO / "marketing" / "app-store"
    if not base.exists():
        return found
    for d in ("screens", "screens-watch", "screens-watch-frames"):
        for p in sorted((base / d).glob("*.html")):
            for m in re.finditer(pattern, p.read_text()):
                found.append((str(p.relative_to(REPO)), m.group(0)))
    return found


def tier_for_level(level: int) -> str:
    """Mirror of MomentumEngine.Tier.forLevel, parsed from the source so it
    cannot drift from it."""
    source = (REPO / "Peptide" / "Services" / "MomentumEngine.swift").read_text()
    m = re.search(r"static func forLevel[^{]*\{(.*?)\n        \}", source, re.S)
    if not m:
        raise SystemExit("could not parse Tier.forLevel")
    for line in m.group(1).splitlines():
        b = re.search(r"case\s+(\d*)\.\.<(\d+):\s*return\s+\.(\w+)", line)
        if b:
            lo = int(b.group(1)) if b.group(1) else 0
            if lo <= level < int(b.group(2)):
                return b.group(3)
        d = re.search(r"default:\s*return\s+\.(\w+)", line)
        if d:
            fallback = d.group(1)
    return fallback


def main() -> int:
    failures: list[str] = []

    def check(label: str, claimed: int, actual: int, rule: str, sites: list) -> None:
        ok = {"at_least": claimed <= actual, "exact": claimed == actual}[rule]
        status = "ok  " if ok else "FAIL"
        print(f"  {status} {label}: copy says {claimed}, source has {actual}")
        if not ok:
            for f, t in sites:
                print(f"         {f}  {t!r}")
            failures.append(label)

    # "870+ exercises"
    sites = copy_says(r'"[^"]*?(\d{3})\+ exercises[^"]*"')
    if sites:
        claimed = int(re.search(r"(\d{3})\+", sites[0][1]).group(1))
        check("exercises", claimed, dataset_count("exercises.json"), "at_least", sites)

    # "208 researched compounds"
    sites = copy_says(r'"[^"]*?(\d{3}) (?:researched )?(?:compounds|peptides)[^"]*"')
    if sites:
        claimed = int(re.search(r"(\d{3})", sites[0][1]).group(1))
        check("compounds", claimed, dataset_count("peptides.json"), "exact", sites)

    # "27 panels across 7 categories"
    sites = copy_says(r'"(\d{2}) panels across (\d) categories"')
    if sites:
        m = re.search(r"(\d{2}) panels across (\d) categories", sites[0][1])
        panels = enum_case_count("Peptide/Models/LabValue.swift", "LabPanel", "enum Category")
        cats = enum_case_count("Peptide/Models/LabValue.swift", "Category")
        check("lab panels", int(m.group(1)), panels, "exact", sites)
        check("lab categories", int(m.group(2)), cats, "exact", sites)

    # Marketing: "208 researched compounds"
    sites = marketing_says(r"(\d{3}) researched compounds")
    if sites:
        claimed = int(re.search(r"(\d{3})", sites[0][1]).group(1))
        check("compounds (marketing)", claimed,
              dataset_count("peptides.json"), "exact", sites)

    # Marketing: the level/tier pairing that was wrong.
    for file, text in marketing_says(r"LEVEL[\s\S]{0,400}?>(\d{1,3})<[\s\S]{0,200}?>([A-Z]{4,9})<"):
        m = re.search(r">(\d{1,3})<[\s\S]{0,200}?>([A-Z]{4,9})<", text)
        level, shown = int(m.group(1)), m.group(2).lower()
        real = tier_for_level(level)
        ok = shown == real
        print(f"  {'ok  ' if ok else 'FAIL'} tier: {file.split('/')[-1]} shows level "
              f"{level} as {shown.upper()}, engine says {real.upper()}")
        if not ok:
            failures.append(f"tier in {file}")

    if failures:
        print(f"\n{len(failures)} copy claim(s) no longer match the source")
        return 1
    print("\nall copy claims match their source")
    return 0


if __name__ == "__main__":
    sys.exit(main())
