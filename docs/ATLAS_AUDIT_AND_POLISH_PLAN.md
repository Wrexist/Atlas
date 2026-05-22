# Atlas — Full App Audit & Liquid Glass Polish Plan

Synthesised from six parallel deep audits (services/data bugs, feature-view
bugs, security, error handling, UI/UX & Liquid Glass design, code quality).
Every item carries a file reference and a concrete fix. Phases are ordered by
risk: data-integrity and crashes first, design polish later, cleanup last.

**Status legend:** `[ ]` not started · `[~]` in progress · `[x]` done.

---

## Phase 0 — Build baseline & safety net

Nothing in the recent branch history is compile-verified. Establish a green
build before changing anything else.

- [ ] **0.1** Run `xcodegen generate` then a clean build for an iOS 18
  simulator. Fix any compile errors before proceeding.
- [ ] **0.2** Run the existing `PeptideTests` suite; record current pass/fail
  baseline so regressions are visible.
- [ ] **0.3** Verify the three Swift-6 concurrency risk spots flagged in
  `HANDOFF.md`: `MealScannerService`/`AIResearchService` payload casts,
  `HomeView` `liquidGlassPresentation(detents:)`, `DoseLiveActivityService`
  `Color.cgColor`.
- [ ] **0.4** Create a feature branch off `claude/app-audit-polish-plan-76Uvg`
  for each phase, or land phases as discrete commits.

---

## Phase 1 — Critical correctness & data integrity

These either lose user data, crash, or break a headline feature for 100% of
users. Do this phase first.

### 1.1 CloudKit sync is dead for the entire user base — `[x]`
**Files:** `Peptide/Data/SwiftDataModels.swift`,
`Peptide/Data/SwiftDataModels+Training.swift`,
`Peptide/Services/SwiftDataRepository.swift:135-151`

CloudKit-backed SwiftData requires every non-relationship attribute to be
optional or have a default. All 7 `@Model` types (`StoredProtocol`,
`StoredEntry`, `StoredProfile`, `StoredWorkoutSession`, `StoredCustomExercise`,
`StoredRoutine`, `StoredPersonalRecord`) declare non-optional, no-default
stored properties. `makeCloudContainer()` therefore throws at init and silently
falls back to a local-only store — iCloud sync never works, yet the UI
advertises it.

- [ ] Give every stored attribute an explicit default or make it optional
  (e.g. `var id: UUID = UUID()`, `var name: String = ""`,
  `var completed: Bool = false`, `var peptideData: Data = Data()`).
- [ ] Confirm no `@Attribute(.unique)` remains (CloudKit-incompatible).
- [ ] Verify a CloudKit container actually opens after the change; only then
  is the upsert/merge/identity machinery in `SwiftDataRepository` live.
- [ ] If a SwiftData store already exists from older builds, add a lightweight
  migration plan so existing local stores open cleanly.

### 1.2 `entry.notes != nil` is always true → stale dose duplication — `[x]`
**File:** `Peptide/App/DataStore.swift:533`

`ProtocolEntry.notes` is a non-optional `String`; the regenerate-guard
predicate `entry.notes != nil` is always true, so every today-entry is treated
as "user-logged" and survives schedule regeneration, producing duplicate/stale
dose rows when a protocol's schedule is edited.

- [ ] Change to `!entry.notes.isEmpty`.
- [ ] Confirm `actualDose != nil` siblings are genuine optionals (they are) and
  leave them.
- [ ] This should already emit a compiler warning — confirm Phase 0 surfaces it.

### 1.3 Revoked/expired StoreKit entitlements still grant Pro — `[x]`
**File:** `Peptide/Services/StoreService.swift:185-199`

`updatePurchasedProducts` inserts every `Transaction.currentEntitlements`
productID without checking `revocationDate` or `expirationDate`. Refunded
lifetime IAPs and revoked subscriptions keep full Pro access indefinitely.

- [ ] Skip entitlements where `revocationDate != nil`.
- [ ] Skip subscription entitlements where `expirationDate < Date()`.

### 1.4 SwiftData live-save failures are silently swallowed — `[x]`
**Files:** `Peptide/Services/SwiftDataRepository.swift:782-789` (`commit()`),
`Peptide/App/DataStore.swift` (`performSaveNow`, `lastError` at line 17)

