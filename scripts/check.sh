#!/usr/bin/env bash
# Every check that can run without Xcode, in one command.
#
# This exists because CI cannot currently start on this repository — every
# push since 2026-06-20 produces a `startup_failure` with no workflow name,
# which is what GitHub does when Actions is disabled or spending-limited.
# Until that is resolved, `pr-checks.yml` gates nothing, and the only way
# these checks run at all is if a human runs them.
#
#   scripts/check.sh            # everything available
#   scripts/check.sh --quick    # skip the browser-based screen measurement
#
# Exit status is non-zero if any check fails, so it works as a pre-push hook:
#   ln -s ../../scripts/check.sh .git/hooks/pre-push
set -uo pipefail
cd "$(dirname "$0")/.."

QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

FAILED=()
run() {
  local name="$1"; shift
  printf '\n\033[1m── %s\033[0m\n' "$name"
  if "$@"; then
    printf '\033[32m   pass\033[0m\n'
  else
    printf '\033[31m   FAIL\033[0m\n'
    FAILED+=("$name")
  fi
}

# ---------------------------------------------------------------- Swift side
# The checkers are checked first: a blind rule reports a clean bill it has
# not earned, which is worse than no rule. This suite exists because that
# actually happened to rule_glow on this branch.
run "Checker self-tests" python3 scripts/test_design_lint.py
run "Design system (20 rules)" python3 scripts/design-lint.py --all
run "Colour contrast (244 token pairs, WCAG AA)" python3 scripts/contrast-check.py

if command -v swiftlint >/dev/null 2>&1; then
  run "SwiftLint" swiftlint lint --quiet
else
  printf '\n\033[1m── SwiftLint\033[0m\n\033[33m   skipped — not installed\033[0m\n'
fi

# Numbers in copy are only wrong relative to something else. Nothing else
# here compares the two, which is how "LEVEL 14 · GOLD" shipped into an App
# Store screenshot for an app whose engine puts level 14 in Silver.
run "Copy claims vs source" python3 scripts/check-copy-claims.py

# Informational, not gating. Coverage is 13% today; making that a hard gate
# would just fail every run until someone commissions the translations.
printf '\n\033[1m── Localization coverage\033[0m\n'
python3 scripts/check-localization.py

run "Bundled peptide dataset" python3 - <<'PY'
import json, pathlib, sys
p = pathlib.Path("Peptide/Resources/peptides.json")
if not p.exists():
    print("peptides.json missing"); sys.exit(1)
data = json.loads(p.read_text())
n = len(data if isinstance(data, list) else data.get("peptides", []))
print(f"{n} entries")
sys.exit(0 if n >= 200 else 1)
PY

# ------------------------------------------------------------------ Proxy side
# The only part of this codebase whose tests actually execute here — Node,
# no Xcode required. 48 of them, covering the rate limiter, the per-device
# quota, App Attest and the CBOR decoder.
if [ -d server ] && command -v node >/dev/null 2>&1; then
  run "Proxy tests (server/)" bash -c "cd server && node --test >/dev/null 2>&1"
else
  printf '\n\033[1m── Proxy tests\033[0m\n\033[33m   skipped\033[0m\n'
fi

# ------------------------------------------------------------- Marketing side
if [ "$QUICK" = "0" ] && [ -d marketing/app-store ] && command -v node >/dev/null 2>&1; then
  for set in phone watch watchframe ipad; do
    run "App Store screens — $set" bash -c \
      "cd marketing/app-store && node measure.mjs $set 2>&1 | tail -1 | grep -qE '^\[.*\] [0-3] contrast'"
  done
else
  printf '\n\033[1m── App Store screens\033[0m\n\033[33m   skipped\033[0m\n'
fi

# ---------------------------------------------------------------------- Result
printf '\n'
if [ ${#FAILED[@]} -eq 0 ]; then
  printf '\033[32m✓ all checks passed\033[0m\n'
  printf '  Not covered here: compiling the app, the test target, or anything\n'
  printf '  rendered on a device. Those need Xcode.\n'
  exit 0
fi
printf '\033[31m✗ %d check(s) failed:\033[0m\n' "${#FAILED[@]}"
printf '   - %s\n' "${FAILED[@]}"
exit 1
