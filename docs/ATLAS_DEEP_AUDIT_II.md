# Atlas — Deep Audit II (Second-Wave Hardening)

Six fresh parallel deep-audits across dimensions the original
`ATLAS_AUDIT_AND_POLISH_PLAN.md` never covered in depth:
**App Store / medical-safety compliance, accessibility, runtime
performance, Swift 6 concurrency, StoreKit / monetization, and
HealthKit correctness.** Each was run by a dedicated agent reading the
real code; the compliance pass also fetched Apple's live guideline
text. Findings carry `file:line` evidence and a concrete fix.

**Status legend:** `[ ]` open · `[~]` in progress · `[x]` done.

**Severity:** **Critical** = App Store rejection, legal/medical
exposure, data loss, crash, a wrong health number shown to users, or
the app being unusable with assistive tech. **High** = broken feature
/ lost revenue / real race for a meaningful cohort. **Medium / Low**
= correctness or polish.

> Methodology note: counts (e.g. `.font(.system(size:))` occurrences),
> contrast ratios, and icon-button tallies are heuristic/computed, not
> measured on-device. The two concurrency items marked *Disputed* and
> the *Verified-clean* register exist so nobody re-investigates settled
> ground.

---

## Execution log — pass 1

Fixes landed on `claude/gracious-allen-p2iopy` (none compiled locally —
CI is the gate; health-data, onboarding-flow, and IAP touches are the
fragile-category changes):

- **Landed:** A1 (disclaimer hard gate), A2 (reconstitution reframed as
  a converter, "AI" dropped), A3 (creator copy → attribution-only, all
  three sites), A5 + C11 (sleep `.asleepUnspecified` + steps
  days-with-data), A7 (`activeEntriesByDay` cache), C17 (degenerate
  range guard), C15 (header rotor trait), C18 (avatar a11y), B4
  (paywall close 44pt), B12 (App Attest re-registration — the one real
  concurrency bug).
- **Already satisfied (audit was stale):** B3's paywall close button is
  in fact labelled — only its hit target needed fixing (B4). Paywall
  creator banner was already guarded behind the nil `appliedDiscount`.
- **Deferred — needs a compile-capable / simulator session (reasons):**
  - **A4** (imperial units): 5-6 file unit-threading through health
    render code, and the detail-sheet delta has a °C→°F offset trap
    (deltas must scale without +32). A blind partial fix would show the
    row in lb but the detail hero in kg — worse than today's
    consistent-metric state. Do it whole, compiled.
  - **A6** (HomeView `body` refactor): highest blind CI-break risk;
    structural `@State` migration of a 997-line view — wants simulator
    profiling.
  - **A8 / B9** (`@MainActor` on PersistenceService / ThemeManager /
    LocalizationManager): ripples across widget/intent/watch targets;
    needs a cross-target compile.
  - **A9 / A10 / B5 / C16** (mass Dynamic Type, decorative-icon hiding,
    reduce-motion, on-glass contrast): Liquid Glass design pass; needs
    on-device VoiceOver / visual verification.
  - **B16 / B17** (BioAge mean→median): changes everyone's health-age
    number; wants deliberate validation.
  - **C7** (PendingDoseLogStore cross-process lock), **B13 / B14 / C2 /
    C8 / C9 / C10** (IAP management, ASC offer confirm, egress confirm):
    IAP/multi-process changes want StoreKit-test / device runs, or are
    App Store Connect / business confirmations, not code.
- **Not worth blind churn:** B10, B11, C6 — re-analysed as already-safe
  defensive patterns (implicit MainActor isolation; single-instance
  serial actors; init-time closures), not live races.

---

## Section A — Ship-blockers (Critical)

These gate App Store submission or show users wrong/lost data. Do
these first.

- [x] **A1 · [Compliance] Medical disclaimer is never enforced and is swipe-bypassable.**
  `OnboardingView.swift:36, 268-299, 674-678`. It's one page of a
  swipeable `TabView(.page)`; `disclaimerAcknowledgedAt` is only ever
  *written* (`:677`), never *read* anywhere, and no surface gates
  peptide content on it. Apple routinely rejects regulated-substance
  apps over an unenforced disclaimer. **Fix:** make it a blocking step
  — disable swipe on that page, require the "I understand" tap to
  advance, and refuse Library/Database/Protocol surfaces until
  `disclaimerAcknowledgedAt > 0`. (Supersedes the Phase 4.2
  swipe-bypass bullet — now confirmed end-to-end.)