`commit()` catches `try context.save()` errors and only logs them. A dose
logged when the disk is full / device locked / CloudKit conflicts is lost with
no UI signal. `lastError` exists but is set only at init.

- [ ] Make `commit()` return `Bool` (or `throws`).
- [ ] In `performSaveNow()`, on failure set `DataStore.lastError` with
  actionable copy and retry once on lock/`fileWriteFileExists` errors.

### 1.5 `lastError` banner is invisible on the main app surface — `[x]`
**Files:** `Peptide/App/DataStore.swift:15-17`, `PeptideApp.swift`

The "Storage unavailable" condition is only rendered in `OnboardingView` and
`Profile/Components/AccountSection.swift`. A user landing on Home never sees it.

- [ ] Surface `lastError` as a persistent banner at the root `TabView`
  container so any data-loss condition is always visible.

### 1.6 Watch `DoseListView` toolbar is outside the `NavigationStack` — `[x]`
**File:** `PeptideWatch/Views/DoseListView.swift:6-27`

`.toolbar { complianceRing }` is chained onto the `NavigationStack`'s result,
not a descendant, so the compliance ring never renders.

- [ ] Move `.toolbar { … }` inside the `NavigationStack` closure.

### 1.7 Duplicate `navigationDestination(for: CommunityStack.self)` — `[x]`
**Files:** `Peptide/Features/Library/StackLibraryView.swift:73-75`,
`Peptide/Features/Protocols/ProtocolListView.swift:134-138`

Two destinations for the same type on one stack → undefined behaviour; the
`ProtocolBuilderView` sheet embedding may have no enclosing stack at all.

- [ ] Remove the destination from `StackLibraryView`; rely on the host stack,
  or always wrap `StackLibraryView` in its own `NavigationStack`.
- [ ] Verify the `ProtocolBuilderView:169` embedding has a navigation host.

---

## Phase 2 — Security hardening

### 2.1 Proxy auth: static shared secret ships in the binary — `[ ]`
**Files:** `server/api/_lib/anthropic-proxy.js:157-163`,
`.github/workflows/ios-testflight.yml:210-260`, `Peptide/Resources/Info.plist`

The only auth gate is a static secret extractable from any `.ipa`. Anyone can
relay to Anthropic on your key.

- [ ] Implement Apple **App Attest** (`DCAppAttestService`): the proxy verifies
  a per-request assertion so only genuine app installs can call it.
- [ ] Treat the shared secret as defense-in-depth only; rotate on a schedule
  (the dual-slot design already supports rotation).

### 2.2 Rate limiter is per-warm-instance and bypassable — `[ ]`
**File:** `server/api/_lib/anthropic-proxy.js:32,70-82`,
`server/api/weekly-summary.js:68-86`

The in-memory `Map` resets on cold start and is per-lambda — "20 RPM per IP" is
not enforced globally.

- [ ] Back the limiter with Vercel KV / Upstash Redis (`INCR` + TTL), keyed per
  IP **and** a global key.
- [ ] Add a hard daily/monthly Anthropic request budget that fails closed
  (503) when exceeded.

### 2.3 Analytics drains exfiltrate PII with no auth/consent — `[ ]`
**Files:** `Peptide/Services/AffiliateIntakeService.swift:22-62`,
`Peptide/Services/OnboardingFunnelTracker.swift:105-143`

`AffiliateApplication` (name, email, handle, channelURL) and funnel snapshots
are POSTed fire-and-forget to operator-set endpoints with no auth, no consent
gate, and only a `scheme == https` check (so `https://attacker.example` passes).

- [ ] Gate both drains behind explicit, informed user consent.
- [ ] Validate the destination host against an allowlist of Atlas domains.
- [ ] Authenticate the intake endpoints (App Attest or rotatable secret) and
  rate-limit them server-side.
- [ ] Update App Store privacy-nutrition labels to disclose PII transmission.

### 2.4 Server-side input & error hygiene — `[ ]`
**Files:** `server/api/weekly-summary.js:93-105,186-192`,
`server/api/_lib/anthropic-proxy.js:198-236`

- [ ] `weekly-summary.js`: build the prompt from an explicit allowlist of
  aggregate fields with type/range checks; reject unknown keys (currently the
  whole object is `JSON.stringify`-ed into the prompt).
