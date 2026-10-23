# Atlas — handoff

## Current in-flight state

### Design-system audit (branch `claude/audit-design-system`)

Deliberately deferred: **A411**. The legacy (iOS 18–25) branches of
`glassSurface`, `glassControl` and `glassSurfaceCapsule` still end in
`.clipShape`, while iOS 26's `glassEffect` does not clip, so content
that overflows a glass surface is cut off on older OSes and spills on
26. Dropping the clip changes every legacy card that relies on it and
needs a visual pass on an iOS 18 device; `glassControl`'s legacy
hairline also depends on the clip (a 1pt stroke, half clipped away).

### Smart scan, barcode and library rebuild (branch `claude/smart-scan-library-s0p35l`)

New server route `server/api/food-scan.js` owns the prompt and a JSON
schema (structured outputs, `claude-opus-5-5`, `fallbacks: "default"`).
The app derives its URL from `MEAL_SCANNER_ENDPOINT` and falls back to
`/api/meal-scan` on 404, so it is safe to ship the app before the proxy.
What it adds: per-item fibre/sugar, portion chips that suit each food,
price ranges in the user's currency, scan tips; barcode review gets price
and missing serving / net weight from Atlas AI; an unknown barcode can be
read from a package photo; "Save to My Foods" from a barcode; the custom
food editor fills itself from typed words or a package photo; library
search with no hits offers "Add … with AI". Every new AI path is behind
`AIDataConsent`.

The scanner also learns from corrections: `ScanCorrectionMemory` keeps
the user's renames and portion fixes (>15 %) on device, and every
food-scan request carries the 15 newest as `corrections`, which the
proxy shape-checks and puts in the prompt. Erased with local data.

Then four upgrades on top, from comparing Cal AI, MacroFactor,
MyFitnessPal and PlateLens:
- **Follow-up questions**: food-scan returns up to three `questions`
  whose answers carry complete values; answer chips on each item swap
  them in without a second request (`EditableFoodItem.answer`).
- **Verified values**: `FoodGrounding` replaces the estimate with a
  matching My Foods entry, or a same-brand Open Food Facts hit with
  calories within 2× of the estimate. Badge on the row says which.
- **Type or dictate**: `MealDescriptionSheet` → food-scan `mode: meal`.
  Needs the new proxy deployed (an old one rejects the mode).
- **LiDAR scale**: on LiDAR iPhones `DepthMealCamera` replaces the
  system camera and sends the measured distance and photo span as the
  scan hint (`PhotoScale`). Untested on hardware: needs a Pro device
  check that capture, rotation and the distance look right.

Not compiled here (no Swift toolchain in the container). Still owed:
build-check on the PR, device QA of the review screens, deploying the
proxy, and watching real cost per scan before deciding the model.

### Watch app 2.0 (PR #184, merged)

The watch app is now a vertical pager in the shape of the watchOS 10
system apps: Today rings, Recovery, Sleep Score, Nutrition and Protocol,
plus Recovery and Sleep Score complications. The phone computes the
vitals (`DataStore.refreshWatchVitals()`, `SleepScoreEngine`) and pushes
them in `WatchData.vitals`, so the watch still has no HealthKit
entitlement. `build-check` compiled all three targets and ran the suite:
1517 tests, 0 failures, including `SleepScoreEngineTests` and
`WatchDataTests`.

Still owed, none of it possible without hardware:
- **Device QA** on a 41 mm and a 45/46 mm watch: every page fits without
  clipping, the heart and ECG beat at the resting rate, entrances replay
  on each Crown page, Always On and Reduce Motion hold everything still.
- **Numbers match:** with Health connected, the watch's Recovery equals
  the iPhone Today hero's, and the Sleep page shows last night, not a nap.
- **Dose round trip** with the phone reachable and unreachable (the phone
  now acks live messages, so taps should no longer fall back to
  `transferUserInfo`).
- **Rest-end alert (A301), partly fixed:** the watch no longer buzzes
  late when it resumes after the rest ended, but it only taps the wrist
  at rest end while the app is open. With it suspended, the wrist gets
  the phone's "Time to lift" notification only when the phone is locked.
  The full fix is a watch-side local notification for `rest.endsAt`
  (fixed identifier, replaced on skip, extend, pause and finish); check
  on device that it doesn't double up with the phone's notification.
