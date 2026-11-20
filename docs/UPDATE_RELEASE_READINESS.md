# Atlas release checklist — TestFlight only

Updated 2026-11-20. Since 2026-11-14 Atlas is distributed only to the
owner's own TestFlight; there is no App Store submission. Store copy,
IAP setup, screenshots, privacy labels and offer codes are out of scope.
`APP_STORE_METADATA.md` and `scripts/check-store-metadata.py` stay in CI
so the store copy is ready if that ever changes. (This file replaces the
2026-10-06 readiness report for 1.3.0.)

## Before you dispatch a build

1. The change is merged to `main` and **PR Checks is green on the merge
   commit** (about 30 minutes after merging). The workflow's `gate` job
   refuses anything else.
2. **Did a SwiftData model change?** (A new `@Model`, a new stored
   property, or a renamed one.) Then deploy the CloudKit schema to
   Production first. TestFlight builds talk to the **Production**
   environment of `iCloud.com.peptidesai.app`, and Production never
   creates record types or fields on its own, so new data silently
   stays on the phone until the schema is deployed:
   1. Run a Debug build from Xcode on a device signed in to iCloud and
      use the new feature once, so the Development schema gets the new
      record type or field.
   2. Open https://icloud.developer.apple.com → CloudKit Database →
      `iCloud.com.peptidesai.app`.
   3. Choose **Deploy Schema Changes…**, check that the list shows the
      new `CD_*` record types and fields, and confirm.
3. Apple's agreements in App Store Connect → Business are all Active.
   An expired agreement fails the run in the first minute
   (`fastlane/auto_version.rb`); only the Account Holder can accept it.

## Dispatch

GitHub → Actions → **iOS TestFlight** → Run workflow on `main`. Leave the
version blank: `fastlane/auto_version.rb` picks one above every version
Apple already has, never below `AUTO_VERSION_FLOOR` (1.6). The build
number is the run number. The build appears in TestFlight about 15 to
30 minutes after the run finishes.

If the `SENTRY_AUTH_TOKEN` secret exists, the last step uploads the
build's dSYMs to Sentry (`isac-molin/apple-ios`) so crash reports show
function names. Without it the step prints a notice and skips.

## After installing

- Smoke test: launch, Today, log a meal (photo, barcode, library), start
  and finish a workout with the rest timer, check the widgets, open the
  Watch app, force quit mid-workout and reopen.
- Crash and hang reports arrive in Sentry within a day (MetricKit
  delivers them on the next launch).

## Never verified on hardware yet

These have only been built and unit-tested in CI. Check them when a
build is on the phone:

1. iCloud account switch: sign out of iCloud (or switch account) and
   open Atlas; the Keep / Delete prompt appears and both choices work.
2. Live Activity during a workout: lock the phone, tap Complete set /
   Skip rest; the app shows the change when reopened.
3. Glass cards on iOS 18–25 (A411), if a device on that OS is around:
   no content spills past the rounded corners.
4. Water on Today: tap water, "Added 250 mL · Undo" appears, Undo
   removes it.
5. Apple Watch: log sets with the phone reachable and unreachable, run a
   whole workout on the watch, Digital Crown, haptics, complications on
   41 mm and 45/46 mm.
6. Camera features: fridge scan, photo cut-out, LiDAR portion estimate.

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