- [ ] Collapse upstream Anthropic statuses into generic client codes (e.g. 502)
  so a 401/429 doesn't leak server-side key state. Log the real status only.
- [ ] Enforce the per-route body cap on the parsed body size
  (`Buffer.byteLength`), not the `content-length` header.
- [ ] Add an `AbortController` (~25s) to each upstream `fetch`.

### 2.5 Logging & secret-commit hygiene — `[ ]`
- [ ] `WeeklySummaryService.swift:134-136` — change error log `privacy: .public`
  → `.private` (URL/response fragments leak otherwise).
- [ ] `OnboardingFunnelTracker` — never put emails/codes into event-name
  strings; keep funnel events as fixed identifiers.
- [ ] Add a CI / pre-commit guard that rejects committing
  `MEAL_SCANNER_SECRET` / `AI_RESEARCH_SECRET` / `WEEKLY_SUMMARY_SECRET` values
  into the tracked `Info.plist`; consider `git update-index --skip-worktree`.
- [ ] `MealScannerService.swift:165-170` / `AIResearchService.swift:38-44` —
  require `scheme == "https"` (and ideally a host allowlist) in `urlSetting`;
  return `nil` → `proxyNotConfigured` otherwise.
- [ ] Add an explicit `NSAppTransportSecurity` dict (`NSAllowsArbitraryLoads:
  false`) to `Info.plist`; consider TLS 1.3 minimum for proxy hosts.
- [ ] Confirm creator-code discounts are enforced by Apple (signed promotional
  offers), not the client-side `discountPercent` in
  `CreatorCodeService.swift:15-19`.

---

## Phase 3 — Error handling & resilience

### 3.1 CloudKit sync status surface — `[ ]`
**Files:** `Peptide/Services/SwiftDataRepository.swift:135-151`, Profile settings

- [ ] Track whether the cloud or local container was used; expose a passive
  "iCloud sync unavailable" indicator in Profile.
- [ ] Check `CKAccountStatus` to distinguish "no account" from "quota
  exceeded".

### 3.2 Network resilience for AI surfaces — `[ ]`
- [ ] `MealScannerService.swift:96-147` — add retry-with-backoff for transient
  transport errors / 502-504 (mirror `OpenFoodFactsService.retryableStatuses`);
  add a dedicated `ScanError.offline` case.
- [ ] `MealScanFlow.swift:331` — make the error-card "Try again" retain the
  loaded `image` and re-run analysis instead of dumping back to image picking.
- [ ] `AIResearchService.swift:191-242` — classify `URLError` offline/timeout
  into a dedicated `.offline` case; optional one silent retry on
  `serviceUnavailable` for both the streaming and non-streaming paths.
- [ ] `MealScannerService.swift:229` / `AIResearchService.swift:366` — replace
  `try?` on the envelope `JSONSerialization` with `do/catch` that logs the
  decode error before throwing `.invalidResponse`.

### 3.3 Watch reliability — `[ ]`
**Files:** `PeptideWatch/Services/WatchStore.swift:90-153`,
`Peptide/Services/WatchSyncService.swift:93-113`

- [ ] On the Watch, when `!isReachable`, fall back to
  `WCSession.transferUserInfo` (guaranteed background delivery) instead of
  dropping `logWater`/`toggleEntry`; retry via the same path in `errorHandler`.
- [ ] Decide on `WatchNutritionSnapshot.waterToday` — either add the field so
  the optimistic water update is real, or remove the dead reconstruction block
  (`WatchStore.swift:64-88`).

### 3.4 Crash-safety: replace `precondition` in render/runtime paths — `[ ]`
- [ ] `Peptide/Services/BarcodeProductCache.swift:148-154` — replace
  `precondition` with a graceful guard (sanitize/hash the key, treat a bad key
  as a cache miss).
- [ ] `Peptide/Features/Protocols/Components/CycleBands.swift:46` — replace
  `precondition(grid.count == 42)` with a graceful early-return +
  debug-only `assertionFailure`.
- [ ] `Peptide/Services/ScreenshotSeedData.swift:156` — guard the
  `proto.peptides.first!` force-unwrap (demo-only, low priority).

### 3.5 App Group / pending-dose-log durability — `[ ]`
**File:** `Shared/PendingDoseLogStore.swift`

