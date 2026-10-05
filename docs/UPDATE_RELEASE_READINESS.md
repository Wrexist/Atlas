# Atlas update readiness — 2026-10-05

Status: implementation prepared; release blocked on native verification. No release or TestFlight upload was performed.

## This update

- Recipes require every ingredient and portion to resolve before logging, including Siri. Incomplete drafts remain editable, with a repair route and clearly labeled partial previews.
- Food-library search deduplicates returned products and promotes exact names, then prefixes and matching words. Source nutrition is unchanged; no fabricated food database was added.
- Library review and quick logging reuse the latest valid recorded portion. Exact gram entry uses the existing portion editor.
- Recipe, library, and repeat logging use durable meal persistence. Save failures keep the review available. Success offers persistent Undo, Log another food, and Done.
- Undo commits the deletion before claiming success. Barcode history writes and reversals are ordered. No schema migration or workout storage changes.

## Evidence

- Design lint: 0 errors, 0 warnings; checker self-tests: 44/44 passed.
- Contrast check: 288 token combinations, 0 below AA. This is not a rendered screen audit.
- Copy/entitlement claims check: passed.
- Swift syntax parsing: passed for the nine changed/new Swift files. Parsing does not establish type correctness.
- Focused XCTest coverage added in `PeptideTests/FoodLibraryLogicTests.swift`: recipe completeness, invalid portions, ranking/deduplication, remembered portions, and failed/successful durable recipe saves. Not executed here.
- Existing `MealScanRecoveryTests` covers durable commit/retry/reopen/Undo identity and scan draft recovery; must be rerun.
- Native attempt: https://github.com/Wrexist/Atlas/actions/runs/37259162751 . Job never started: account locked due to billing. No new native screenshots were produced. Windows has no Xcode or iOS simulator.

## Release gates, in order

1. Restore a functioning macOS runner or use a Mac. Generate the project with `xcodegen generate`. Run SwiftLint and the full `PeptideTests` suite using the repository PR-checks workflow. Run training validation and UI tests. Fix failures before proceeding.
2. Capture and inspect Meals, incomplete recipe repair, exact portions, saved/Undo, scanner recovery, workout recap, and sharing on small/large iPhones, light/dark, large text, VoiceOver, and Reduce Motion. Confirm denied camera/photo/Health permissions and offline lookup behavior. Screenshots must come from the final build.
3. Verify an upgrade from the currently distributed build on a test account with existing workouts, meals, custom foods, recipes, favorites, and settings. Compare totals before/after; force quit and reopen. Do not reset storage. Test optional CloudKit and Health behavior on hardware using `CLOUDKIT_HARDWARE_TEST_PLAN.md`.
4. Review the existing uncommitted premium-motion changes independently. This food patch does not stage those files or claim their native verification. Include only reviewed changes in the release candidate.
5. Check the latest approved and TestFlight versions in App Store Connect. Supply an explicit valid higher marketing version to `ios-testflight.yml`; do not use the stale local `project.yml` version as release authority. Confirm matching app/watch/widget versions, signing, entitlements, privacy declarations, and release-service configuration. Credentials and store status have not been verified here.
6. Build and distribute an internal TestFlight candidate only after tests pass. Smoke-test install, sign-in, purchase/restore, logging, editing, recovery, share/cancel, account deletion, and offline relaunch. Review crash reports before wider rollout.
7. Finalize release notes, real-device App Store screenshots, support/privacy links, reviewer instructions, and privacy labels against the actual build. Submit and release through the established process after acceptance; no automatic publishing is part of this work.

## Reproduction and commands

On macOS after generation, replace `<SIMULATOR_ID>` with an available iPhone simulator:

```sh
swiftlint lint
xcodebuild test -project Peptide.xcodeproj -scheme Peptide \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:PeptideTests
```

For food recovery captures, dispatch `screenshots.yml` on the candidate branch with `test_filter=test_captureFoodReviewRecovery` (method name only; the workflow adds the class prefix).

Manual food regression: create two custom ingredients and a recipe; delete one ingredient; open the recipe and verify logging is blocked with a repair route. Repair it and log on a past date. Verify all calories and date, Undo, then relog. Search a food, set exact grams, log, reopen and verify the remembered amount. Exercise persistence failure using the test-only repository hook; success must never appear and retry must add one entry.

## Draft customer release notes

Food logging is easier to review and repeat. Atlas remembers your recent portions, supports exact gram entry in the food library, and keeps Undo available after saving. Improved recipe checks help prevent incomplete ingredients from producing misleading totals, with clearer guidance when a recipe needs attention.

These notes describe implemented behavior; publish only after the release gates pass.
