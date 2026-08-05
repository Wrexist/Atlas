#!/usr/bin/env python3
"""Report how much of the UI the string catalog actually covers.

Declaring a language is a promise, and the catalog is what keeps it. This
measures the gap between the two, because nothing else does: a missing key is
not a build error, it just silently renders the English source string to a
user who asked for Spanish.

The app briefly declared ten languages against 13% coverage — which would
have listed all ten on the App Store and handed those users a mostly-English
medical app. It ships English only now, and the check below fails the build
if a language is declared before the app is actually in it.

Counts only real user-facing sentences — capitalised, multi-word, no string
interpolation — since fragments and format strings are not separately
translatable keys.

    python3 scripts/check-localization.py [--min-coverage 80]
"""
from __future__ import annotations
import argparse, json, pathlib, re, sys

REPO = pathlib.Path(__file__).resolve().parent.parent
CATALOG = REPO / "Peptide" / "Resources" / "Localizable.xcstrings"
PROJECT = REPO / "project.yml"


def shipped_languages(catalog: dict) -> set[str]:
    """Languages the built binary will actually contain.

    Measured from the catalog, because that is what Xcode compiles into
    `.lproj` folders and those folders are what the App Store reads. A first
    attempt at this pinned `options.knownRegions` in project.yml instead —
    which is not an XcodeGen key at all, so it would have declared English
    while still shipping nine languages, and the check would have agreed with
    itself while being wrong.

    `CFBundleLocalizations` is unioned in so a stale declaration there shows
    up rather than sitting unnoticed next to a catalog that disagrees.
    """
    out = {loc for v in catalog.get("strings", {}).values()
           for loc in (v.get("localizations") or {})}
    m = re.search(r"^\s*CFBundleLocalizations:\s*\n((?:\s*#[^\n]*\n|\s*-\s*[\w-]+\s*\n)+)",
                  PROJECT.read_text(), re.MULTILINE)
    if m:
        out |= set(re.findall(r"-\s*([\w-]+)", m.group(1)))
    return out


def blank_previews(source: str) -> str:
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
        out = out[:m.start()] + re.sub(r"[^\n]", " ", source[m.start():i + 1]) + out[i + 1:]
    return out


def ui_sentences() -> set[str]:
    found: set[str] = set()
    for root in ("Peptide/Features", "Peptide/DesignSystem"):
        for p in (REPO / root).rglob("*.swift"):
            code = re.sub(r"//[^\n]*", "", blank_previews(p.read_text()))
            for m in re.finditer(r'\bText\(\s*"((?:[^"\\]|\\.){6,})"\s*\)', code):
                t = m.group(1)
                if "\\(" in t or "%" in t or not re.match(r"^[A-Z]", t) or " " not in t.strip():
                    continue
                found.add(t)
    return found


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-coverage", type=float, default=0.0,
                    help="fail below this %% of UI sentences present in the catalog")
    ap.add_argument("--min-coverage-per-language", type=float, default=80.0,
                    help="coverage %% required before a non-English language may "
                         "be declared in project.yml")
    args = ap.parse_args()

    catalog = json.loads(CATALOG.read_text())
    keys = set(catalog.get("strings", {}))
    sentences = ui_sentences()
    covered = sentences & keys
    pct = 100 * len(covered) / len(sentences) if sentences else 100.0

    print(f"  catalog keys:            {len(keys)}")
    print(f"  UI sentences in code:    {len(sentences)}")
    print(f"  covered by the catalog:  {len(covered)}  ({pct:.0f}%)")

    orphans = sorted(k for k in keys if k not in sentences and " " in k and re.match(r"^[A-Z]", k))
    langs: dict[str, int] = {}
    for v in catalog.get("strings", {}).values():
        for loc in (v.get("localizations") or {}):
            langs[loc] = langs.get(loc, 0) + 1
    if langs:
        worst = min(langs.values())
        print(f"  languages in catalog:    {len(langs)}  (min {worst}/{len(keys)} translated)")
    print(f"  catalog keys no longer in the UI: {len(orphans)}")

    shipped = shipped_languages(catalog)
    print(f"  languages the build ships: {len(shipped)}  ({', '.join(sorted(shipped))})")

    # A language is only worth shipping if the app is actually in it. The
    # withheld catalog is fully translated but covers 13% of the UI, so
    # shipping the other nine would have put them on the App Store listing
    # while handing those users a mostly-English app — dosing and safety
    # copy included.
    overreach = shipped - {"en", "Base"}
    if overreach and pct < args.min_coverage_per_language:
        print(f"\n{len(overreach)} non-English language(s) declared — "
              f"{', '.join(sorted(overreach))} — but only {pct:.0f}% of the UI is "
              f"in the catalog, below the {args.min_coverage_per_language:.0f}% "
              "needed to claim a localization.\n"
              "Either raise coverage, or move those localizations back out to "
              "localization/Localizable.translated.xcstrings and drop them from "
              "CFBundleLocalizations.")
        return 1

    if pct < args.min_coverage:
        print(f"\ncoverage {pct:.0f}% is below the required {args.min_coverage:.0f}%")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