- [ ] Use `.completeUntilFirstUserAuthentication` file protection so Lock
  Screen "Log Dose" writes succeed while the device is locked.
- [ ] Log write failures rather than swallowing them with `try?`.

### 3.6 Build-integrity & minor fallbacks — `[ ]`
- [ ] Add a CI check asserting `PeptideDatabase.shared.count == 208` so a build
  that drops `peptides.json` (silently falling back to `MockPeptides`) fails.
- [ ] `MealScannerService.compress` — use `CGImageSourceCreateThumbnailAtIndex`
  with `kCGImageSourceThumbnailMaxPixelSize` for bounded-memory downscaling.
- [ ] `WeeklySummaryService.weekStartString:204` — fall back to
  `DateInterval(start: date, duration: 0)` instead of `DateInterval()`.

---

## Phase 4 — High & medium correctness bugs

### 4.1 Services & data-layer bugs — `[ ]`
- [ ] **Streak freeze ignored by dose streaks** — `DataStore.swift:623-706`:
  `currentStreak`/`bestStreak` never consult `StreakFreezeService.isFrozen`;
  the whole streak-freeze feature is non-functional for dose streaks. Mirror
  `LifestyleDataLogic.mealLoggingStreak`'s `isCovered` logic.
- [ ] **Lost save in identity-change window** — `DataStore.swift:173-207`:
  cancel `pendingSaveTask` in `handleIdentityChange` before clearing arrays;
  re-run `performSaveNow()` after `reloadFromDisk` if mutations were pending.
- [ ] **Workout quick-log doesn't refresh widget** — `DataStore.swift:1391-1403`:
  replace the no-op `bumpVersionIfDayChanged()` in `logWorkout`/`deleteWorkout`
  with an explicit `cacheVersion &+= 1` and call `updateWidgetData()`.
- [ ] **Habit reminders can evict dose reminders past the 64 limit** —
  `NotificationService.swift:227-277`: give `scheduleHabitReminders` a combined
  budget with `scheduleNotifications` (reserve a slice / fold into one
  sort-and-prefix pipeline) and surface drops in a report.
- [ ] **Spotlight reindex cancellation race** — `DataStore.swift:1315-1334`:
  make `FoodSpotlightService.reindex` check `Task.isCancelled` internally, or
  serialize reindexes through an actor so last-enqueued wins.
- [ ] **`weekNumber`/`cycleNumber` use `weekOfYear` delta math** —
  `PeptideProtocol.swift:221-234`: switch to day-delta `/ 7` so they agree with
  `CyclePhaseEngine`.
- [ ] **`endDate` vs `cycleEndDay` drift** — `PeptideProtocol.swift:194-207`:
  define `endDate` in terms of `cycleEndDay` (one source of truth, using
  `safeCycleLengthWeeks * 7` days from `startOfDay`).
- [ ] **`DaySlot.from(hour:)` slot collision** —
  `DailyScheduleEngine.swift:83-92`: give 0–5 its own slot (or `.preBed`) so
  doses 16h apart aren't analysed as co-administered.
- [ ] **`SmartCyclePlanner` inconsistent date normalization** —
  `SmartCyclePlanner.swift:109,171,244`: normalize `today` and `startDate` to
  `startOfDay` consistently across all heuristics.
- [ ] **DST time-string parsing fallback** — `DataStore.swift:2004-2022`,
  `NotificationService.parseTime`: handle `date(bySettingHour:)` failure
  explicitly (`.nextTime` matching) rather than `?? Date()`.
- [ ] **`DoseLiveActivity` double-`end` race** —
  `DoseLiveActivityService.swift:95-111`: after `Task.sleep`, re-check the
  stored task token identity before calling `activity.end`.
- [ ] **`WatchSyncService` sort predicate** — `WatchSyncService.swift:65`:
  replace the non-strict-weak-ordering closure with a proper comparator
  (`completed` group, then `scheduledTime`).
- [ ] **`averageSleepHours` divides by window length** —
  `HealthKitService.swift:579`: divide by the count of days that actually had
  merged sleep, not the requested window.
- [ ] **Achievement `latestUnlock` overwrite** — `AchievementService.swift`:
  make `latestUnlock` a queue drained one toast at a time.
