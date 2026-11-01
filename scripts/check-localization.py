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

`Text("…")` is not the only way a literal becomes a catalog lookup: custom
views and helpers that take a `LocalizedStringKey` (`title:`, `eyebrow:`,
`subtitle:`, …) and String enums whose `rawValue` is wrapped in one do too,
and they let English section headings leak into the Swedish UI. Every such
literal must have a catalog key translated into each shipped language.

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


def strip_comments(code: str) -> str:
    """`code` with comments blanked, string literals intact, offsets kept."""
    out, i, n = list(code), 0, len(code)
    while i < n:
        if code.startswith('"""', i):
            end = code.find('"""', i + 3)
            i = n if end < 0 else end + 3
        elif code[i] == '"':
            i += 1
            while i < n and code[i] not in '"\n':
                i += 2 if code[i] == "\\" else 1
            i += 1
        elif code.startswith("//", i) or code.startswith("/*", i):
            end = code.find("\n" if code[i + 1] == "/" else "*/", i)
            end = n if end < 0 else end + (0 if code[i + 1] == "/" else 2)
            out[i:end] = re.sub(r"[^\n]", " ", code[i:end])
            i = end
        else:
            i += 1
    return "".join(out)


def closing(code: str, open_at: int) -> int:
    """Index of the bracket closing the one at `open_at`, skipping strings."""
    depth, i = 0, open_at
    while i < len(code):
        c = code[i]
        if c == '"':
            i += 1
            while i < len(code) and code[i] != '"':
                i += 2 if code[i] == "\\" else 1
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return len(code)


def split_top_level(text: str) -> list[str]:
    """`text` split at commas outside brackets and strings."""
    parts, depth, start, i = [], 0, 0, 0
    while i < len(text):
        c = text[i]
        if c == '"':
            i += 1
            while i < len(text) and text[i] != '"':
                i += 2 if text[i] == "\\" else 1
        elif c in "([{<":
            depth += 1
        elif c in ")]}>" and not (c == ">" and text[i - 1] == "-"):
            depth -= 1
        elif c == "," and depth == 0:
            parts.append(text[start:i])
            start = i + 1
        i += 1
    parts.append(text[start:])
    return [p.strip() for p in parts if p.strip()]


LSK_TYPE = re.compile(r"^LocalizedStringKey\??$")
PLAIN_STRING_TYPE = re.compile(r"^(?:String|Substring)\??$")
TYPE_DECL = re.compile(r"\b(struct|class|enum|actor|extension)\s+(\w+)[^{;]*?\{")
INIT_OR_FUNC = re.compile(r"(?<!\.)\b(?:init[?!]?|func\s+(\w+))\s*(?:<[^>(]*>)?\s*\(")
STORED_PROPERTY = re.compile(r"^[ \t]*(?:(?:private|fileprivate|internal|public)\s+)?"
                             r"(?:let|var)\s+(\w+)\s*:\s*([\w?.]+)", re.MULTILINE)


def swift_sources(roots: tuple[str, ...]):
    for root in roots:
        for p in sorted((REPO / root).rglob("*.swift")):
            yield p, strip_comments(blank_previews(p.read_text()))


def parameter_types(signature: str) -> dict[str, str]:
    """External label → declared type; an unlabeled first parameter is `_0`."""
    out = {}
    for index, param in enumerate(split_top_level(signature)):
        m = re.match(r"(\w+)(?:\s+\w+)?\s*:\s*(?:@\w+\s+)*([^=]+)", param)
        if not m:
            continue
        label = m.group(1)
        if label == "_":
            if index:
                continue
            label = "_0"
        out[label] = m.group(2).strip()
    return out


def lsk_parameters(sources) -> dict[str, set[str]]:
    """Callee name → labels typed `LocalizedStringKey` in every overload that has them.

    Callees are view types (explicit or memberwise inits) and functions. A
    label that some overload of the same name takes as a plain `String` is
    dropped: a literal picks the `String` overload, so it is never looked up.
    """
    seen: dict[str, dict[str, set[str]]] = {}

    def record(callee: str, types: dict[str, str]):
        for label, type_ in types.items():
            seen.setdefault(callee, {}).setdefault(label, set()).add(type_)

    for _, code in sources:
        bodies = [(m.group(1), m.group(2), m.end() - 1, closing(code, m.end() - 1))
                  for m in TYPE_DECL.finditer(code)]
        for m in INIT_OR_FUNC.finditer(code):
            types = parameter_types(code[m.end():closing(code, m.end() - 1)])
            if m.group(1):
                record(m.group(1), types)
                continue
            owner = min((b for b in bodies if b[2] < m.start() < b[3]),
                        key=lambda b: b[3] - b[2], default=None)
            if owner:
                record(owner[1], types)
        for kind, name, start, end in bodies:
            if kind != "struct":
                continue
            members = [m for m in STORED_PROPERTY.finditer(code, start, end)
                       if code.count("{", start, m.start()) - code.count("}", start, m.start()) == 1]
            explicit_init = any(code.count("{", start, i.start()) - code.count("}", start, i.start()) == 1
                                for i in re.finditer(r"(?<!\.)\binit[?!]?\s*\(", code[:end])
                                if i.start() > start)
            if not explicit_init:
                record(name, {m.group(1): m.group(2) for m in members
                              if not code[m.end():code.find("\n", m.end())].lstrip().startswith("{")})
    return {callee: {label for label, types in labels.items()
                     if any(LSK_TYPE.match(t) for t in types)
                     and not any(PLAIN_STRING_TYPE.match(t) for t in types)}
            for callee, labels in seen.items()}