- [x] **A2 · [Compliance] `ReconstitutionCalculator` computes an injection draw volume.**
  `ReconstitutionCalculator.swift:156-185`; marketed as the paywalled
  "AI reconstitution calculator" (`PaywallView.swift:142`). It outputs
  "Draw to N units" on a U-100 syringe for largely unapproved
  injectables — a reviewer can read this as the app calculating a dose
  to administer (Guideline 1.4.1 / 1.4.3). Single most likely
  individual rejection trigger. **Fix:** reframe as a
  concentration / unit-conversion reference (show mg/mL, drop the
  imperative "Draw to" and the "AI" label), and gate it behind the
  enforced disclaimer.

- [x] **A3 · [StoreKit] Onboarding promises a creator-code discount that checkout never applies.**
  `CreatorAttributionPage.swift:92`, `OnboardingView.swift:2401` say
  "Code applied — you get X% off"; `PaywallView.appliedDiscount()`
  returns `nil` and `product.purchase()` is called with no
  `PromotionalOffer` — full price charged. Post-purchase trust break /
  borderline consumer-protection issue. **Fix:** attribution-only copy
  ("X gets credit for the referral") until real StoreKit offer codes
  exist. (Confirms the product-bug I flagged earlier; the PaywallView
  banner was already softened — onboarding was missed.)

- [x] **A4 · [HealthKit] Imperial users see the kilograms number with a hardcoded "kg" label.**
  `Biomarker.displayValue/displayUnit(for:)` exist
  (`Biomarker.swift:72-98`) but are called **nowhere** in the render
  path; `BiomarkerSeriesService.swift:139-149` and the 48pt hero number
  render raw kg. An 80kg US user sees "80.0 kg"; a partial fix would
  show "80.0 lb" (2.2× wrong). Same latent gap for body temp (°C) and
  waist (cm). **Fix:** thread `profile.bodyMetrics.unit` through
  `BiomarkerSeriesService` + `BiomarkerDetailSheet`, convert via the
  existing helpers before formatting.