- [ ] Drop the dead `deinit` in `StoreService.swift:28-40` (singleton never
  deallocates) or document it.
- [ ] `NutritionMath.dailyTargets` — clamp protein grams so protein calories
  can't exceed ~40% of TDEE; surface a note when carbs floor at 0.

### 4.2 Feature-view & state bugs — `[ ]`
- [ ] **Watch pages missing titles** — wrap `WatchStatsView`/`WatchNutritionView`
  in their own `NavigationStack` (or drop the dead `.navigationTitle` calls)
  for consistency with `DoseListView`.
- [ ] **Onboarding `buildingPlan` auto-advance race** —
  `OnboardingView.swift:1987-2007`: add a generation token checked after the
  1400ms sleep, in addition to the page guard.
- [ ] **`HomeView` duplicate `onChange(of: stats.score)`** —
  `HomeView.swift:530-555`: merge into one handler; add a generation token to
  `refreshHeroSnapshot`/`refreshHealthRange` so stale results can't overwrite.
- [ ] **`HomeView` async appear races** — `HomeView.swift:538-545,704-729`:
  convert the hero/health/summary loads to `.task(id:)` (cancel-and-replace).
- [ ] **Blank pushed dead-end** — `HomeView.swift:559-566`: add an `else`
  (`EmptyStateView`) branch to `navigationDestination(item: $detailWeekStart)`.
- [ ] **`ActiveWorkoutView` name edit clobbered** —
  `ActiveWorkoutView.swift:54-145`: only `syncNameFromSession()` when the field
  isn't focused.
- [ ] **Onboarding health permission no scene-phase recheck** —
  `OnboardingView.swift:1835-1842`: add a `.task(id: scenePhase)` HealthKit
  authorization re-check mirroring the notifications step.
- [ ] **`AIResearchView` `isStreaming` stuck true** —
  `AIResearchView.swift:233-298`: drive `isStreaming` from a generation token /
  self-task identity check instead of a bare `defer`.
- [ ] **Swipeable onboarding `TabView` bypasses data capture** —
  `OnboardingView.swift:256-288`: block horizontal swipe, or persist every
  step's data on `.onChange(of: page)` regardless of how the page advanced —
  this also closes the medical-disclaimer acknowledgement gap
  (`disclaimerAcknowledgedAt` at lines 619-623).
- [ ] **Expensive work in `HomeView` body** — `HomeView.swift:334,633-670`:
  move `timelineEvents` (a SwiftData fetch) and `TodayOverviewSnapshot.build` /
  `dailyPlan` into `@State` populated from `.task`/`.onChange`, not computed
  vars read every body pass (they recompute on every scroll frame).
- [ ] **`LabsView` modal has no dismiss** — `BiologyView.swift:103-106`: pass a
  `presentedModally` flag and add a Close/Done toolbar item to `LabsView`.
- [ ] **`HabitsView` stale rows after delete** — `HabitsView.swift:60-141`:
  filter `ForEach(rows)` to ids still present in `habits`.
- [ ] **`PeptideListView` iPad stale detail pane** —
  `PeptideListView.swift:93-108`: clear `selectedPeptide` in `refreshPeptides()`
  when it's no longer in the list.
- [ ] **`ExerciseDetailView` false "not found"** —
  `ExerciseDetailView.swift:52-83`: show a `ProgressView` while the library is
  loading; only show `missingState` after load completes with no match.
- [ ] **`ProtocolListView` navigation desync** —
  `ProtocolListView.swift:160-168`: replace the `[PeptideProtocol]`-typed path
  with a type-erased `NavigationPath` (the stack pushes 3 value types).
- [ ] **Widget duplicate ids** — `PeptideWidgets.swift:215`: give
  `WidgetDoseSlot` a stable unique `id` instead of keying `ForEach` on `.time`.
- [ ] Smaller items: `RestTimerOverlay` always-running timer publisher
  (`RestTimerOverlay.swift:20-29`); `HomeView` `toastAchievement` never reset
  (`HomeView.swift:500-504`); `quickLogSheet`/`.dose` `EmptyView` blank-sheet
  (`HomeView.swift:731-754`); `BiologyView.refreshState` race (`.task(id:)`);
  Watch `DoseRowView` not `.disabled` during send; onboarding `goalDate`
  out-of-range clamp (`OnboardingView.swift:315-317`); `nameStep` focus fired
  from `.onAppear` instead of `.onChange(of: page)`; `signInErrorBinding`
  dual-source alert → `.alert(item:)`; `TrainContainerView` section `.id()`;
  `MealsContainerView` vestigial `consumesDeepLink`.

