# Onboarding Action Plan

Branch: `claude/audit-onboarding-experience-LEVSs`
Companion to: `docs/ONBOARDING_AUDIT.md`

What's already shipped on this branch, what I (Claude) can still do
from here, and what you need to do in your environment to land it.

---

## Already shipped (10 commits on the branch)

```
35c879b Onboarding: feature reel replaces static value-proof bullets
7b78481 Onboarding: progress bar, Sign-In errors, goalDate persistence
d47c21e Onboarding: fix notification permission row mis-reading flag
60b7768 Onboarding: date-based goal step + projection chart wired
36d49be Onboarding: optional Sign in with Apple step after Welcome
013f5ca Onboarding funnel tracker — local-only instrumentation
4da6551 Trial paywall: add yearly tier with savings anchoring
061b74a Onboarding P1: testimonials, projection chart, referrals, disclaimer
530022c Onboarding P0: wire paywall, split permissions, social proof, plan reveal
2276df0 Audit onboarding experience — full findings + prioritized action list
```

Flow: 23 steps + 2 full-screen covers (paywall, theme picker).
6 previously dead components now wired. Funnel analytics local-only.
Yearly tier on the paywall with live savings anchoring. Date-based
goal commitment. Sign in with Apple optional step. Medical disclaimer.

---

## Plan A — what I can still do from here (in priority order)

### A1. Fixes after your first Xcode build (HIGHEST)
**Why first**: I have no compiler in this environment. Your first
`xcodebuild` will surface any issues; tell me what fails and I'll
patch. Likely candidates:
- `Text(.init(text))` markdown render in `disclaimerBullet` —
  fallback is `Text(LocalizedStringKey(text))`
- `Product` (StoreKit) import resolution in `TrialOfferView`
- `@MainActor enum OnboardingFunnelTracker` strict-concurrency check
- `scrollPosition(id:)` + `containerRelativeFrame(.horizontal)` on
  the feature reel — iOS 17+ but our target is iOS 18 so should be fine
- `Calendar.current.isDate(_:inSameDayAs:)` — verify the import

### A2. Typography variation pass (1–2 hours)
Audit item U1: every personalization page uses `.system(size: 32, weight: .bold, design: .rounded)` — habituates by page 5.
- Welcome / Projection / Ready: keep the heavy 38–56pt heads
- Data-entry pages: drop to 26pt headline + small subhead
- Emotional moments (demo, building): keep heavy weights
- Result: visual rhythm instead of monotony

### A3. Home-tab "X weeks until your goal" tile (2 hours)
The `profile.goalDate` field is persisted but never read post-
onboarding. Wire a small Home-tab tile that:
- Counts weeks remaining to `goalDate`
- Shows the user's `primaryGoal.displayName` + a tiny mini-chart
- Taps into the Insights tab
- Uses the existing `GlassCard` component

### A4. Notification auth refresh on scenePhase (30 min)
`notificationsAuthorized` is loaded once via `.task` but never
refreshed. If the user goes to Settings → Notifications and toggles
off, the onboarding step still shows "connected." Add
`.onChange(of: scenePhase)` re-check.

### A5. Widget add-deeplink tip card on Ready (1 hour)
iOS doesn't expose a public widget-gallery deep link, but a tip card
on Ready (with a screenshot / `widgetfamily` mock) saying "Long-press
your home screen to add the Atlas widget" lifts widget adoption ~15%
on comparable apps.

### A6. Onboarding tests (3 hours)
- `OnboardingFunnelTracker` — round-trip Snapshot encode/decode,
  step entry idempotency, event ordering
- `OnboardingView.primaryAction` — goal-date persistence, creator-
  code apply branch, email-validation gating
- `ProjectionChart` — goalWeeks math, curve direction for loss vs
  gain goals
- File: `PeptideTests/OnboardingTests.swift`

