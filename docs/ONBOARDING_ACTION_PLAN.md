# Onboarding Action Plan — Detailed

Branch: `claude/audit-onboarding-experience-LEVSs`
Companion to: `docs/ONBOARDING_AUDIT.md`

Execution status updates inline as items land. See trailing
"Audits" section for bug-hunting findings.

---

## Plan A — Items I can execute from here

### A2. Typography variation pass
**Goal**: break the visual monotony of identical 32-pt rounded heads.
**Steps**:
1. Identify each page's role: heavy-moment vs data-entry vs informational
2. For heavy moments (Welcome, Projection, Ready, Disclaimer): keep `.system(size: 38, weight: .bold, design: .rounded)`
3. For data-entry pages (Name, Goal, GoalDate, Experience, BodyMetrics, Schedule, Equipment, Nutrition): drop to `.system(size: 26, weight: .bold, design: .rounded)` + smaller subhead
4. For informational pages (Comparison, ProgramPreview): keep mid-weight 28pt
5. Touch: `OnboardingView.swift` headlines on 8+ pages

### A3. Home-tab "X weeks until your goal" tile
**Goal**: surface the committed `goalDate` post-onboarding so the commitment matters.
**Steps**:
1. Build a `GoalCountdownCard` component reading `profile.goalDate` + `profile.primaryGoal`
2. Show: weeks remaining, target date, primary goal label, tap-to-Insights
3. Hide cleanly when `goalDate` is nil (older accounts, skipped users)
4. Place: near the existing motivation/streak cards on Home
5. Touch: new file in `Features/Home/Components/`, mount in HomeView

### A4. ScenePhase refresh for notification auth
**Goal**: notification row re-checks OS auth when app foregrounds.
**Steps**:
1. Add `@Environment(\.scenePhase) private var scenePhase` to OnboardingView
2. `.onChange(of: scenePhase)` — re-run the auth check when `.active`
3. Same for HealthKit — Health auth status can be revoked in Settings

### A5. Widget add-deeplink tip card on Ready
**Goal**: lift widget-add rate from ~5% to ~15-20%.
**Steps**:
1. Add a small `widgetTip` row at the bottom of `readyStep`
2. Copy: "Pro tip — long-press your home screen to add the Atlas widget."
3. Tap → Apple's documented widget-gallery deep link doesn't exist; fall back to nothing (just a tip)
4. Use a subtle `widget.tint` style so it doesn't compete with the primary CTA

### A10. "How did you hear about us?" attribution survey
**Goal**: surface marketing-channel attribution into the funnel snapshot.
**Steps**:
1. New page between `socialProof` and `valueProof` (low-friction position)
2. 6 chip options: Friend, App Store, TikTok, YouTube, Reddit, Other
3. Optional skip; persist into `OnboardingFunnelTracker.recordEvent("attribution_<channel>")`
4. Store the channel string on the funnel snapshot for later drain
5. Touch: new view in OnboardingView, Page enum slot, funnel event

### A7. Localize stub keys
**Goal**: new English copy is parseable by xcodebuild's localization extractor.
**Steps**:
1. Walk every new `Text("…")` literal added on this branch
2. Wrap any non-SwiftUI auto-LocalizedStringKey usage in `LocalizedStringKey(...)` or use string literal
3. Verify `Localizable.xcstrings` picks them up on next `xcodebuild -exportLocalizations`
4. Stubs only — native translators close the loop

### A6. Onboarding tests
**Goal**: cover funnel tracker, primary action, projection math.
**Steps**:
1. `OnboardingFunnelTrackerTests`: snapshot round-trip, idempotency, event ordering
2. `OnboardingViewTests`: enum boundary tests for primaryAction branches
3. `ProjectionChartTests`: curve direction for loss vs gain goals
4. New file: `PeptideTests/OnboardingTests.swift`

### A8. Lightweight A/B experiment scaffolding
**Goal**: deterministic split-testing without a backend.
**Steps**:
1. `OnboardingExperiment` enum with `.control` / `.variantA`
2. Assignment via hash of install ID stored in UserDefaults
3. One concrete use site: paywall tier-order (annual-first default vs monthly-first variant)
4. Funnel event records assigned variant for correlation
5. New service file

---

## Plan B — Items requiring your environment

(unchanged from previous revision — see below for full step-by-step)

### B1. Build & run in Xcode

```bash
git fetch origin
git checkout claude/audit-onboarding-experience-LEVSs
git pull
xcodegen generate
open Peptide.xcodeproj
```

In Xcode: Peptide scheme → iPhone 16 simulator → ⌘B build → ⌘R run.
If anything fails, paste the error.

### B2. Tests

```bash
xcodebuild test \
  -project Peptide.xcodeproj \
  -scheme Peptide \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'
```

### B3. Decide peptide-identity question
Option A (re-introduce peptides honestly — recommended) vs Option B
(stay training-pure). Tell me which one — I'll wire the changes.

### B4. Apple Developer config
1. https://developer.apple.com/account → Identifiers → `com.peptidesai.app`
2. Verify "Sign In with Apple" is checked
3. Regenerate provisioning profiles if changed
4. Xcode → target Peptide → Signing & Capabilities → verify capability

### B5. App Store Connect products
Verify these 3 product IDs exist:
- `com.peptidesai.app.pro.monthly` — 3-day free trial intro
- `com.peptidesai.app.pro.annual` — ~$49.99/yr
- `com.peptidesai.app.pro.lifetime` — ~$169

### B6. Promotional offers (optional, for real creator-code discounts)
Per-tier promo offers + a JWT-signing endpoint. ~1 day if you want it.

### B7. Physical-device tests (iPhone 15+, iPad with Stage Manager, Apple Watch)

### B8. TestFlight upload
```bash
bundle exec fastlane beta
```

### B9. Fresh-user testing (5–10 testers)

### B10. Localize new strings into 9 locales (native translators)

### B11. App Store metadata + screenshots update

### B12. App Review note about medical disclaimer

### B13. Merge the branch

---

## Audits (run after Plan A items land)

See trailing "Audit findings" section.