---

## Phase 5 — Liquid Glass design foundation

The single highest-leverage design fix. Until these land, no screen actually
looks like Liquid Glass on iOS 26.

### 5.1 Kill dual-material rendering — `[ ]`
**Files:** `GlassCard.swift`, `GlassCardModifier.swift`, `GlassButton.swift`,
`GlassTextField.swift`, `GlassSegmentedControl.swift`, `GlassStat.swift`,
`GlassEffectCompat.swift`

Every glass primitive paints a 60%-opaque fake fill *then* applies real
`glassEffect()` on top — two stacked materials, muddy on iOS 26, flat on older
OSes.

- [ ] Rewrite `GlassEffectCompat` so real glass and the fake recipe are
  **mutually exclusive**: `if #available(iOS 26) { .glassEffect(.regular, in:) }
  else { /* fake recipe fallback */ }`.
- [ ] Route every glass primitive through the single new `glassSurface(...)`
  helper.
- [ ] Adopt `GlassEffectContainer` / the existing-but-unused
  `LiquidGlassContainer` to group adjacent glass shapes (hero trio, quick-stats
  row, jump-bar chips) so they merge/refract correctly.
- [ ] Lower tinted-glass alpha to ~0.15–0.2 (`GlassButton.swift:72,119`
  currently 0.32–0.35).

### 5.2 Light/dark semantic colors; remove the dark-mode clamp — `[ ]`
**Files:** `ColorTheme.swift`, `AppTheme.swift:111-134`

`ThemeManager` force-clamps `.light → .dark` because no light surfaces exist;
Liquid Glass is fundamentally an adaptive system.

- [ ] Migrate `AppColor` to semantic asset-catalog colors with light + dark
  variants (or `Color(uiColor: .system*)`).
- [ ] Remove the `.light → .dark` clamp; remove the "SOON" disabled state on
  the theme picker.
- [ ] Lighten `background` from near-black `0x0A0A0A` (~`0x121214`+) so glass
  has something to refract.

### 5.3 Tokenize radii & typography — `[ ]`
- [ ] Add concentric-radius helpers to `Spacing` (`concentric(in:inset:)`);
  purge the ~170 hardcoded `cornerRadius:` literals (~80 distinct values).
- [ ] Replace the ~660 `.font(.system(size:))` literal calls with the `AppFont`
  Dynamic-Type ramp; keep fixed sizes only for documented hero-stat exceptions.
- [ ] Move the 41 `Color(hex:)` + 130 `Color(red:g:b:)` inline colors in
  `Features/` into `AppColor` semantic tokens.
- [ ] Make `Shadows` glass-aware: drastically reduce radius/opacity on glass
  surfaces, or drop drop-shadows entirely on iOS 26.

---

## Phase 6 — Liquid Glass chrome & shared primitives

### 6.1 Native chrome — `[ ]`
- [ ] Delete `GlassNavBar` and `HomeStickyHeader`; move every tab to native
  large-title `NavigationStack` + `.toolbar` (glass + scroll-edge behaviour
  come free on iOS 26). Removes the custom `.ultraThinMaterial` compressing
  header and its fragile hit-test gating.
- [ ] Remove `.toolbarBackground(.hidden, …)` from `HomeView`/`BiologyView`.
- [ ] Migrate list searches (`PeptideListView`, `StackLibraryView`) from
  embedded `GlassTextField` to native `.searchable`.
- [ ] Verify the tab bar `Tab(...)` API + `tabViewBottomAccessory`
  (`NextDoseAccessoryView`) render correct glass and contrast; don't
  double-stack a background on the accessory.
- [ ] Replace `.ultraThinMaterial` sheet backgrounds (`GlassSheet.swift:11,38`)
  and the AIResearch composer (`AIResearchView.swift:223`) with native glass;
  drop forced `presentationCornerRadius` on iOS 26.

