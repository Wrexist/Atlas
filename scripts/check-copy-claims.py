#!/usr/bin/env python3
"""Check what the app *claims* against what it *does*.

Numbers in copy, privacy purpose strings, entitlements, App Group IDs — every
one is an assertion about the code, and every one is checked here against the
code itself.

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

# Add-only exports do not request read/write library access. Keep legacy,
# variable-access and asset-reading calls covered by the read-purpose check.
PHOTO_USAGE_PATTERNS = {
    "NSPhotoLibraryUsageDescription": (
        r"\bPHAsset\b|\bPHImageManager\b|\bPHCachingImageManager\b|\bPHFetchResult\b|"
        r"PHPhotoLibrary\.(?:requestAuthorization|authorizationStatus)\s*"
        r"(?:\((?!\s*for\s*:\s*\.addOnly\b)|\{)|"
        r"PHAssetChangeRequest\.(?:deleteAssets|init)\b"
    ),
    "NSPhotoLibraryAddUsageDescription": r"PHAssetChangeRequest|PHAssetCreationRequest|for:\s*\.addOnly",
}


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
    for d in ("screens", "screens-watch", "screens-watch-frames", "social"):
        for p in sorted((base / d).glob("*.html")):
            for m in re.finditer(pattern, p.read_text()):
                found.append((str(p.relative_to(REPO)), m.group(0)))
    return found


# Ids a test deliberately expects to be *absent*, so `lookup` returns nil and
# the empty-result path gets exercised. Each one must stay unfindable.
DELIBERATE_MISSING_IDS = {
    "definitely_not_real",
    "definitely_not_a_real_exercise_id_123",
}


def check_exercise_fixtures() -> list[str]:
    """Every `exerciseID` a test resolves through `ExerciseLibrary` must exist.

    `exerciseID: "Barbell_Bench_Press"` was written into the training fixtures;
    the dataset calls it `Barbell_Bench_Press_-_Medium_Grip`. The lookup
    returned nothing and six tests fell over — but the *worse* half is that the
    tests asserting emptiness went green, because comparing two empty
    dictionaries passes for any reason at all. A broken fixture made negative
    tests pass for the wrong reason, which is the failure mode that hides.

    Scoped to test files that actually touch `ExerciseLibrary`. Everywhere else
    an exercise id is an opaque key — `"Squat"` is a perfectly good one for a
    1RM calculation that never consults the dataset — and demanding real ids
    there would be noise nobody keeps paying.
    """
    tests = REPO / "PeptideTests"
    if not tests.exists():
        return []
    real = {e["id"] for e in json.loads(
        (REPO / "Peptide" / "Resources" / "exercises.json").read_text())}

    failures = []
    for p in sorted(tests.rglob("*.swift")):
        source = p.read_text()
        if "ExerciseLibrary" not in source:
            continue
        for m in re.finditer(r'(?:exerciseID:|lookup\(id:)\s*"([^"]+)"', source):
            ident = m.group(1)
            if ident in DELIBERATE_MISSING_IDS:
                if ident in real:
                    line = source.count("\n", 0, m.start()) + 1
                    print(f"  FAIL {p.name}:{line}: {ident!r} is allowlisted as "
                          "missing but the dataset now has it")
                    failures.append(f"exercise-fixture:{ident}")
                continue
            if ident not in real:
                line = source.count("\n", 0, m.start()) + 1
                print(f"  FAIL {p.name}:{line}: exerciseID {ident!r} is not in "
                      "exercises.json — the lookup will return nil")
                failures.append(f"exercise-fixture:{ident}")
    if not failures:
        print(f"  ok   exercise fixtures resolve against {len(real)} dataset ids")
    return failures


# Store-facing briefs must use the product names: "Protocol", not "stack",
# and "Biological Age", not the retired "Performance Age".
STORE_BRIEFS = ("APP_STORE_METADATA.md", "SCREENSHOT_PROMPT.md")
RETIRED_TERMS = r"(?i)\bperformance age\b|\bstack(?:s|ing)?\b"


def store_facing_files() -> list[pathlib.Path]:
    """The briefs, every marketing screen and doc, and the Marketing URL page
    App Review opens. The screenshots said "Performance Age" long after the
    briefs were fixed, because only the briefs were scanned."""
    files = [REPO / name for name in STORE_BRIEFS] + [REPO / "docs" / "index.html"]
    marketing = REPO / "marketing"
    if marketing.exists():
        files += sorted(p for p in marketing.rglob("*") if p.suffix in (".html", ".md"))
    return [p for p in files if p.exists()]


def check_store_terms() -> list[str]:
    failures = []
    for path in store_facing_files():
        name = path.relative_to(REPO)
        for number, line in enumerate(path.read_text().splitlines(), 1):
            for m in re.finditer(RETIRED_TERMS, line):
                print(f"  FAIL {name}:{number}: retired term {m.group(0)!r}")
                failures.append(f"term:{name}:{number}")
    if not failures:
        print("  ok   store-facing copy uses Protocol / Biological Age naming")
    return failures


# The app removed its synthetic "offer ends in" timer as misleading urgency
# (TrialOfferView), so a store screen showing one advertises UI that does not
# exist (Guideline 2.3.1).
COUNTDOWN_COPY = r"(?i)\bends in\b|\boffer expires\b|\btime left\b|\bcountdown\b"


def check_screenshot_countdowns() -> list[str]:
    failures = []
    for file, text in marketing_says(r"<[^<>]*>[^<>]*</"):
        if re.search(COUNTDOWN_COPY, text):
            print(f"  FAIL {file}: countdown copy {text!r}")
            failures.append(f"countdown:{file}")
    if not failures:
        print("  ok   store screens show no offer countdown")
    return failures


# Copy the user reads verbatim from the bundled data: the Swift tables in
# Peptide/Data and the JSON in Peptide/Resources. The noun for a combination
# is Protocol, never Stack, and "gold standard" is a clinical claim the app
# cannot back. exercises.json is skipped: its "weight stack" is gym kit.
BANNED_COMPATIBILITY_WORDING = r"\bstack(?:s|ed|ing)?\b|\bgold standard\b"
WORDING_EXEMPT_RESOURCES = {"exercises.json"}


def json_strings(value):
    if isinstance(value, dict):
        for item in value.values():
            yield from json_strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from json_strings(item)
    elif isinstance(value, str):
        yield value


def check_compatibility_wording() -> list[str]:
    failures = []

    def flag(where: str, text: str) -> None:
        hit = re.search(BANNED_COMPATIBILITY_WORDING, text, re.I)
        if hit:
            print(f"  FAIL {where}: user-facing copy says {hit.group(0)!r}")
            failures.append(f"compatibility-wording:{where}")

    for path in sorted((REPO / "Peptide" / "Data").glob("*.swift")):
        for number, line in enumerate(path.read_text().splitlines(), start=1):
            if line.lstrip().startswith("//"):
                continue
            for literal in re.findall(r'"((?:[^"\\]|\\.)*)"', line):
                flag(f"{path.name}:{number}", literal)
    for path in sorted((REPO / "Peptide" / "Resources").glob("*.json")):
        if path.name in WORDING_EXEMPT_RESOURCES:
            continue
        for text in json_strings(json.loads(path.read_text())):
            flag(path.name, text)
    if not failures:
        print("  ok   bundled data copy avoids 'stack' and 'gold standard'")
    return failures


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

    # Privacy purpose strings vs the APIs the code actually touches. A missing
    # one is a hard TCC termination on first access; a wrong one is what the
    # user reads at the consent prompt.
    plist = (REPO / "project.yml").read_text()
    declared = set(re.findall(r"(NS\w+UsageDescription):", plist))
    required = {
        "NSHealthShareUsageDescription": r"HKHealthStore|HealthKit",
        "NSHealthUpdateUsageDescription": r"toShare:",
        "NSCameraUsageDescription": r"AVCaptureDevice|AVCaptureSession|UIImagePickerController",
        **PHOTO_USAGE_PATTERNS,
        "NSFaceIDUsageDescription": r"LAContext|LocalAuthentication",
        "NSMicrophoneUsageDescription": r"AVAudioRecorder",
        "NSLocationWhenInUseUsageDescription": r"CLLocationManager",
        "NSMotionUsageDescription": r"CMMotionManager|CMPedometer",
    }
    swift = "\n".join(
        p.read_text()
        for root in ("Peptide", "PeptideWatch")
        if (REPO / root).exists()
        for p in (REPO / root).rglob("*.swift")
    )
    for key, pat in required.items():
        used = re.search(pat, swift) is not None
        if used and key not in declared:
            print(f"  FAIL {key}: code uses this API but no usage string is declared")
            failures.append(key)
        elif used:
            print(f"  ok   {key}: declared and used")

    # The write description must not claim the app does not write.
    m = re.search(r"NSHealthUpdateUsageDescription:\s*\"(.*?)\"\s*$", plist, re.M)
    if m and re.search(r"does not write|never writes", m.group(1), re.I):
        if "toShare:" in swift and "toShare: []" != swift:
            print("  FAIL NSHealthUpdateUsageDescription claims the app does not "
                  "write, but requestAuthorization(toShare:) is called")
            failures.append("health-write-claim")

    # Entitlements vs code. A capability used without its entitlement fails at
    # runtime; an App Group that disagrees between targets means the widget
    # silently reads an empty container forever.
    import plistlib
    ents = {}
    for f in sorted(REPO.rglob("*.entitlements")):
        try:
            ents[f.name] = plistlib.load(f.open("rb"))
        except Exception as e:
            print(f"  FAIL {f.name}: unreadable ({e})")
            failures.append(f.name)
    groups = {g for d in ents.values() for g in d.get("com.apple.security.application-groups", [])}
    code_groups = set(re.findall(r'"(group\.[\w.-]+)"', swift))
    if len(groups) > 1:
        print(f"  FAIL App Group differs between targets: {sorted(groups)}")
        failures.append("app-group-mismatch")
    elif code_groups and not (code_groups <= groups):
        print(f"  FAIL code uses {sorted(code_groups)}, entitlements declare {sorted(groups)}")
        failures.append("app-group-code-mismatch")
    elif groups:
        print(f"  ok   App Group {sorted(groups)[0]} consistent across "
              f"{len(ents)} targets and code")

    app_ents = ents.get("Peptide.entitlements", {})
    for key, pat, label in [
        ("com.apple.developer.healthkit", r"HKHealthStore", "HealthKit"),
        ("com.apple.developer.applesignin", r"ASAuthorizationAppleIDProvider", "Sign in with Apple"),
        ("com.apple.developer.devicecheck.appattest-environment", r"DCAppAttestService", "App Attest"),
        ("com.apple.developer.icloud-services", r"ModelConfiguration|CKContainer", "CloudKit"),
    ]:
        used, declared = re.search(pat, swift) is not None, key in app_ents
        if used and not declared:
            print(f"  FAIL {label}: used in code, no entitlement")
            failures.append(label)
        elif used:
            print(f"  ok   {label}: entitlement and code agree")

    if re.search(r"ActivityKit|Activity<", swift) and "NSSupportsLiveActivities" not in plist:
        print("  FAIL Live Activities used but NSSupportsLiveActivities is not set")
        failures.append("live-activities")
    elif "NSSupportsLiveActivities" in plist:
        print("  ok   Live Activities: declared and used")

    failures += check_exercise_fixtures()
    failures += check_store_terms()
    failures += check_screenshot_countdowns()
    failures += check_compatibility_wording()

    if failures:
        print(f"\n{len(failures)} copy claim(s) no longer match the source")
        return 1
    print("\nall copy claims match their source")
    return 0


if __name__ == "__main__":
    sys.exit(main())
