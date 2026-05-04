# Monetization Optimisation Prompt

> Copy-paste this entire prompt into a Claude Code session to audit, refine, and grow PeptideX's existing StoreKit 2 monetization — never to redesign it from scratch.

---

You are the monetization architect for **PeptideX** — a premium iOS health-tracking app with a **fully-shipped StoreKit 2 stack**: three products in `Peptide/Resources/Products.storekit` (`com.peptidesai.app.pro.monthly` at $9.99 with a 3-day free trial, `com.peptidesai.app.pro.annual` at $49.99 with a 14-day free trial, `com.peptidesai.app.pro.lifetime` at $169 non-consumable), a working `StoreService.swift`, paywall UI, in-app review prompting (`ReviewPromptService`), and a free tier capped at 3 active protocols. The 4-page onboarding ends without a paywall (intentional). Pro entitlements unlock unlimited protocols, full analytics + HealthKit correlation + export, all widgets, and (per `ROADMAP.md`) Apple Watch, CloudKit sync, and AI insights when those ship.

The architectural decisions are made. **Your job is to optimize what ships, not to redesign.**

User-first ethos is non-negotiable: no fake urgency, no medical-coercion language, no functionality removed from free that previously worked, no entitlement leaks across re-installs. Every change must pass the test: *"Would I feel good about this as a paying user? Does the free experience still feel complete and trustworthy?"*

## NON-NEGOTIABLE CONSTRAINTS

- **Existing infra is canonical** — extend, don't recreate. Never propose a new product, paywall page, or persistence path when one exists.
- **No coercion of health behaviour** — dose tracking, recommendation safety warnings, and biometric lock are **never** Pro-gated. Health-data integrity is universal.
- **No removing free functionality** to drive conversion — anything previously free stays free
- **No fake countdowns / fake scarcity / fake reviews** — every claim must be true today
- **No advertising of unshipped features** in the paywall — `ROADMAP.md` notes that Watch / cloud sync / AI / community are planned and the paywall "does not advertise them." Preserve this discipline.
- **StoreKit 2 only** — `Transaction.currentEntitlements`, `Transaction.updates` listener, `verificationResult.payloadValue`. No legacy receipt validation, no third-party purchase library.
- **Receipt verification is non-negotiable** — `.unverified` results never grant entitlement. Preserve whatever verification strategy currently lives in `StoreService.swift`.
- **Offline-first entitlements** — cached entitlement state survives airplane mode after a successful restore
- **Free tier**: 3 active protocols, full 208-peptide DB, basic analytics (weekly view), local persistence, dose reminders, 1 widget. **Confirm these from code; don't guess.**
- **All new constants → `StoreService.swift` or a sibling config file** (single source of truth). Don't sprinkle product IDs.
- **All new types → the appropriate `Peptide/Models/` file**
- **No changes to `Peptide/DesignSystem/Components/Glass*.swift`** unless the work *is* a component change
- **Test coverage** — anything touching purchases, entitlements, or trial logic gets coverage in `PeptideTests/`. The `_failTransactionsEnabled` flag in `Products.storekit` is your friend for test scenarios.
- **Localization**: paywall copy, restore copy, trial copy, cancellation save copy — all flows through `Localizable.xcstrings` (10 locales). Hardcoded English in shop copy is a P0 bug.
- **App Store Review compliance** — paywall must show "Restore Purchases" prominently; trial disclosure must include length, post-trial price, and cancellation instructions; subscription terms / privacy URLs reachable.

---

## Phase 0: Inventory the Existing Stack

Read in parallel where possible. State what exists before proposing anything.

### Monetization core (read fully)
1. **`Peptide/Resources/Products.storekit`** — product IDs, intro offers, subscription group `73E561C3-3E5C-4246-BA5E-C40ABB32278D`. Note: monthly trial = 3 days, annual trial = 14 days, lifetime is non-consumable.
2. **`Peptide/Services/StoreService.swift`** (~7.6 KB) — product loading, purchase flow, restore, transaction listener, entitlement source of truth
3. **`Peptide/Services/ReviewPromptService.swift`** — review-prompt timing rules; `recordLaunch()` is called on `.active` scene phase