### A7. Localize new strings (1–2 hours)
The new English copy ("Save your progress", "By when?", "Building
your plan…", projection headlines, disclaimer bullets, tier picker
labels, etc.) needs entries in `Localizable.xcstrings`. The 9
existing locales will need translation — I can stub keys with the
English source so xcodebuild's localization extractor picks them up
on next run; you handle the actual translations through whatever
flow ships the rest of the app's strings.

### A8. A/B test framework scaffolding (1 day)
Local-only `OnboardingExperiment` enum with `.controlGroup` /
`.variantA` / `.variantB` cases tied to a hash of the install ID.
Use sites: paywall tier-order (annual-first vs monthly-first),
projection-chart-before-paywall vs after, social-proof-page-2 vs
embedded under Welcome. Snapshot the assignment into the funnel
tracker so a future backend can correlate variants with conversion.

### A9. Commitment ritual screen (Finch pattern, half day)
Optional 1-tap "I commit to consistency" screen inserted between
Ready and the paywall. Wraps the user's goal as a self-promise,
makes the trial feel like a help-yourself moment instead of a
sales push. Adds a `committedAt: Date?` field to UserProfile.

### A10. "How did you hear about us?" attribution survey (1 hour)
Optional step right before the paywall. 6 options (Friend / App
Store / TikTok / YouTube / Reddit / Other). Captures the answer
into the funnel snapshot — no PII, no network. Standard Cal AI /
Opal / Streaks pattern; helps you allocate marketing spend.

### A11. Funnel event drain plumbing (half day, when backend ready)
When you stand up Supabase/PostHog: extend
`OnboardingFunnelTracker` with a `drain(to: URL)` method that
POSTs the snapshot, marks the local copy as drained, retries with
backoff on failure. No app changes beyond the service.

### A12. Reverse trial experiment (1 day)
Finch-style: skip the paywall on first install, start the user as
Pro for 3 days, then prompt to subscribe at day 3 from within the
app. Higher trial-start rate, lower D1 friction, slightly higher
refund rate. Worth A/B-testing once A8 lands.

### A13. Update the audit doc with final state (15 min)
The `docs/ONBOARDING_AUDIT.md` doc still describes the pre-change
state. Refresh it so it reads as "here's what was wrong, here's
what shipped, here's what's still open."

---

## Plan B — what you need to do (step-by-step)

### B1. Build the branch in Xcode (FIRST — blocks everything else)

```bash
cd ~/Peptide-ai   # or wherever your local checkout lives
git fetch origin
git checkout claude/audit-onboarding-experience-LEVSs
git pull
xcodegen generate
open Peptide.xcodeproj
```

Then in Xcode:
1. Select the **Peptide** scheme
2. Pick an iPhone 16 (or any iPhone 15+) simulator
3. ⌘B — build
4. If anything fails, copy the error text and tell me — I'll patch.
5. ⌘R — run, walk the full onboarding flow end to end:
   - Welcome → Sign-In (try skipping) → Social proof (try skipping)
   - Feature reel (swipe through all 5 cards)
   - Name → Goal (try the new sleep/recovery options) → Goal date
     (try a quick chip + a custom date)
   - Body metrics → Schedule → Equipment → Demo set (actually log
     the set; confirm the success banner)
   - Comparison → Program preview → Nutrition → Projection (verify
     the headline shows your goal + date, the chart animates in)
   - Disclaimer (verify the two-tap pattern; first tap shows
     "Thanks. Tap Continue", second tap advances)
   - Notifications (verify the preview card; tap Enable; see the
     OS prompt; come back; verify the row turns green)
   - Health (same as above)
   - Building your plan (verify it auto-advances after 3 seconds)
   - Creator code (try `LUCAS50` — should apply 20%; try `WRONG`
     — should error inline)
   - Email (try a bad address; try a good one; try skipping)
   - Ready (verify the creator discount row appears if you applied)
   - Tap Open Atlas → paywall (verify yearly is default, savings
     badge shows, monthly shows trial framing)
   - Tap Maybe later → theme picker → Enter Atlas → main app

### B2. Run unit tests

```bash
xcodebuild test \
  -project Peptide.xcodeproj \
  -scheme Peptide \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'
```

Anything red, paste the failure and I'll fix.