- **Sleep Score weights** (duration 60, deep + REM 25, continuity 15) are
  a product call nobody has signed off on yet.
- **Store screenshots** in `marketing/app-store/screenshots-watch-*` are
  renders of `screens-watch/`. Check them against the device before
  uploading; update the HTML if the build differs.
- **Vercel `peptide-ai`** (the docs site) refuses deployments whose commit
  author has no linked Vercel account, so Claude-authored commits show it
  red. Allow unlinked authors in that project's Git settings, or ignore it.

### Deferred: paywall Close off-screen at accessibility sizes (A049)

At accessibility XXXL `PaywallView` lays out wider than the screen and its
top-trailing Close button lands off-screen. The cause is not confirmed: the
likeliest suspects are the `.fixedSize()` plan name, savings pill and price
in `pricingRow`, which together refuse to shrink. It needs a device or
simulator to reproduce, so it was not changed blind. `capturePaywall` in
`PeptideUITests/ScreenshotTests.swift` still wraps the miss in
`XCTExpectFailure`; once Close stays hittable, replace that block with
`XCTAssertTrue(closeButton.isHittable)`.

### Earlier: September 2026 audit

Branch: `claude/sleepy-babbage-fjf6gh`, on top of `main` at PR #178.

This branch is the September 2026 audit and the fixes that came out of it:
App Review and privacy compliance, proxy spend controls, correctness and
performance fixes, and revenue work (contextual paywalls, metered AI meal
scans, trial reminders, billing-retry banner, offer codes, win-back offer,
review prompts). `docs/ATLAS_AUDIT_2026_09.md` is the full record of what
was found, what changed, and what still needs a decision or credentials.

**Nothing on this branch has been compiled locally.** It was written in a
container with no Swift toolchain. The proxy suite (`cd server && npm
test`) and every `scripts/` gate pass; the Swift is only proven by
`build-check` on a non-draft PR. Open the PR and read that run before
anything else.

**Nothing has been seen rendered.** Device QA still owed: the paywall and
trial-offer footers (taller now, 44 pt targets), the AI consent sheet, the
meal-scan quota caption, the Delete All Data alert, and the reconstitution
calculator on an iPhone SE and a Pro Max, plus Dynamic Type and VoiceOver.

**Needs App Store Connect / Vercel / GitHub, not code:**
- Vercel: confirm `ANTHROPIC_DAILY_REQUEST_BUDGET` (production now defaults
  to 20 000 units when unset) and that Upstash Redis is configured.
- GitHub secrets: `APP_ATTEST_ENDPOINT`, `APP_ATTEST_SECRET`; then ship,
  watch for `app-attest ok` in logs, and set `APP_ATTEST_MODE=enforce`.
- App Store Connect: one-week intro offer on both subscriptions; rank Annual
  above Monthly in the group; decide on Family Sharing; create win-back
  offers; review screenshot slot 8 (the privacy screen now shows an AI
  card). Creator codes were removed from the app: deactivate any creator
  offer codes or promotional offers set up for them.

## Before merging branch work

1. `xcodegen generate`, then a clean build for an iOS 18+ simulator.
2. Run `PeptideTests`. CI runs it as a gating step inside `build-check`,
   so a green `build-check` means the suite passed.
3. Verify Liquid Glass surfaces on an iOS 26 simulator/device — the design
   work cannot be validated on older OSes.
4. Check the app in **all three** display modes. Light mode has never been
   run; the tokens are correct by construction, but no screen has been seen
   in it.

## Project basics

- Product: **Atlas** (iOS health & fitness). Repo / Xcode targets are
  named `Peptide` for legacy reasons — see the "Naming" section of
  [`README.md`](README.md).
- iOS 18+, Swift 6.0, SwiftUI, SwiftData (CloudKit-backed). Companion
  Watch app, two widget targets, Live Activities.
- Persistence runs through `SwiftDataRepository` (the JSON
  `PersistenceService` is retained only for custom peptides and
  widget snapshots).
- The Anthropic key lives in the Vercel proxy under `server/`; the iOS
  binary never ships one.
