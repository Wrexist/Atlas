#!/usr/bin/env python3
"""Report how much of the UI the string catalogs actually cover.

Declaring a language is a promise, and the catalog is what keeps it. This
measures the gap between the two, because nothing else does: a missing key is
not a build error, it just silently renders the English source string to a
user who asked for Spanish.

The app briefly declared ten languages against 13% coverage — which would
have listed all ten on the App Store and handed those users a mostly-English
medical app. The check below fails the build if a language is declared before
the app is actually in it: every shipped language must translate at least
`--min-coverage-per-language` of the UI sentences, not merely have the keys.

It also fails on a translation whose format specifiers don't match its key
(`%lld` turned into `%@`, an argument dropped). That isn't a build error
either — it crashes or prints garbage at runtime, in that language only.

Counts only real user-facing sentences — capitalised, multi-word, no string
interpolation — since fragments and format strings are not separately
translatable keys.

    python3 scripts/check-localization.py [--min-coverage 80]
"""
from __future__ import annotations
import argparse, json, pathlib, re, sys

REPO = pathlib.Path(__file__).resolve().parent.parent
CATALOG = REPO / "Peptide" / "Resources" / "Localizable.xcstrings"
TARGET_CATALOGS = [CATALOG] + [REPO / t / "Localizable.xcstrings"
                               for t in ("PeptideWidgets", "PeptideWatch", "PeptideWatchWidgets")]
PROJECT = REPO / "project.yml"
SPEC = re.compile(r"%#@(?P<sub>\w+)@|%(?:(?P<pos>\d+)\$)?"
                  r"(?P<conv>[-+#0]*\d*(?:\.\d+)?(?:ll|l|hh|h|q|z|t|j)?[@dDuUxXoOfFeEgGcCsSaAp])|%%|%")


def shipped_languages(catalogs: list[dict]) -> set[str]:
    """Languages the built binaries will actually contain.

    Measured from the catalogs, because that is what Xcode compiles into
    `.lproj` folders and those folders are what the App Store reads. A first
    attempt at this pinned `options.knownRegions` in project.yml instead —
    which is not an XcodeGen key at all, so it would have declared English
    while still shipping nine languages, and the check would have agreed with
    itself while being wrong.

    `CFBundleLocalizations` is unioned in so a stale declaration there shows
    up rather than sitting unnoticed next to a catalog that disagrees.
    """
    out = {loc for c in catalogs for v in c.get("strings", {}).values()
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


def unescape(literal: str) -> str:
    """A Swift literal's text as the catalog stores it: `\\"` is `"`, `\\n` a newline."""
    return re.sub(r'\\(["\\nt])', lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), literal)


def ui_sentences() -> set[str]:
    found: set[str] = set()
    for root in ("Peptide/Features", "Peptide/DesignSystem"):
        for p in (REPO / root).rglob("*.swift"):
            code = re.sub(r"//[^\n]*", "", blank_previews(p.read_text()))
            for m in re.finditer(r'\bText\(\s*"((?:[^"\\]|\\.){6,})"\s*\)', code):
                t = m.group(1)
                if "\\(" in t or "%" in t or not re.match(r"^[A-Z]", t) or " " not in t.strip():
                    continue
                found.add(unescape(t))
    return found


def specifiers(s: str, subs: dict | None = None) -> list[tuple[int, str]]:
    """(argument position, conversion) for each specifier; raises on a stray %."""
    out, n = [], 0
    for m in SPEC.finditer(s):
        if m.group(0) == "%%":
            continue
        if m.group(0) == "%":
            raise ValueError("stray %")
        n += 1
        if m.group("sub"):
            sub = (subs or {}).get(m.group("sub"))
            if sub is None:
                raise ValueError(f"unknown substitution {m.group('sub')}")
            out.append((sub["argNum"], "%" + sub["formatSpecifier"]))
        else:
            out.append((int(m.group("pos")) if m.group("pos") else n, "%" + m.group("conv")))
    return sorted(out)


def rendered_forms(loc: dict):
    """Every string one localization can render, with its substitutions."""
    if "stringUnit" in loc:
        yield loc["stringUnit"]["value"], loc.get("substitutions")
    for kind in loc.get("variations", {}).values():
        for form in kind.values():
            yield from rendered_forms(form)


def specifier_mismatches(name: str, catalog: dict) -> list[str]:
    errors = []
    for key, entry in catalog.get("strings", {}).items():
        try:
            want = specifiers(key)
        except ValueError:
            continue  # a plain literal with a bare % — never formatted
        if not want:
            continue
        for lang, loc in (entry.get("localizations") or {}).items():
            for value, subs in rendered_forms(loc):
                try:
                    got = specifiers(value, subs)
                except ValueError as e:
                    got = str(e)
                if got != want:
                    errors.append(f"  {name} [{lang}] {key!r} → {value!r}")
    return errors


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-coverage", type=float, default=0.0,
                    help="fail below this %% of UI sentences present in the catalog")
    ap.add_argument("--min-coverage-per-language", type=float, default=80.0,
                    help="share of UI sentences a non-English language must translate "
                         "before it may ship")
    args = ap.parse_args()

    catalogs = {p.relative_to(REPO).as_posix(): json.loads(p.read_text())
                for p in TARGET_CATALOGS if p.exists()}
    catalog = catalogs[CATALOG.relative_to(REPO).as_posix()]
    strings = catalog.get("strings", {})
    keys = set(strings)
    sentences = ui_sentences()
    covered = sentences & keys
    pct = 100 * len(covered) / len(sentences) if sentences else 100.0

    print(f"  catalog keys:            {len(keys)}")
    print(f"  UI sentences in code:    {len(sentences)}")
    print(f"  covered by the catalog:  {len(covered)}  ({pct:.0f}%)")

    orphans = sorted(k for k in keys if k not in sentences and " " in k and re.match(r"^[A-Z]", k))
    print(f"  catalog keys no longer in the UI: {len(orphans)}")

    shipped = shipped_languages(list(catalogs.values()))
    print(f"  languages the build ships: {len(shipped)}  ({', '.join(sorted(shipped))})")

    # A language is only worth shipping if the app is actually in it — its
    # own translations, not the keys. The withheld catalog is fully
    # translated but covers 13% of the UI, so shipping those nine would have
    # put them on the App Store listing while handing those users a
    # mostly-English app, dosing and safety copy included.
    failed = False
    for lang in sorted(shipped - {"en", "Base"}):
        done = {s for s in covered if lang in (strings[s].get("localizations") or {})}
        lang_pct = 100 * len(done) / len(sentences) if sentences else 100.0
        print(f"  {lang}: {len(done)}/{len(sentences)} UI sentences translated ({lang_pct:.0f}%), "
              f"{sum(1 for v in strings.values() if lang in (v.get('localizations') or {}))}"
              f"/{len(keys)} keys")
        if lang_pct < args.min_coverage_per_language:
            print(f"\n{lang} is declared but only {lang_pct:.0f}% of the UI is translated, "
                  f"below the {args.min_coverage_per_language:.0f}% needed to claim a "
                  "localization.\nEither translate the rest, or move it back out to "
                  "localization/Localizable.translated.xcstrings and drop it from "
                  "CFBundleLocalizations.")
            failed = True

    mismatches = [e for name, c in catalogs.items() for e in specifier_mismatches(name, c)]
    if mismatches:
        print(f"\n{len(mismatches)} translation(s) don't match their key's format specifiers:")
        print("\n".join(mismatches))
        failed = True

    if pct < args.min_coverage:
        print(f"\ncoverage {pct:.0f}% is below the required {args.min_coverage:.0f}%")
        failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