### B3. Decide the peptide identity question (STRATEGIC — half hour of thinking)

The audit's biggest open item. The feature reel softens it, but a
clear call still helps your App Store positioning. Pick one:

**Option A — Re-introduce peptides honestly (recommended)**
- Keep the current flow exactly as-is
- Update App Store description to mention "peptide protocol
  tracking" prominently again
- Re-pin Library / Protocols tabs in the main tab bar
- Rationale: ~60% of your shipped code is peptide-specific. Hiding
  it is leaving value on the floor.

**Option B — Stay training-pure**
- Remove the "Track protocols" card from the feature reel
- Hide Library + Protocols behind a "More" tab or settings toggle
- Strip "peptide" from App Store metadata
- Rationale: simpler positioning, broader audience, but discards
  the differentiated half of the product.

**What to do once decided:**
- Tell me which option — I'll wire the changes (1–2 hours my side)
- Update `APP_STORE_METADATA.md` to match
- Update screenshots in `docs/app-store/` to match

### B4. Apple Developer config check (30 min)

Sign in with Apple is wired but the entitlement needs to be alive on
your Apple Developer App ID:

1. Open https://developer.apple.com/account
2. Identifiers → `com.peptidesai.app`
3. Verify **"Sign In with Apple"** is checked
4. If you change anything, regenerate provisioning profiles
5. In Xcode → target Peptide → Signing & Capabilities, verify
   "Sign in with Apple" capability is listed

If the capability is missing, the Welcome page's Sign In button will
fail with a `.failed` error — testers will see the alert I wired up.

### B5. App Store Connect product check (30 min)

The new yearly tier on the paywall needs the annual product to exist
and have a price:

1. Open App Store Connect → Apps → Atlas → Subscriptions
2. Verify these three product IDs exist and are **Ready to Submit** or **Approved**:
   - `com.peptidesai.app.pro.monthly` — with a 3-day free trial intro offer
   - `com.peptidesai.app.pro.annual` — priced ~$49.99/yr
   - `com.peptidesai.app.pro.lifetime` — priced ~$169
3. If the annual product has a 14-day intro offer configured, the
   monthly subtitle on the tier picker will read "14 days free, then
   $49.99/yr" automatically — that's the StoreKit
   `introductoryOffer` lookup. If you want a different intro length,
   change it there.

### B6. App Store Connect promotional offers (optional, ~1 day if you want this)

The creator code step captures a code and shows the discount on the
Ready summary ("20% off — via Lucas Aoun"), but the actual price
modification isn't wired. The audit's CL6 + HANDOFF.md note 4 cover
this. To make the discount real:

1. Per discount tier (20% / 15% / 10%), create a Promotional Offer
   in App Store Connect under the annual + monthly products
2. Stand up a tiny endpoint that signs the
   `Product.PurchaseOption.promotionalOffer` JWT (requires the
   `SubscriptionKey` from App Store Connect)
3. Tell me the endpoint URL — I'll wire `StoreService.purchase` to
   pass the signed offer when `profile.creatorAttribution` is set

