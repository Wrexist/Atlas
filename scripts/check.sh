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
run "Design system (17 rules)" python3 scripts/design-lint.py --all
run "Colour contrast (244 token pairs, WCAG AA)" python3 scripts/contrast-check.py

if command -v swiftlint >/dev/null 2>&1; then
  run "SwiftLint" swiftlint lint --quiet
else
  printf '\n\033[1m── SwiftLint\033[0m\n\033[33m   skipped — not installed\033[0m\n'
fi

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