### 6.2 Consolidate to one of each primitive — `[ ]`
- [ ] One `GlassButton` — eliminate the solid-accent capsule (`TrainOverviewView`),
  white capsule (`HabitsView:174`), `.borderedProminent` (`LabsView:192`), and
  ad-hoc CTA pills. Pick the glass capsule everywhere.
- [ ] One `GlassCard` — replace the inline glass recipes in `HeroMetricTrio`,
  `AddCustomPeptideCard`, `CommunityStacksEntryCard`, `LabSummaryRow`,
  `PaywallView` etc.
- [ ] Extract a shared `GlassEntryRow` for the duplicated entry-card pattern
  (3+ copies).
- [ ] One `EmptyStateView` — route `HabitsView`, `LabsView`, `TrainOverviewView`,
  `AIResearchView`, `BiologyView` through it instead of bespoke inline states.
- [ ] One segmented control — unify `TrainContainerView`'s underline switcher,
  system `Picker`s, and `GlassSegmentedControl` onto the glass control.
- [ ] Standardize dismiss affordances (native `Done` / drag-to-dismiss).
- [ ] Wire the unused `ShimmerModifier` as skeleton loading on async surfaces
  (Train muscle map, hero trio, weekly summary).
- [ ] Finish or delete the half-retired `GlassProgressRing`.

---

## Phase 7 — Per-screen polish

- [ ] Re-skin `CosmicBackdrop` — replace the opaque non-brand purple starfield
  (Biology tab, premium cards) with translucent accent-tinted glass over the
  app background.
- [ ] Wire a real Atlas brand mark to replace the placeholder "A" glyph in
  `PremiumPromoCard.BrandGlyphMark`.
- [ ] Reconsider Information Architecture: `ProtocolListView` is reached via
  `fullScreenCover` with a manual "Close"; Profile is reached only via a Home
  avatar tap. Promote both to proper navigation destinations.
- [ ] Replace the dated `confirmationDialog` quick-log with a glass menu/popover.
- [ ] Audit the `HomeView` chained-sheet sequence (milestone → completion →
  share) and the `Task.sleep(350ms)` handoffs — ensure a user can't be hit by
  three modals in a row on one appear.
- [ ] Accessibility pass: add `accessibilityLabel` to icon-only buttons
  (only ~82/250 feature files have any); ensure ≥44pt hit targets; verify
  Dynamic Type after the typography sweep; verify contrast of small badge text
  on glass; remove the manual hit-test disabling once `HomeStickyHeader` is gone.
- [ ] Resolve `MetricRing` double animation driver (`easeOut` on `progress` +
  spring on `animatedProgress`).
- [ ] Resolve the stubbed `creatorBanner` discount logic in `PaywallView`
  (`:284-288` returns `nil`) — finish or remove.

---

## Phase 8 — Code cleanup

### 8.1 Dead code — `[ ]`
- [ ] Delete `Features/Insights/InsightsView.swift` and the 8 dead
  `Insights/Components/` files (~2,000 lines, used only by their own previews).
- [ ] Relocate the two live survivors `WeeklySummaryDetailView.swift` and
  `PastWeeksSection.swift` into `Features/Home/` (or a new
  `Features/WeeklySummary/`); delete the empty `Insights/` folder.
- [ ] Delete `Features/Onboarding/OnboardingColors.swift` (zero references).
- [ ] Remove the zombie `AppTab.protocols` / `AppTab.profile` cases; route call
  sites directly via `selectedTab = .library` + `pendingProtocolList`.
- [ ] Move `Features/Lifestyle/WorkoutDetailView.swift` into `Features/Train/`;
  delete the `Lifestyle/` folder.

### 8.2 Naming & docs — `[ ]`
- [ ] Add an authoritative "Naming" section to `README.md`: product = Atlas;
  Xcode targets/repo = Peptide (frozen); bundle ID / URL scheme / Spotlight
  prefixes = `peptidex`/`peptidesai` (frozen for install compatibility).
- [ ] Reconcile the marketing domain (`peptidex.site` vs `peptidesai.com` in
  `OpenFoodFactsService` user-agent) — pick one.
- [ ] Rename folders/types to match enum cases: `Features/Home` → `Today`,
  `Features/Database` → `Library`.
- [ ] Fix `HANDOFF.md` (wrong product name "PeptideX"; false claim that
  SwiftData migration is deferred; references non-existent Track/Lifestyle
  tabs) — or delete it.