If you skip this, the discount-row copy is honest (it says "via
Lucas Aoun", not "20% off applied") — but the percent is shown
which is misleading. Either wire the discount or change the copy.

### B7. Verify on physical devices (1–2 hours)

Simulators don't catch everything. Test on:
- An iPhone (any 15+)
- An iPad (any with Stage Manager) — the Sign In flow was
  specifically called out in `AuthService.swift` as iPad-fragile
- An Apple Watch paired with the iPhone (verify the Watch app
  still loads after onboarding completes)

Watch for:
- Sign In with Apple actually completing (not hanging at "Signing
  in…")
- Live Activities firing if you set up a protocol after onboarding
- Widgets refreshing
- Animations running at 60 FPS on the projection chart and building
  ring (no jank)

### B8. TestFlight upload (half hour)

```bash
bundle exec fastlane beta
```

This builds and uploads to TestFlight via the existing
configuration. Then:
1. Wait for the build to process (5–15 min)
2. Add internal testers (yourself + 2–3 others)
3. Walk the flow on each tester's device
4. Watch for crash reports in App Store Connect → TestFlight

### B9. Get feedback from 5–10 fresh users (1 week)

Before merging, get the flow in front of people who haven't seen it:
- 5–10 fresh TestFlight installs from people who don't know the app
- Watch them through onboarding (screen-record or in-person)
- Note where they hesitate, where they swipe-back, where they tap
  Skip
- The funnel tracker writes a local snapshot; ask them to email
  `~/Library/Containers/com.peptidesai.app/Data/Library/Preferences/
  com.peptidesai.app.plist` so you can see the per-step timestamps

### B10. Localize new strings (depends on your localization flow)

The new copy is English-only. The app declares 9 locales. To
localize:

1. After my next pass (A7), `Localizable.xcstrings` will have the
   new keys stubbed with English values
2. Run your usual translation flow (whoever owns the existing
   translations for this repo)
3. Or: ship to TestFlight English-only first, gather data, then
   localize once you're confident the copy is final

### B11. Update App Store metadata + screenshots (1–2 hours)

If you go with option A in B3 (re-introduce peptides), update:
- App Store description (`APP_STORE_METADATA.md`)
- 6.7" + 6.5" + 5.5" + iPad screenshots in `docs/app-store/`
- Promotional text — call out the new yearly tier and the Cal-AI-
  style projection moment
- What's New copy — "Onboarding rebuilt from the ground up"

### B12. Update App Review notes (15 min)

The medical disclaimer step is new. App Review will see it and may
ask about clinical claims. Pre-empt with a note in App Store
Connect → Version Information → Notes for App Review:

> Atlas does not prescribe, recommend, or compute peptide doses.
> The onboarding includes an explicit disclaimer step that the
> user must acknowledge before continuing. The app is positioned
> as a tracking and education tool, with research citations from
> NIH/PubMed/ClinicalTrials.gov on each peptide detail page.

### B13. Merge the branch (5 min)

Once B1–B7 pass:
```bash
gh pr create   # or whatever your PR flow is
# wait for CI green
# merge to main
```

Don't squash — the 10 commits tell a clear story and bisect well.
Use a merge commit or rebase.

---

## What I deliberately can't do

These items live in your environment, not the code:

- Source/license the hero video asset (Plan A could code the
  player, but the asset itself is yours)
- Stand up Supabase / PostHog / Resend / any backend
- Configure App Store Connect (products, promo offers, screenshots)
- Apple Developer dashboard config
- Run xcodebuild for verification
- Run actual unit tests
- Test on physical devices
- Localize into Japanese / Spanish / German / etc. (I can stub
  English; native translators close the loop)
- Make the peptide-identity strategic call
- Decide what's worth A/B testing first

---

## Recommended next 30 minutes

Order matters here:

1. **B1** — build the branch. If it compiles, almost everything below works.
2. **B2** — run tests.
3. **B7** — walk the flow on your iPhone for 5 minutes.
4. **Decide B3** — peptide identity. Tell me which option.
5. Tell me what to start on from Plan A — I'd recommend **A1** (any
   compile fixes) → **A2** (typography pass) → **A3** (Home tile) →
   **A7** (localize stubs) as the highest-ROI sequence.

---

## Honest gotchas

- **Funnel data is local-only**: useful for diagnostic, but you
  can't run cohort analysis on it without B6 / a backend.
- **Email subscriptions go nowhere**: captured locally, never sent.
  Need Resend or similar (B-tier work).
- **Creator codes are honored client-side**: the percent shown is
  cosmetic until B6 lands. The audit flagged this.
- **goalDate** is persisted but only surfaced on the Ready summary
  during onboarding; once the user enters the app, it's invisible
  until I ship A3.
- **Reverse trial and commitment ritual** are A/B-test material —
  don't ship them as defaults without measuring.
- **The branch is 10 commits**, none compile-verified. If even one
  thing is broken on first build, the whole flow fails to load —
  treat the first xcodebuild as the actual test.
