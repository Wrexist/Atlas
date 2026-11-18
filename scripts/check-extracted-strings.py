#!/usr/bin/env python3
"""Fail when a string the compiler extracted has no translation.

`check-localization.py` finds catalog lookups by reading Swift source with
regexes. That is fast and runs without Xcode, but it only sees the call forms
it knows and it skips interpolated keys (`"\\(name) lock"`, `"Added \\(n)"`),
so it can report full coverage while new English strings ship.

The compiler has no such blind spot. With `SWIFT_EMIT_LOC_STRINGS=YES` every
build writes one `.stringsdata` file per Swift file, listing each key that
code will look up at runtime, interpolations already turned into `%@` /
`%lld`. This reads those files from a build's DerivedData and requires every
key to exist in its target's catalog with a value in every language that
catalog ships. Keys without a letter (`%lld`, `•`) have nothing to translate.

    python3 scripts/check-extracted-strings.py ~/Library/Developer/Xcode/DerivedData
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
TARGET_CATALOGS = {
    "Peptide": REPO / "Peptide" / "Resources" / "Localizable.xcstrings",
    "PeptideWidgets": REPO / "PeptideWidgets" / "Localizable.xcstrings",
    "PeptideWatch": REPO / "PeptideWatch" / "Localizable.xcstrings",
    "PeptideWatchWidgets": REPO / "PeptideWatchWidgets" / "Localizable.xcstrings",
}
TABLE = "Localizable"


def target_of(stringsdata: pathlib.Path) -> str | None:
    """The target a `.stringsdata` file was built for.

    The innermost `<Target>.build` folder names it; the outer one is the
    project's (`Peptide.build`), which must not make a test target count.
    """
    for part in reversed(stringsdata.parts):
        if part.endswith(".build"):
            target = part[:-len(".build")]
            return target if target in TARGET_CATALOGS else None
    return None


def extracted_keys(stringsdata: pathlib.Path, repo: pathlib.Path = REPO) -> set[str]:
    """Keys of the `Localizable` table one compiled Swift file looks up.

    A cached DerivedData keeps `.stringsdata` for Swift files that were since
    deleted, and for other checkouts; only files compiled from a source that
    still exists in this checkout count.
    """
    data = json.loads(stringsdata.read_text())
    source = pathlib.Path(data.get("source") or "")
    if not source.is_file() or not source.resolve().is_relative_to(repo.resolve()):
        return set()
    return {entry["key"] for entry in (data.get("tables") or {}).get(TABLE, [])
            if isinstance(entry, dict) and "key" in entry}


def needs_translation(key: str, entry: dict | None) -> bool:
    if not re.search(r"[A-Za-z]", re.sub(r"%(?:\d+\$)?[-+#0]*\d*(?:ll|l|h)?[@dDuUxXfFeEgGsS]", "", key)):
        return False
    return entry is None or entry.get("shouldTranslate", True)


def gaps(keys_by_target: dict[str, set[str]], catalogs: dict[str, dict]) -> list[str]:
    """`target: language: key` for each extracted key a shipped language lacks."""
    out = []
    for target, keys in sorted(keys_by_target.items()):
        catalog = catalogs[target]
        strings = catalog.get("strings", {})
        source = catalog.get("sourceLanguage", "en")
        languages = sorted({lang for v in strings.values()
                            for lang in (v.get("localizations") or {})} - {source})
        for key in sorted(keys):
            entry = strings.get(key)
            if not needs_translation(key, entry):
                continue
            have = (entry or {}).get("localizations") or {}
            out += [f"  {target}: {lang}: {key!r}" for lang in languages if lang not in have]
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2
    keys_by_target: dict[str, set[str]] = {}
    files = 0
    for path in pathlib.Path(argv[1]).expanduser().rglob("*.stringsdata"):
        target = target_of(path)
        if target is None:
            continue
        files += 1
        keys_by_target.setdefault(target, set()).update(extracted_keys(path))
    if not files:
        print(f"::error::no .stringsdata under {argv[1]}; was SWIFT_EMIT_LOC_STRINGS turned off?")
        return 1
    catalogs = {t: json.loads(TARGET_CATALOGS[t].read_text()) for t in keys_by_target}
    for target, keys in sorted(keys_by_target.items()):
        print(f"  {target}: {len(keys)} keys extracted by the compiler")
    missing = gaps(keys_by_target, catalogs)
    if missing:
        print(f"\n{len(missing)} compiler-extracted key(s) render untranslated "
              "(add them to the target's Localizable.xcstrings):")
        print("\n".join(missing))
        return 1
    print("  every extracted key is translated")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
