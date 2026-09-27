# Atlas audit — September 2026

Four parallel audits of `main` at `2a4ae11` (PR #178): correctness and
crashes, security and privacy, user-facing UX / accessibility / App Review,
and build / CI / tests / performance. Every finding below was confirmed by
reading the code. Nothing here was seen rendered: this pass had no Mac, no
simulator and no Swift toolchain, so every Swift change relies on CI's
`build-check` to prove it compiles.

Baseline before any change: `scripts/check.sh --quick` green (design lint
0/0, store metadata, copy claims, 208-entry dataset), proxy tests 50/50.

## Fixed on `claude/sleepy-babbage-fjf6gh`

| Area | Fix |
|---|---|
| Privacy / 5.1.3 | AI weekly recap now defaults **off** (it sends HRV to Anthropic; Info.plist and privacy.html already promised opt-in). The toggle names the recipient. |
| App Review 1.4.1 / 2.3.1 | The 12 bundled "Community Stacks" credited invented doctors ("Dr. M. Reyes, MD"), showed invented popularity scores and made efficacy claims. They are now "Atlas Editorial" research summaries with hedged wording, no scores, a disclaimer at "Use this stack", and the library is renamed "Stack Library". |
| App Review 1.4.1 | Calendar showed the database research range as the user's scheduled dose when none was set; now "Dose not set". |
| App Review 3.1.2(c) | Yearly plan headlined the per-month figure; the billed amount ($49.99/yr) now leads on both `PaywallView` and `TrialOfferView`. |
| App Review / IAP | `TrialOfferView` had no Restore Purchases; added. Onboarding skips the trial offer for existing subscribers. Paywall shows a retry state when products fail to load instead of an empty list. Inline auto-renew price and 24-hour cancellation line on the paywall. 44 pt hit targets on Restore / Terms / Privacy / Maybe later. |
| Store copy | `APP_STORE_METADATA.md` claimed "All on your device" and "No backend" while AI features use the proxy. Reworded; stated character count updated (3 940 / 4 000). |
| Onboarding bug | Swiping forward skipped `primaryAction()`, so name, goal and nutrition targets were never saved. Forward swipes are now blocked on every page. Outcome-promise headlines softened; sample Health values labelled "Example". |
| UX bug | Language picker offered 10 languages but only English ships; Arabic flipped the app RTL with English text. Picker now lists only bundled languages (hidden while that's just English) and a stale saved choice is dropped. |
| UX / honesty | Creator-program application only saved locally yet promised a reply in 5 business days. Hidden unless `AffiliateIntakeEndpoint` is configured. |
| UX | Today timeline forced 24-hour time; now follows the device's 12/24-hour setting. |
| Copy | Delete-account warning now lists workouts, meals and photos (which it does erase); privacy screen no longer implies free exports. |
| Security | Proxy rebuilds every content part from allow-listed fields and rejects `url` image sources (a 1 KB body could make Anthropic fetch large images for one quota unit). Two new tests; 52/52 pass. |
| Security | CSV exports neutralise leading `= + - @` (formula injection via Open Food Facts / AI meal names). |
| Security | Meal-scan retry now signs each attempt with a fresh App Attest assertion (the reused one would 401 under enforce). |
| Privacy manifests | `1C8F.1` app-group UserDefaults reason added to app, widgets and watch; watch widgets got a manifest (ITMS-91053). Unused `healthkit.background-delivery` entitlement removed. |
| CI | Screenshots workflow (the exit-70 failure) and the UI-tests step pick the simulator by UDID instead of `name=…,OS=latest`; the `simulator` input reaches the shell through `env`. |

## Needs a decision or credentials (not changed)

These change production behaviour or need access this pass didn't have.

1. **HIGH — proxy has no real spend cap.** The only working auth is the
   `PROXY_SHARED_SECRET` baked into Info.plist (extractable from the IPA).
   `APP_ATTEST_ENDPOINT` / `APP_ATTEST_SECRET` are never injected by
   `ios-testflight.yml`, so App Attest never runs and `enforce` can't be
   switched on without locking out every user. Limits are therefore per IP,
   and `ANTHROPIC_DAILY_REQUEST_BUDGET` defaults to 0 (disabled).
   **Do now:** set `ANTHROPIC_DAILY_REQUEST_BUDGET` in Vercel. **Then:** add
   the two attest keys to the TestFlight inject loop, ship, confirm
   `app-attest ok` in logs, set `APP_ATTEST_MODE=enforce`.
2. **MED — server fails open on missing config** (`app-attest.js` passes when
   `APP_ATTEST_APP_ID` or Redis is missing, even in enforce mode; rate limits
   fall back to per-instance memory without Redis). Deliberate today
   ("must not lock the API"); revisit once enforce is on.
3. **MED — cost accounting charges 1 unit per 256 KB**, so text is ~40×
   cheaper per unit than photos, and `meal-scan` accepts 40 messages of free
   text. Tighten per-route shape (meal-scan: one image + short text) and
   charge by estimated tokens.
4. **MED — HealthKit-derived data syncs to iCloud** (`WeeklySummary.KeyStats.hrvDelta`
   and HRV-quoting recap text land in the CloudKit store). Guideline
   5.1.3(ii) forbids storing health data in iCloud. Move summaries to a
   local-only `ModelConfiguration` or drop the HRV fields from the synced model.
5. **MED — existing users still have the weekly recap on.** The default
   flipped, but profiles saved before this change persisted `true`. Decide
   whether to reset it once (and show the consent) on upgrade.
6. **MED — no "Delete all data" for guests.** Account deletion only shows when
   signed in; the "Reset App Data" setting the code comments mention doesn't
   exist. Sign in with Apple tokens are never revoked via Apple's REST API on
   deletion (Apple requires it; the proxy could host the call).
7. **MED — creator codes name real-looking influencers** (`CreatorCodeService.swift:16-18`).
   Confirm signed agreements or use neutral seed codes.
8. **MED — privacy copy says AI inputs are "not retained".** Only true with a
   zero-data-retention agreement with Anthropic. Confirm or soften
   (Info.plist strings, `docs/privacy.html`).
9. **LOW — sensitive files use default Data Protection**: progress photos,
   backups, and temp exports (never deleted). Write with
   `.completeFileProtection`; delete temp exports after sharing.
10. **LOW — reconstitution calculator** defaults to 250 mcg with dosing
    quick-picks and "exact U-100 syringe units" copy, no disclaimer; its math
    lives in private view properties with no tests. Extract a
    `ReconstitutionEngine`, test it, neutralise the defaults.
11. **LOW — meal-scan capture time** calls `PHAsset.fetchAssets` without ever
    requesting Photos access, so it silently falls back to "now".
12. **LOW — legacy branding visible to users**: `support@peptidesai.com`,
    `/Peptide-ai/` privacy URL, dose-centric Siri phrases.

## Build, CI, tests

- `project.yml` builds in Swift 5 mode with `SWIFT_STRICT_CONCURRENCY: minimal`
  (CLAUDE.md says Swift 6). 32 `nonisolated(unsafe)` / `@unchecked Sendable`
  escape hatches are unchecked. Move to `targeted`, then `complete` + 6.0.
- `test-compile` in `pr-checks.yml` is a redundant second macOS job: the
  Unit Tests step already compiles and runs PeptideTests. Several comments
  (`project.yml:305-311`, `screenshots.yml:10-13`) still say the tests don't
  compile.
- Missing gates: no Release-config compile on PRs, no CI on pushes to main
  (`release.yml` pushes there), SwiftLint without `--strict`, `node --check`
  covers only `meal-scan.js`. The `labeled` trigger re-runs the 40-minute
  macOS build for any label.
- Three version schemes disagree (`project.yml` 1.0.1, TestFlight
  `1.2.<run>`, `release.yml` tag bumps). Pick one.
- `Peptide/Resources/Info.plist` is checked in but stale versus `project.yml`
  (regenerated at build); regenerate or ignore it.
- CloudKit sync has no `remote-notification` background mode / `aps-environment`,
  so other-device changes arrive only on foreground.
- Untested: `WatchSyncService`, `AppAttestService`, `ProgressPhotoCache`,
  `OfflineWeeklySummaryFormatter`, the three logging App Intents.
- Clock-dependent tests: `TodayOverviewSnapshotTests` (no injected `now`),
  real sleeps in `WorkoutSessionServiceTests`, `BackupSnapshotServiceTests`,
  `BarcodeProductCacheTests`. `PeptideApp.init` configures RevenueCat inside
  the test host.

## Performance

- `WorkoutHistoryView` builds a `DateFormatter` and regroups/sorts sessions on
  every render, plus a formatter per row. Same per-call formatter pattern in
  `WeeklySummaryDetailView`, `TrainOverviewView`, `LabEntryEditor` (every
  keystroke), `PeptideIntents`.
- `PRDetectionEngine.recompute` is O(sessions × PRs) on the main actor after a
  workout delete.
- `AtlasLogo` is a single 1024² 1.27 MB PNG drawn small (~4 MB decoded);
  anatomy PNGs are 1200×2880.
- `MealScanFlow` decodes the full-resolution photo on the view's actor;
  `ActiveWorkoutView` keeps an always-connected `Timer.publish`.

## Dead code (~800 lines, zero references)

`LabsEntryCard`, `WeightLogSheet`, `WeightTrackingCard`,
`BiometricCorrelationCard` (the only consumer of `BiometricCorrelationEngine`),
`PastWeeksSection`, `OnboardingRecommendationEngine` (tests only),
`FadeSlideModifier`. Delete, or wire in if they're intended features.

## Correctness sweep: clean

No force-unwraps, `try!`, reachable `fatalError`, TODO/FIXME, CloudKit-
incompatible model constraints, unguarded divisions in the `*Engine` types,
DST bugs in HealthKit day math, or notification-budget overflows were found.
Save failures retry and surface a banner. `DataStore.swift` (2 600 lines),
`ActiveWorkoutView` and most `Features/**/Components` views were sampled, not
read end to end.

## Still needs a device

Everything visual: iPhone SE / Pro Max layout of the changed paywall and trial
offer footers (now taller with 44 pt targets), Dynamic Type, VoiceOver, the
consent sheet, Sandbox purchase + restore, and the App Store Connect
one-week intro offer on both subscriptions.