LITERAL = r'"((?:[^"\\]|\\.)*)"'


def argument_literals(value: str) -> list[str]:
    """The literals a `LocalizedStringKey` argument can render: `"A"` or `c ? "A" : "B"`."""
    m = re.fullmatch(LITERAL, value) or re.fullmatch(rf"[^\"]+\?\s*{LITERAL}\s*:\s*{LITERAL}", value)
    return [g for g in (m.groups() if m else ()) if "\\(" not in g and re.search(r"[A-Za-z]", g)]


def enum_raw_values(code: str, name: str) -> list[str]:
    m = re.search(rf"\benum\s+{name}\s*:\s*String\b[^{{]*\{{", code)
    if not m:
        return []
    body = code[m.end():closing(code, m.end() - 1)]
    return re.findall(rf"\bcase\s+\w+\s*=\s*{LITERAL}", body) + \
        re.findall(rf",\s*\w+\s*=\s*{LITERAL}", body)


def localized_key_arguments(roots: tuple[str, ...] = ("Peptide",)) -> dict[str, set[str]]:
    """Literals that reach a `LocalizedStringKey` parameter, each with where it is used.

    `Text("…")` is already counted by `ui_sentences`; this covers the custom
    views and helpers that take a `LocalizedStringKey` (`title:`, `eyebrow:`,
    `subtitle:`, …) and String-backed enums whose `rawValue` is wrapped in
    `LocalizedStringKey(…)` for a `GlassSegmentedControl`. Each one is
    looked up in the catalog at runtime, so a missing key renders English.
    """
    sources = list(swift_sources(roots))
    params = {k: v for k, v in lsk_parameters(sources).items() if v}
    found: dict[str, set[str]] = {}
    for path, code in sources:
        where = path.relative_to(REPO).as_posix()
        for m in re.finditer(r"(?<![\w])(\w+)\s*\(", code):
            labels = params.get(m.group(1))
            if not labels or re.search(r"\b(?:func|init|struct|class|enum)\s*$", code[:m.start()]):
                continue
            args = split_top_level(code[m.end():closing(code, m.end() - 1)])
            for index, arg in enumerate(args):
                labelled = re.match(r"(\w+)\s*:(?!:)\s*(.*)$", arg, re.DOTALL)
                label, value = (labelled.groups() if labelled else (f"_{index}", arg))
                if label in labels:
                    for literal in argument_literals(value.strip()):
                        found.setdefault(unescape(literal), set()).add(where)
        for m in re.finditer(r"LocalizedStringKey\(\s*\$0\.rawValue\s*\)", code):
            enum = re.findall(r"options:\s*(\w+)\.allCases", code[max(0, m.start() - 400):m.start()])
            if enum:
                for raw in enum_raw_values(code, enum[-1]):
                    found.setdefault(unescape(raw), set()).add(where)
    return found


def untranslated_arguments(arguments: dict[str, set[str]], strings: dict,
                           languages: set[str]) -> list[str]:
    """One line per argument literal the catalog lacks, or lacks in a shipped language."""
    gaps = []
    for key in sorted(arguments):
        have = set((strings.get(key) or {}).get("localizations") or {})
        missing = ["catalog key"] if key not in strings else sorted(languages - have)
        if missing:
            gaps.append(f"  {key!r} — no {', '.join(missing)} — {', '.join(sorted(arguments[key]))}")
    return gaps


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

    arguments = localized_key_arguments()
    print(f"  literals passed as LocalizedStringKey: {len(arguments)}")

    orphans = sorted(k for k in keys if k not in sentences and k not in arguments
                     and " " in k and re.match(r"^[A-Z]", k))
    print(f"  catalog keys no longer in the UI: {len(orphans)}")

    shipped = shipped_languages(list(catalogs.values()))
    print(f"  languages the build ships: {len(shipped)}  ({', '.join(sorted(shipped))})")

    # A language is only worth shipping if the app is actually in it — its
    # own translations, not the keys. The withheld catalog is fully
    # translated but covers a small fraction of the UI, so shipping those
    # nine would have put them on the App Store listing while handing those
    # users a mostly-English app, dosing and safety copy included.
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

    # Held to every key, not a share: these are titles and eyebrows, so a
    # single miss is an English heading in the middle of a translated screen.
    gaps = untranslated_arguments(arguments, strings, shipped - {"en", "Base"})
    if gaps:
        print(f"\n{len(gaps)} literal(s) passed to a LocalizedStringKey parameter render "
              "in English (add them to Localizable.xcstrings):")
        print("\n".join(gaps))
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