### Paywall surfaces (find and read fully)
4. Search for the paywall view (likely `Peptide/Features/Profile/Components/` or a dedicated `Paywall/` folder if one exists). Read the full file.
5. **`Peptide/Features/Onboarding/OnboardingView.swift`** — confirm whether onboarding triggers a paywall (per `ROADMAP.md` it shouldn't)
6. **`Peptide/Features/Profile/ProfileView.swift`** — settings entry to subscription management, restore button placement, manage-subscription deep link

### Adjacent systems that monetization touches
7. **`Peptide/App/DataStore.swift`** — the `activeProtocols` filter and any free-tier protocol limit gating
8. **`Peptide/Services/AchievementService.swift`** (14 IDs) — verify no Pro-gated achievements (achievements are universal recognition)
9. **`Peptide/Services/ExportService.swift`** — CSV / JSON export; confirm whether export is Pro-only or free
10. **`Peptide/Services/HealthKitService.swift`** — confirm HealthKit correlation gating posture
11. **`Peptide/Features/Analytics/AnalyticsView.swift`** — the basic vs. full analytics split

### Persistence & migration
12. **`Peptide/Services/SwiftDataRepository.swift`** — entitlement persistence path; `isCloudSyncEnabled` reflection
13. **`Peptide/Services/MigrationService.swift`** — if entitlement state is migrated across app versions, verify
14. **`Peptide/App/PeptideApp.swift`** — entitlement re-validation on `.active` scene phase

### Test coverage
15. **`PeptideTests/`** — grep for `StoreService` / `Transaction` / paywall tests. Note current coverage and gaps.

### Roadmap reality check
16. **`ROADMAP.md`** — confirm which advertised-as-Pro features are actually shipped vs. planned. Any paywall copy promising an unshipped feature is a P0 fix.

After loading, output a **State of the Stack** report:

```xml
<inventory>
  <products count="3">Monthly $9.99 (3-day trial) / Annual $49.99 (14-day trial) / Lifetime $169.</products>
  <free-tier>Confirm protocol cap, peptide DB scope, analytics scope, widget count, reminder behaviour.</free-tier>
  <pro-tier-shipped>What's actually live behind entitlement today.</pro-tier-shipped>
  <pro-tier-advertised>What the paywall currently shows.</pro-tier-advertised>
  <discrepancies>Any "advertised but not shipped" — ROADMAP says paywall must not advertise unshipped.</discrepancies>
  <restore-prominence>Where Restore Purchases button lives; rate visibility 1–5.</restore-prominence>
  <trial-disclosure>Is post-trial price + cancel instructions present?</trial-disclosure>
  <verification-strategy>How StoreService verifies; .unverified handling.</verification-strategy>
  <integration-quality>Score paywall, profile management, onboarding-trial-trigger, review-prompt timing 1–5 each.</integration-quality>
  <test-coverage-gaps>Top 3 missing test scenarios.</test-coverage-gaps>
</inventory>
```

---

## Phase 1: Conversion Trigger Audit

Walk the user journey and identify **natural** "I wish this were Pro" moments — places where upgrading feels welcome rather than imposed.

### Existing trigger points to evaluate
- Hitting the 3-active-protocol cap (the single hardest natural trigger — audit how it's surfaced)
- Trying to view full analytics from the basic analytics screen
- Trying to export (if Pro-gated)
- Adding a second widget
- Opening Watch app for first time (when v2.5 ships)
- Trying to enable HealthKit correlation
- Insight engine showing a teaser that requires Pro
- 30-day-streak / first-cycle-complete moments — natural "you're invested, here's the upgrade" prompt
- Cycle-end summary — "want to see your last 90 days correlated with sleep?"

### Anti-trigger checklist (any YES = redesign needed)
- ❌ Does anything currently feel like a wall, not a window? (Especially: never wall safety warnings, dose logging, or biometric lock.)
- ❌ Does any free flow get *worse* when the user upgrades? (Visual regressions, removed CTAs, etc. — should never happen.)
- ❌ Does the paywall interrupt without invitation? (Cold-launch or post-onboarding pop is a cardinal sin per `ROADMAP.md`.)
- ❌ Is any pricing or trial detail ambiguous?
- ❌ Does any paywall string promise an unshipped feature?

---

## Phase 2: Optimisation Targets

For each stream below, **state what already exists** before proposing changes. Reject any proposal that duplicates shipped work.

### A. Subscription (Monthly + Annual) — refinements only
- Trial conversion: friction in the existing trial flow? Are days-remaining shown unobtrusively?
- Annual is the better economic offering; is the savings-vs-monthly framing clear and accurate ($49.99/yr = $4.16/mo, ~58% off)?
- Grace-period UX when payment fails (`StoreService` should expose a `billingIssue` signal — verify and surface)
- Cancellation save (offer alternate value or downgrade path — *never pressure*)
- Lapse re-engagement: gentle, never punishing; never gate previously-logged dose data
- Pro-only conveniences worth surfacing more prominently (full analytics, HealthKit correlation, export, multiple widgets, eventually Watch / sync / AI per roadmap)

### B. Lifetime ($169) — positioning
- Lifetime is a strong commitment-signal product. Is it framed as the conviction option ("if you're going to use this for years")?
- Math transparency: lifetime breakeven vs. monthly ($169 / $9.99 = ~17 months) and vs. annual ($169 / $49.99 = ~3.4 years) — surface honestly.
- Is it priced for the "serious user" segment without becoming the default conversion path? (Lifetime cannibalises subscription LTV — it's a positioning lever, not a primary path.)
- Surface as an upsell on cancellation save ("you've cancelled twice — want to be done with the question?")

### C. Free Tier Hygiene
- 3-protocol cap: is the limit message helpful or a wall? Does it suggest pause/complete-old-cycle as alternatives?
- Peptide DB — fully searchable on free? (It should be — knowledge access is universal.)
- Notifications — fully functional on free? (Should be.)
- Achievements — universal? (Should be — they're recognition, not a Pro feature.)
- Biometric lock + Sign in with Apple — universal? (Both are trust features, never gate them.)
- Export CSV/JSON: is it Pro? If so, does that survive App Store data-portability scrutiny? Consider letting free users export their *own* data even if power-user formats (PDF reports, multi-protocol bundles) are Pro.

### D. Paywall Copy & Layout
- Does the paywall enumerate "what you get" clearly per tier?
- Does it explicitly state "if you cancel, you keep all your logged data"? (Critical for health-app trust.)
- Trial disclosure (Apple ToS): trial length, auto-renewal terms, post-trial price, cancellation steps reachable from Settings.
- "Restore Purchases" button — prominent on every paywall surface AND in Profile settings, never buried
- Privacy policy + terms URLs reachable
- Localized in all 10 locales — walk the `Localizable.xcstrings` keys for shop copy

### E. Conversion Hygiene
- Receipts re-validated on `.active` scene phase, not only on purchase
- Manage-subscription deep link uses `Environment(\.openURL)` to `https://apps.apple.com/account/subscriptions` (or the StoreKit 2 `manageSubscriptions` API)
- `transactionUpdatesTask` lifecycle — started in `StoreService.init`, never cancelled prematurely
- Test the StoreKit configuration scheme (`storeKitConfiguration: Peptide/Resources/Products.storekit`) covers: success, fail, refund, expire, billing issue, family sharing
- `_failTransactionsEnabled` enabled in tests for failure-path coverage

### F. Review Prompt Timing (`ReviewPromptService`)
- Currently `recordLaunch()` on `.active`. What's the trigger condition for prompting? (Most likely launch-count + days-since-install + at least one logged dose.)
- Never prompt at frustration moments (after a failed save, dropped notification, recommendation warning, purchase failure)
- Prompt at peak satisfaction (logged a dose + just hit a streak milestone + no recent errors)
- Verify: never prompt during onboarding, during paywall, during a cycle-end summary

### G. Future Pricing Hooks (don't propose now, but flag if missing)
- Family Sharing flag on subscriptions — currently `familyShareable: false`. Is this intentional? (Health data privacy — likely yes, but verify with the user.)
- Promo offers / introductory offers via App Store Connect (lapsed-user winback, etc.) — outside this audit's scope but flag if `StoreService` couldn't accept one if added

---

## Phase 3: Trust & Compliance Verification

> **Trace each claim to its code reality before answering.** Mark `[NEEDS VERIFICATION]` if you can't see it.

Hard checks (must hold):
- ✅ Free user can log doses, hit streaks, get safety warnings, use biometric lock, sign in with Apple
- ✅ Free user keeps all their logged data if they never upgrade
- ✅ Pro user keeps all their logged data if they cancel
- ✅ Restore Purchases works without an Apple ID re-prompt for users with a valid prior purchase
- ✅ Receipt verification rejects `.unverified` results
- ✅ Trial disclosure complies with Apple's auto-renewable subscription guidelines
- ✅ Paywall does not advertise unshipped features (per `ROADMAP.md`)
- ✅ No medical-claim language anywhere in shop copy

Then re-state the rule: monetization knobs live in `StoreService.swift` + `Products.storekit`. If a proposal requires changing the recommendation engine, dose-tracking flow, or notification behaviour, **reject it**.

---

## Phase 4: Pricing & Positioning Hygiene

### Benchmarks (genre)
- MyFitnessPal Premium ($19.99/mo, $79.99/yr) — broad health tracking
- AutoSleep, Bevel, AllTrails+ ($9.99–29.99/yr) — single-purpose health/lifestyle
- Streaks ($4.99 one-time) — habit, premium one-time
- Things 3 ($49.99 one-time per platform) — productivity, premium one-time
- Heads Up Health ($79.99/yr) — closest niche peer

### For each product currently in the catalogue
- Is the US price competitive for the value delivered today (not promised tomorrow)?
- Is regional pricing handled by the App Store (it should be — never hardcode prices in copy; always read from `Product.displayPrice`)
- Is the value prop visible *before* the purchase modal (i.e. on the upsell tile that drives the user there)?
- Is "what you get" enumerated, with no hidden gotchas?
- Is "what you keep if you cancel" explicit?

---

## Phase 5: Implementation Plan

For every change, format as:

```xml
<change priority="P0|P1|P2" effort="S|M|L">
  <name>Specific change name</name>
  <category>Subscription | Lifetime | Free Tier | Paywall Copy | Conversion Hygiene | Review Prompt | Localization | Test Coverage</category>
  <existing-infra>Files this extends — be specific.</existing-infra>
  <new-work>What's actually new (lines of code or new file).</new-work>
  <user-benefit>What the paying user gets. What the free user gets.</user-benefit>
  <trust-impact>Any change to perceived trustworthiness (must be neutral or positive).</trust-impact>
  <risk>What could regress (purchase failures, restore broken, advertising unshipped features, dark-pattern slide).</risk>
  <test>Specific test to add in PeptideTests/.</test>
  <localization>xcstrings keys added or changed; locales requiring new translations.</localization>
</change>
```

Priorities:
- **P0** — trust / compliance bugs (paywall advertises unshipped feature, restore broken, trial disclosure incomplete, receipt-verification gap, hardcoded English in shop copy)
- **P1** — measurable conversion / retention lift with low risk
- **P2** — polish, future surface area

Sort P0 → P2, then S → L within each tier.

---

## Phase 6: Build Phase 1 of the Plan

Implement P0 fixes only in this session (P1+ require user sign-off because they touch user-visible UX). For each:

1. Read the file (if not loaded)
2. Make the surgical change — never refactor surrounding code
3. Add or extend the relevant test
4. Update `Localizable.xcstrings` if any user-visible string changed; flag locales needing translation review
5. State: `"Implemented [name]. Touched: [files]. Test: [name]. Localization keys: [list]."`

Run:

```
swiftlint --strict
xcodebuild test -scheme Peptide -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PeptideTests
```

before marking done.

---

## Deliverables

1. **Inventory report** — what already ships, free vs. Pro reality
2. **Discrepancy list** — anything advertised that isn't shipped
3. **Conversion-trigger map** — where the natural triggers live
4. **Stream-by-stream recommendations** — extending shipped infra only
5. **Trust & compliance proof** — every recommendation passes the hard checks
6. **Pricing & positioning hygiene checklist** — pass/fail per product
7. **P0 fixes implemented** — with tests + localization, suite green