- [ ] Fix `README.md`: service count (73, not 37), Insights description, the
  missing `WEEKLY_SUMMARY_*` env-var pair.
- [ ] Move branch-specific planning docs (`ATLAS_REMEDIATION_PLAN.md`,
  `ONBOARDING_*`, `SCREENSHOT_SEED_DATA_AND_FIXES.md`) to `docs/archive/`.
- [ ] Update `CLAUDE.md` (says "Opus 4.6"; environment is 4.7).

### 8.3 God objects & file organization — `[ ]`
- [ ] Split `OnboardingView.swift` (2,551 lines) — one file per page under
  `Onboarding/Pages/`; `OnboardingView` keeps only the pager + `Page` routing.
- [ ] Decompose `DataStore.swift` (2,044 lines) into `extension DataStore`
  files (`+Protocols`, `+Cache`, `+Stats`) — currently zero extension files.
- [ ] Split the multi-phase mega-views: `FoodLibraryFlow.swift` (1,892),
  `BarcodeScanFlow.swift` (1,102), `HomeView.swift` (997),
  `ProfileCustomizationSheet.swift` (960), `ProtocolBuilderView.swift` (823),
  `PaywallView.swift` (688) — split per `Phase`/section.
- [ ] Extract a shared meal-logging flow skeleton (phase enum + portion picker
  + review + logged-confirmation) shared by the 3 scan/search flows.
- [ ] Reserve `Components/` for genuinely small reusable views; promote
  full-screen flows/sheets to the feature root or a `Flows/`/`Sheets/` folder.
- [ ] Flatten one-file subfolders (`Home/Components/Adjustment/`).
- [ ] Move the pure-logic `*Logic` files out of `App/` into `Services/`.

### 8.4 Constants & config — `[ ]`
- [ ] Define the App Group identifier `"group.com.peptidesai.app"` once in
  `Shared/` (it's duplicated in `WidgetData.swift:4` and
  `PendingDoseLogStore.swift:24`); consolidate the cross-process notification
  name prefix too.
- [ ] `.swiftlint.yml` — remove `PeptideTests`/`PeptideUITests` from `included:`
  (they're also excluded). After Phase 8.3, re-enable `file_length` and
  `type_body_length` (generous thresholds) to prevent regression.
- [ ] Codify the service convention in `README.md`/`CLAUDE.md` (stateful →
  `class` singleton; stateless namespace → `enum`; computation → `*Engine`).

---

## Phase 9 — Tests & verification

- [ ] Add unit tests for untested pure engines first (cheapest wins):
  `CyclePhaseEngine`, `OutcomeCorrelationEngine`, `DoseLiveActivityService`.
- [ ] Add regression tests for every Phase 1 fix: CloudKit model defaults,
  the `notes` regenerate-guard, StoreKit entitlement filtering, save-failure
  surfacing, streak-freeze in dose streaks.
- [ ] Build out a real `PeptideUITests` suite (currently a 51-line stub) for
  the onboarding, paywall, and meal-scan happy paths.
- [ ] After each phase: clean build + full test run + manual smoke test of the
  affected surfaces in the simulator (and the Liquid Glass phases on an iOS 26
  simulator/device specifically).
- [ ] Add the CI peptide-count integrity check from Phase 3.6.

---

## Suggested execution order & rationale

1. **Phase 0–1 first, always.** CloudKit being dead (1.1), stale-dose
   duplication (1.2), and silent save loss (1.4) corrupt or lose real user
   data; the Watch toolbar (1.6) and duplicate destination (1.7) break shipped
   features. Nothing else matters if data isn't safe.
2. **Phase 2–3 next.** Security (leaked proxy key → uncapped Anthropic spend,
   PII exfiltration) and resilience are pre-conditions for a public release.
3. **Phase 4** clears the long tail of correctness bugs.
4. **Phase 5–7** is the Liquid Glass conversion — large but lower-risk;
   Phase 5.1 (kill dual-material) gates everything visual.
5. **Phase 8** cleanup is safe to interleave but lands best last so it isn't
   churned by the earlier phases.
6. **Phase 9** runs continuously; treat the per-phase verification as a gate.

Each checkbox is an independently committable change. Keep one logical change
per commit, run tests before each commit, and never mix a refactor with a fix.