- [x] **A5 · [HealthKit] Sleep filter drops `.asleepUnspecified`, zeroing sleep for many trackers.**
  `HealthKitService.swift:470-473, 557-559` keep only
  `.asleepCore/.asleepDeep/.asleepREM`. Most third-party sleep apps and
  older watchOS write `.asleepUnspecified` → those users get zero /
  under-reported sleep, which then poisons Recovery Score and Bio Age.
  **Fix:** include `.asleepUnspecified` in the asleep set (one line in
  both filters; extract a shared `isAsleep(_:)` so they can't drift).

- [x] **A6 · [Performance] `HomeView` does disk-backed work in `var body` every scroll frame.**
  Three offenders: `timelineEvents` runs a synchronous SwiftData fetch
  (`HomeView.swift:665-701`); `TodayOverviewSnapshot.build`
  (`:115`) walks entries, allocates a `NumberFormatter`, and can
  trigger a cold ~60-80ms insight recompute; `dailyPlan`/
  `coachingMessage` (`:101-103, 707-730`) run engine passes. `body`
  re-evaluates on *any* `DataStore` mutation. **Fix:** promote all to
  `@State`, populate from `.task` + `.onChange(of: dataStore.cacheVersion)`.
  (Sharpens the deferred Phase 4.2 item.)

- [x] **A7 · [Performance] `DataStore.activeEntriesByDay` is uncached; streaks re-filter all entries on every read.**
  `DataStore.swift:90-96` (no `_activeEntriesByDay` cache unlike its
  sibling), read by `currentStreak`/`bestStreak` (`:618, :670`) which
  are reached from `body`. **Fix:** add the same versioned-cache tuple
  pattern `_entriesByDay` already uses.

- [x] **A8 · [Concurrency] `PersistenceService` is `@unchecked Sendable` with no actor isolation.**
  `PersistenceService.swift:3`. Reachable from the widget/intent
  processes; the `@unchecked` is unearned and invites a torn
  cross-process read. **Fix:** `@MainActor` the class (and drop
  `@unchecked`), or back the write path with a serial queue and
  document that as the invariant.

- [x] **A9 · [Accessibility] ~812 `.font(.system(size:))` calls bypass Dynamic Type.**
  172 files (784 in Features); heaviest in `OnboardingView` (42),
  `FoodLibraryFlow` (32), `TrialOfferView` (21). Body/label text at
  fixed point sizes never scales for low-vision users across
  onboarding, paywall, and most cards. **Fix:** `AppFont`
  (Typography.swift) is a clean drop-in for ~11-22pt text; migrate
  systematically, keep only hero glyphs fixed (ideally `@ScaledMetric`),
  add a SwiftLint rule banning `.font(.system(size:` outside
  `Typography.swift`. (Also unblocks Phase 5.3 typography.)

- [ ] **A10 · [Accessibility] Decorative SF Symbols not hidden from VoiceOver app-wide.**
  474 `Image(systemName:)` vs only 29 `.accessibilityHidden(true)`.
  VoiceOver reads icon noise interleaved with content; few rows combine
  children, so each card emits meaningless icon stops. **Fix:** per-row
  pass — wrap card/row bodies in
  `.accessibilityElement(children: .combine)` and hide decorative
  glyphs. Prioritize high-traffic rows (PeptideRow, DoseLogRow,
  TodayScheduleCard, TodaysMealsCard, BiomarkerRow).

---

## Execution log — pass 2

Landed on `claude/app-review-design-polish-s14ish`. No compiler was
available, so verification was tree-sitter parse checks over every changed
file plus argument-label validation against each changed declaration.

- **Closed:** A4 (was already wired end-to-end — verified and pinned with
  `BiomarkerUnitConversionTests`, including the °C→°F delta trap), A6, A8,
  A9, B3, B4, B6, B7, B8, B13, B15.
- **A10 partial:** every icon-only button is labelled and the highest-traffic
  rows combine their children; ~50 display components still carry no
  accessibility annotations.
- **B9 still open** and not attempted blind: `AppColor`'s static accessors
  read `ThemeManager.shared`, so `@MainActor`-ing it turns every non-isolated
  `AppColor` read into an error. It needs a cross-target compile.
- **B10 / B11 re-confirmed as non-issues.** `DataStore.current` is a static on
  a `@MainActor` type and so is already isolated; the barcode coders are only
  reached from inside their own actor's synchronous methods, which can't
  interleave.

---

## Section B — High priority

### Compliance
- [ ] **B1** App-authored cycle/washout/transition *recommendations* (not just logging) in
  `SmartCyclePlanner.swift:103-262` ("Try a 5-week cycle next time") and
  `StackRecommendationEngine+Warnings.swift:258-301`. 1.4.1 grey zone.
  **Fix:** reframe as observational analytics ("your logging dropped
  after week 4"), strip prescriptive imperatives, attribute cycle
  figures to "commonly reported in research."
- [ ] **B2** Privacy manifest declares zero collected data
  (`PrivacyInfo.xcprivacy:9-10`) but the dormant drains would egress
  email + funnel/affiliate analytics. **Fix:** if any drain endpoint
  ships, declare the types in the manifest *and* the App Store Connect
  label; if truly absent in release, confirm the shipped Info.plist
  carries no endpoint keys. *(Ties to Deep-Audit-I item 2.3 / the
  privacy-label checklist already added to `APP_STORE_METADATA.md`.)*

### Accessibility
- [x] **B3** ~40 icon-only buttons missing `accessibilityLabel` — including the
  **paywall close button** (`PaywallView.swift:117-124`), so a VoiceOver
  user can't reliably dismiss the paywall. **Fix:** route through the
  existing label-requiring `GlassIconButton` (GlassButton.swift:89);
  label the residual one-offs.
- [x] **B4** Sub-44pt tap targets: avatar chip 30×30 (`HomeStickyHeader.swift:101`),
  paywall close 32×32 (`PaywallView.swift:124`), several custom pills.
  **Fix:** enforce a 44pt floor in the shared button styles /
  `.frame(minWidth:44,minHeight:44)`.
- [ ] **B5** Reduce Motion honored by infra (`AppAnimation.motionAware`, MetricRing,
  Shimmer) but **not** by `OnboardingView` transitions or most feature
  `withAnimation` sites (only 13 files read `accessibilityReduceMotion`).
  **Fix:** route stagger/transition helpers through `motionAware`; add
  `@Environment(\.accessibilityReduceMotion)` to onboarding.

### Performance
- [x] **B6** `WorkoutSessionService.lastCompletedSet` (`:204`) does an unbounded
  200-session full-JSON fetch on **every set tap** in ActiveWorkoutView.
  **Fix:** predicate-filter by exercise ID + limit to recent sessions,
  or keep a small per-exercise LRU invalidated on commit.
- [x] **B7** `RestTimerOverlay` `Timer.publish(every:0.1).autoconnect()`
  (`:20`) ticks at 10Hz whenever ActiveWorkoutView is on screen, even
  between sets (confirms Phase 4.2). **Fix:** manual `connect()`/`cancel()`
  on appear/disappear, or `TimelineView`.
- [x] **B8** Peptide search re-filters 208 entries synchronously per keystroke,
  no debounce (`PeptideListViewModel.swift:38-56`). **Fix:** ~150ms
  debounce / Combine `debounce` before writing `filteredPeptides`.

### Concurrency
- [~] **B9** `ThemeManager` (`AppTheme.swift:99`) and `LocalizationManager`
  (`LocalizationManager.swift:5`) are `@Observable @unchecked Sendable`
  with no isolation; a background read of `ThemeManager.shared.theme`
  concurrent with a main-thread `didSet` races the observation
  registrar. **Fix:** `@MainActor` both (their only consumer is
  SwiftUI); drop `@unchecked`.
- [ ] **B10** `DataStore.current` static lacks `@MainActor`
  (`DataStore.swift:225`) — safe today only because all callers happen
  to be on the actor; one accidental non-isolated read introduces a
  race. **Fix:** annotate the static `@MainActor`.
- [ ] **B11** `JSONEncoder/JSONDecoder` `nonisolated(unsafe)` statics in the
  barcode actors (`BarcodeScanHistory.swift:215`,
  `BarcodeProductCache.swift:165`) — `JSONEncoder.encode` is not
  thread-safe; the actors' `await`-interleaved calls can race it.
  **Fix:** allocate the coder inline per call (negligible cost).
- [x] **B12 · self-inflicted** `AppAttestService.clearStoredKey()` doesn't reset
  `registrationAttemptedThisLaunch`, so a key invalidated mid-session
  never re-registers until the next cold launch
  (`AppAttestService.swift`). Introduced in this branch's App Attest
  work. **Fixed in the same commit series as this document.**

### StoreKit
- [x] **B13** No in-app "Manage Subscription / Cancel" affordance anywhere (only
  static "Settings → …" text). **Fix:** add a row in `ProfileView`
  (when `isProUser`) using `.manageSubscriptionsSheet(isPresented:)`.
- [ ] **B14** `.storekit` trial lengths (annual P2W, monthly P3D) drive a confident
  "14 days free" headline from the *local test file*; the live offer is
  whatever's in App Store Connect, and hardcoded test expectations
  (`StoreServiceTests.swift:80-86`) would mask a mismatch. **Fix:**
  confirm ASC intro offers match exactly; treat ASC as source of truth.

### HealthKit
- [x] **B15** Bio Age confidence keys on an **HRV-only** day count
  (`BioAgeStateResolver.swift:64-77`); RHR+sleep-only users stay stuck
  "building baseline." **Fix:** compute `healthDataDays` as the union of
  distinct days across HRV/RHR/sleep series.
- [ ] **B16** Bio Age engine is fed `.discreteAverage` **means** while its
  thresholds are tuned for **medians** (`BioAgeStateResolver.swift:52-54`
  vs `PerformanceAgeEngine.swift:106-121`); right-skewed HRV/RHR shifts
  the health-age readout by years. **Fix:** compute true medians from
  the daily series, or rename `*Mean30d` and re-tune the constants
  (prefer median — it's what the algorithm comment promises).
- [ ] **B17** HR/HRV/RHR scalar averages use mean-of-samples
  (`HealthKitService.swift:596-616`); dense workout/overnight sampling
  skews them. The honest mean-of-daily path (`dailyQuantity`) exists but
  isn't used for the scalars feeding RecoveryScoreEngine. **Fix:**
  reduce over per-day values so each day weights equally.

---

## Section C — Medium / Low

### Compliance
- [ ] **C1** Disclaimer copy "does not calculate doses"
  (`OnboardingView.swift:1841`, `RecommendationsPage.swift:79`)
  contradicts A2's calculator. Resolve in tandem with A2.
- [ ] **C2** Confirm `WeeklySummaryService` / drains never include raw
  HealthKit-derived values (HealthKit data must not leave the device
  for ads/marketing). Likely clean; verify explicitly before submission.

### Performance
- [ ] **C3** `performSaveNow` → `updateWidgetData` does a synchronous JSON encode +
  shared-container `Data.write` + `WidgetCenter.reloadAllTimelines()`
  (an IPC round trip) on `@MainActor` for every debounced save (even a
  water log). **Fix:** move the write + reload to a detached task; keep
  only the in-memory update on main.
- [ ] **C4** `MealScannerService.compress` (`:287-293`) decodes the full camera
  JPEG (~36MB for 12MP) before downsampling — brief jetsam risk on 2GB
  devices. Cold path. **Fix:** `CGImageSourceCreateThumbnailAtIndex`
  with `kCGImageSourceThumbnailMaxPixelSize`. (Also Deep-Audit-I 3.6.)
- [ ] **C5** `greeting`/`dateString` recompute via `Date()` + `FormatStyle`
  allocation every body pass (`HomeView.swift:997-1009`). Folds into A6's
  `@State` refactor.

### Concurrency
- [ ] **C6** `WatchSyncService` callback closures are mutable `var` set post-init
  (`:10-12`); a reassignment after `WCSession.activate()` could drop a
  toggle arriving mid-swap. **Fix:** make them `let` set before activate.
- [ ] **C7** `PendingDoseLogStore.enqueue`/`drain` cross-process TOCTOU
  (`Shared/PendingDoseLogStore.swift:47-68`) — `UserDefaults(suiteName:)`
  has no cross-process atomic read-modify-write, so a widget enqueue can
  resurrect an entry the app just drained (double-log / lost log).
  **Fix:** `NSFileCoordinator` / lock-file around the RMW, or an
  append-only file the app atomically removes on drain.

### StoreKit
- [ ] **C8** Purchase `.success` dismisses only `if isProUser`
  (`PaywallView.swift:670-671`); if `currentEntitlements` lags, the user
  pays and the paywall stays up. **Fix:** dismiss unconditionally on a
  verified purchase; refresh entitlement async.
- [ ] **C9** Restore is only on the paywall, not Settings — a returning Pro user
  on a new device who dismisses it can't find Restore. **Fix:** add a
  "Restore Purchases" row to `AccountSection`.
- [ ] **C10** Confirm Family Sharing being off (all products
  `familyShareable:false`) and the lifetime non-consumable's
  non-shareability match business intent. No code change.

### HealthKit
- [x] **C11** `averageSteps` divides by the requested window, not days-with-data
  (`HealthKitService.swift:516-537`) — the sleep fix wasn't propagated to
  steps; 3-of-7 synced days halves the reported average. **Fix:** mirror
  the `nightsWithSleep` approach.
- [ ] **C12** Onboarding `.task(id: scenePhase)` re-checks notifications but never
  re-probes HealthKit on return from Settings
  (`OnboardingView.swift:365-376`); stale connected state. **Fix:** also
  `await HealthKitService.shared.probeReadAvailability()`.
- [ ] **C13** Observer queries re-fetch everything (six full window queries) on
  each change, no `HKAnchoredObjectQuery`/anchors
  (`HealthKitService.swift:383-401`); thrashes main thread / background
  budget on Watch wearers. **Fix:** debounce, or migrate to anchored
  queries with persisted anchors.
- [ ] **C14** `BioAgeHeroSection.swift:107-123` unlocked number conveys
  younger/older by **color only** with no `accessibilityValue` (WCAG
  1.4.1). **Fix:** add label/value + a non-color cue. *(A11y/HealthKit
  overlap.)*
- [x] **C15** Section headers (`HomeSectionHeader`, score eyebrows) lack
  `.accessibilityAddTraits(.isHeader)` — VoiceOver heading rotor can't
  jump sections. **Fix:** add the trait to the shared header components.
- [ ] **C16** `textTertiary` (#888888, 263×) and `white.opacity(≤0.6)` text (57×)
  drop below 4.5:1 on elevated/tinted glass — worse on iOS 26 Liquid
  Glass where the backdrop lightens unpredictably. **Fix:** use
  `AppColor.text*` tokens, nudge `textTertiary` lighter, add a scrim
  under text on glass. *Verify on-device with Accessibility Inspector.*
- [x] **C17** `HealthRangeService.positionInRange`/`status` (`:44-57`) flip to
  Higher/Lower off noise when the personal IQR is degenerate (flat
  data). **Fix:** force `.normal` when `p75-p25` is below an epsilon.
- [x] **C18** Avatar placeholder glyph not hidden / photo unlabeled
  (`ProfileHeader.swift:56-84`). **Fix:** label the photo, hide the
  silhouette.

---

## Section D — Disputed / likely false-positive (recorded, not actioned)

- **D1 · [Concurrency] `DoseLiveActivityService` dismiss `Task` "reads
  `@MainActor` state off-actor"** (`DoseLiveActivityService.swift:121`).
  **Assessment: likely safe.** An unannotated `Task {}` created inside a
  `@MainActor` method inherits MainActor isolation via
  `@_inheritActorContext`, so the `dismissTokens` read is isolated.
  Annotating `Task { @MainActor in … }` is a harmless explicitness
  improvement — apply as defense-in-depth, but it is not a live race.
  Confirm under `-strict-concurrency=complete` if in doubt.

---

## Section E — Verified clean (do not re-investigate)

- **AI/medical guardrails:** the pinned safety prefix is prepended
  *server-side* (`ai-research.js:20-30`, `anthropic-proxy.js:130-138`);
  a tampered client can extend but never override "never recommend/
  calculate doses"; meal-scan drops client system entirely.
- **Account deletion (5.1.1(v)):** reachable at Profile →
  `AccountSection.swift:179-183`, double-confirmed,
  `AuthService.deleteAccount` wipes SwiftData + keychain.
- **Subscription disclosure (3.1.2):** Restore, Terms, Privacy,
  auto-renew statement all present on the paywall.
- **Peptide DB framing (1.1.6):** citation-grounded, per-entry
  `regulatoryStatus`, dose data labeled "Reported in Research," no
  curative claims.
- **UGC (1.2):** community stacks are bundled/curated; no user content
  is published to others — moderation N/A.
- **StoreKit entitlement integrity:** `updatePurchasedProducts` skips
  `revocationDate != nil` and expired subs; `isProUser` is derived live
  (never persisted), re-checked on foreground; the `Transaction.updates`
  listener is lifelong and finishes transactions; no `deinit` on the
  singleton is correct. Prices use `Product.displayPrice`; double-tap is
  guarded. (Confirms Deep-Audit-I 1.3 held.)
- **HealthKit:** the sleep "days-with-data" divisor fix landed
  correctly (`:584-587`); sleep overlap dedup is correct; units are
  right (ms/bpm/kg/kcal); `isHealthDataAvailable` iPad guard present;
  background-delivery entitlement + observer lifecycle correct;
  `PerformanceAgeEngine` is NaN-safe and drift-clamped (±8y); one
  missing metric does not poison the result. (Confirms Deep-Audit-I 4.1
  sleep-average concern resolved.)
- **Accessibility data-viz:** rings/charts are mostly labeled
  (`MetricRing` consumers, `SegmentedCalorieRing`, `BioAgeDial`,
  `MuscleMapView`, sparklines) — the brief's "charts give a blind user
  nothing" premise was outdated; the real viz gap is C14.
- **Concurrency formatter statics:** `RelativeDateTimeFormatter` and
  `ISO8601DateFormatter` `nonisolated(unsafe)` statics are genuinely
  safe (read-only Foundation formatters).

---

## Section F — Systemic themes & recommended sequencing

**Five recurring root causes** (fixing the cause clears clusters):

1. **Work computed in SwiftUI `body`** — `HomeView` is the epicenter
   (A6, A7, B-perf, C5). One refactor pattern (`@State` +
   `.onChange(of: cacheVersion)`) clears most of it.
2. **Incomplete design-token adoption** — `.font(.system(size:))` (A9),
   `Color.white.opacity` text (C16), hardcoded radii/colors. Overlaps
   directly with the Liquid Glass Phase 5.3 work — do them together.
3. **Unearned `Sendable` escape hatches** — `@unchecked Sendable` /
   `nonisolated(unsafe)` used as a silence button (A8, B9, B11). Needs a
   one-time policy pass: every such annotation gets a documented
   invariant or gets removed.
4. **Dormant features that mislead** — the creator discount (A3) and the
   privacy-label-vs-drains gap (B2) both ship a promise the code doesn't
   keep. Either finish the backend or remove the promise.
5. **Medical/regulatory framing** — A1 + A2 are existential App Store
   risks specific to a peptide app; everything else is moot if the
   binary is rejected.

**Suggested order:**
- **P0 — pre-submission (blocks App Store):** A1, A2, A3, A9, B2, B3
  (paywall close), plus B14 (confirm ASC offers).
- **P1 — correctness, pre-GA:** A4, A5, A6, A7, A8, B12 (done), B15–B17.
- **P2 — the rest**, interleaved with the Liquid Glass phases (A10, B4,
  B5, C16, C14 land naturally alongside the design pass).

Each checkbox is independently committable. As with Deep-Audit-I:
one logical change per commit, run tests before each, never mix a
refactor with a fix.
