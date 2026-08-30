# ATLAS COMPLETE ENGINEERING AUDIT

**Master Audit 01 — full codebase, architecture, and product-engineering diagnosis.**
Date: 2026-08-28. Scope: entire repository at commit `d6c2e14` (post PR #169).
Method: eight parallel evidence-based investigations (architecture/core, data layer,
HealthKit/concurrency/performance, Today/Train/Watch/widgets, Meals/Biology/Habits/Protocols,
AI/server/privacy/security, StoreKit/notifications/compliance, testing/CI/docs/design system),
synthesized here. Every material claim cites a file; claims that could not be verified from the
repository are marked **NOT VERIFIED**. No application code was changed by this audit.

---

## Executive Summary

Atlas is in **substantially better technical shape than a typical indie iOS app of this scope** —
and better than its own documentation implies. The codebase shows discipline that most teams never
reach: 1,043 gating unit tests, a self-tested design linter at zero errors, an arithmetic WCAG
contrast gate, a genuinely well-engineered AI proxy with App Attest and layered spend controls,
audit-trail comments documenting past bug fixes throughout, and pure `*Engine` types separated from
I/O. The historical P0s (CloudKit delete-diff data loss, expired-entitlement Pro access, StoreKit
3.1.2 rejection) are fixed with rationale recorded in code.

The real problems cluster into four themes:

1. **Trust/compliance drift (fix before the next submission).** The store metadata, privacy
   manifest, and App Review response documents claim "zero third-party SDKs, no data collected,
   no external AI, read-only HealthKit, no camera" — and the code now contradicts every one of
   those claims (RevenueCat at launch, Claude vision meal scanning, HealthKit meal write-back,
   three camera flows, HRV/RHR/sleep aggregates sent to the AI proxy against a purpose string
   that says "All analysis happens on your device", sleep read but undeclared). Two paywall
   surfaces also carry a fabricated "4.9 · 12k+ athletes" rating and a fake 10-minute countdown.
   None of this is hard to fix; all of it is rejection material and reputational risk.

2. **Multi-device data integrity (the only true data-loss class left).** There is no CloudKit
   remote-change ingestion; every save wholesale-upserts stale in-memory state; the entire
   profile (meals, habits, labs, recipes) is one JSON blob in one CloudKit record with
   last-writer-wins semantics; the `StoredProfile` singleton can duplicate on first sync; and two
   devices generate duplicate dose entries for the same day. Single-device users are safe; any
   iPhone+iPad user is silently losing writes today. Separately, the "full backup" omits all
   workout data — the designated no-iCloud recovery path loses the Train tab.

3. **Strategic incoherence between positioning and surfaces.** The product repositioned as
   fitness-first, and the tab bar reflects that — but Today is still structurally a
   peptide-compliance dashboard (dose state rendered up to five times per scroll, no nutrition
   section), every widget and the entire Live Activity/Watch surface is dose-centric, the Watch
   cannot log a single set, and the training planning layer (routines, programs, supersets, RPE)
   is dead scaffolding with models and stores but zero UI. Atlas currently monetizes and
   glances like a peptide app that happens to have a workout logger.

4. **Scaling debt with a known shape.** Every mutation re-serializes the whole data graph on the
   main actor (profile blob included); dose entries are fetch-all-decode-all at launch; the
   931 KB peptide database decodes on the launch critical path; a dead HealthKit
   background-delivery pipeline burns queries and widget-reload budget feeding a cache nothing
   reads; progress photos are stored full-resolution and decoded synchronously in `body`.

**Bottom line:** keep the architecture — it is coherent and does not need a rewrite. Fix the
compliance drift and the sync-integrity cluster first, then rebalance the product surfaces
(Today, widgets, Watch) toward training/nutrition before building anything new.

---

## Current Architecture

**Pattern**: single-store SwiftUI with modern Observation. One `@MainActor @Observable`
`DataStore` (`Peptide/App/DataStore.swift`, 2,357 lines) created in `PeptideApp.init` and injected
via `.environment(dataStore)` (57 `@Environment(DataStore.self)` call sites; zero legacy
`@EnvironmentObject`). A small `AppState` holds tab selection and deep-link mailbox flags.
36 `.shared` singleton services; pure computation extracted to `*Engine` / `*Logic` types per the
stated convention, which is genuinely followed.

**Persistence**: SwiftData with 7 "shell" `@Model` types (`PeptideAtlasSchema.swift:24-40`) —
identity + queryable columns + JSON payload blobs, no SwiftData relationships. CloudKit private
database (`iCloud.com.peptidesai.app`) when signed in, with a documented fallback chain
(CloudKit → local → in-memory → inoperable, each with user-facing banners)
(`SwiftDataRepository.swift:46-215`). The legacy JSON `PersistenceService` survives only for
custom peptides and the widget/Watch App Group snapshots — the dual-write era is over.

**Targets**: iOS app (`Peptide`), iOS widgets + Live Activity (`PeptideWidgets`), watchOS app
(`PeptideWatch`), watchOS widgets (`PeptideWatchWidgets`), unit tests (1,043 tests / 80 files),
UI tests (tab reachability + screenshot harness). XcodeGen-generated project; Swift 5 language
mode with `SWIFT_STRICT_CONCURRENCY: minimal` (the Swift 6 migration is real but moderate —
see Concurrency).

**AI**: three Claude-backed features (meal photo scanning, research chat, weekly summary) routed
through a Vercel proxy (`server/`) that holds the Anthropic key, with shared-secret auth,
App Attest (report mode), model allowlists, token caps, and layered rate/spend limits.

**Navigation**: root `TabView` with 5 tabs — Today, Train, Meals, Biology, Habits
(`PeptideApp.swift:354-375`). Profile is a cross-tab sheet; the peptide Library (database +
protocols + AI chat) is a demoted `fullScreenCover`. Deep links `peptidex://dose/…` and
`peptidex://weekly/current`; Spotlight food/recipe indexing. 86 `.sheet` call sites; one
path-driven `NavigationStack` in the entire app.

```
SwiftUI Views (Features/, 219 files)
   ↓ @Environment
DataStore (@MainActor @Observable god-store) ── AppState (tab + deep-link mailboxes)
   ↓ delegates to                                  ↑ consumed by views
*Logic / *Engine types (pure, tested)         36 .shared services (HealthKit, Store,
   ↓                                           Notifications, WatchSync, AI clients…)
SwiftDataRepository (CloudKit-backed)  +  PersistenceService (JSON: custom peptides,
   ↓                                       App Group widget/Watch snapshots)
SwiftData/CloudKit · HealthKit · StoreKit 2 · WCSession · Vercel proxy → Anthropic
```

---

## Complete Feature Inventory

| Feature | Lives in | State | Notes |
|---|---|---|---|
| Onboarding | `Features/Onboarding/` (OnboardingView 2,724 lines) | Shipped, working | ~20 screens incl. quiz, disclaimer, HealthKit/notifications, trial offer; resume persisted; A/B infra + local-only funnel tracker |
| Today/Home | `Features/Home/` (HomeView 1,086 lines + 48 components) | Shipped, overloaded | 18 sections; heavy dose duplication; no nutrition section; god-screen |
| Train — logging | `Features/Train/`, `WorkoutSessionService` | Shipped, solid | Set logging, prefill from history, rest timer w/ notification, kill-restore, PR engine |
| Train — planning | Models only | **Dead scaffolding** | Routines/programs/supersets/RPE/warm-ups/%1RM all modeled, zero UI; `programs.json` doesn't exist |
| Muscle map | `MuscleMapView`, `WeeklyMuscleHeatmap`, `MuscleGainsEngine` | Shipped | The genuine training differentiator |
| Meals — scanning | `MealScanFlow`, `BarcodeScanFlow`, `NutritionLabelOCR`, `MealScannerService` | Shipped, strong | Photo AI + barcode + label OCR + identity cross-check; confidence-driven UX |
| Meals — library/search | `FoodLibraryFlow` (1,864 lines), `OpenFoodFactsService` | Shipped | OFF search, favorites, recents, custom foods, recipes, Spotlight |
| Nutrition targets | `NutritionMath` | Shipped, static | One-shot Mifflin-St Jeor; no adaptive loop |
| Biology | `Features/Biology/`, `PerformanceAgeEngine`, `BioAgeStateResolver` | Shipped | HRV/RHR/sleep/weight + Pro biomarkers, manual labs, Bio Age (capped, disclaimed heuristic) |
| Habits | `Features/Habits/`, `HabitsService`, `MomentumEngine` | Shipped, high quality | DST-safe streaks, CloudKit dedup, Atlas Score |
| Protocols/peptides | `Features/Protocols/`, `Library/`, `Database/`, schedule/cycle engines | Shipped, demoted surface | 208-entry DB with citations; strong 1.4.1 mitigations; recommendation engines |
| AI research chat | `Features/AIResearch/`, `AIResearchService` | Shipped, Pro | Local RAG grounding + safety system prompt |
| Weekly summary | `WeeklySummaryEngine/Service` + scheduler | Shipped, Pro | AI recap w/ offline fallback; **unreachable without dose logging** |
| Watch app | `PeptideWatch/` | Shipped, dose-only | Dose toggle, stats, water; **no workout capability**; complications structurally empty |
| Widgets | `PeptideWidgets/` | Shipped, dose/nutrition-only | Next dose, compliance, nutrition; no training widget; no widgetURL |
| Live Activity | `DoseWindowLiveActivity`, `DoseLiveActivityService` | Shipped, excellent engineering | Interactive log button, durable cross-process inbox — for doses only |
| Subscriptions | `StoreService`, `PaywallView`, `TrialOfferView`, RevenueCat observer | Shipped | StoreKit 2, pessimistic trial eligibility; several integrity issues (below) |
| Auth | `AuthService` (Sign in with Apple, optional) | Shipped | Keychain hygiene is exemplary |
| Backup/export | `ExportService`, `BackupImportService`, `BackupSnapshotService` | Shipped | Hardened import pipeline; **omits all training data** |
| Siri/App Intents | `Peptide/Intents/` | Shipped | Log meal/recipe/water, streak |
| Sharing | `Features/Sharing/` | Shipped | Cycle share cards, milestone prompts |
| Server proxy | `server/` | Deployed | Auth, rate/spend limits, App Attest, 50 node tests (not in CI) |

---

## Architecture Findings

- **DataStore is a god object (P1)** — 2,357 lines, ≥15 domains (protocol CRUD, streaks, 14
  memoized caches, nutrition, labs, habits, momentum, recipes, notes, food library/Spotlight,
  vials, travel mode, freezes, widget/Watch push, notifications, screenshot mode, backup,
  achievements). Mitigations are real (revision/cacheVersion memoization `DataStore.swift:50-122`,
  debounced save + `flushPendingSave()` on background, thin delegation to `*Logic` types), but
  habits/notes/custom-foods/momentum still mutate `profile` inline instead of via Logic types —
  two conventions in one file (P2).
- **`static var current: DataStore?` escape hatch (P2)** — legitimate for App Intents, but
  `WorkoutSessionService.swift:107` and `PendingDoseLogProcessor.swift:51` reach back into the
  store that also calls them: a soft circular dependency with hidden ordering assumptions.
- **Views bypassing the store (P2)** — `HomeView.swift:738`, `TrainOverviewView.swift:98`,
  `WorkoutDetailView.swift:24`, `WorkoutHistoryView.swift:139` read `SwiftDataRepository.shared`
  directly; `ExercisePickerSheet.swift:49` *writes* from a view. Two data paths to one store means
  cache invalidation only works when writers remember `recordWorkoutFinished` — the exact bug
  class fixed before (comments at `DataStore.swift:1497-1506`).
- **Three divergent streak implementations (P2, user-visible)** — `DataStore.currentStreak`
  (2-day tolerance, freeze-aware, `DataStore.swift:642-681`); `InsightEngine.swift:100-115`
  (claims to match, ignores freezes); `WeeklySummaryEngine.swift:147-165` (1-day tolerance,
  ignores freezes). The home ring, insights, and weekly recap can all show different numbers.
- **Massive files (P2)** — OnboardingView 2,724 lines / 39 `@State`; FoodLibraryFlow 1,864;
  BarcodeScanFlow 1,323; MealScanFlow 1,096; HomeView 1,086; PaywallView 998. These are where
  regressions will hide.
- **No test seam for services (P2)** — everything binds `.shared` at use site;
  `DataServiceProtocol` exists with one conformer and zero consumers (dead abstraction).
- **Strengths to preserve**: Observation-based injection; the memoization system (one O(n)
  grouping per mutation, day-rollover invalidation — most codebases recompute in `body`);
  scene-phase orchestration in `PeptideApp.swift:229-288` (flush-on-background, entitlement
  re-check, notification drift reconciliation); `AppConstants.staticHTTPS` killing force-unwrapped
  URLs; `AppState`'s validated deep-link parsing.

## Data Findings

- **IDs**: UUIDs throughout, stable peptide IDs in the bundled DB — sound.
- **Units**: canonical kg / fl oz with display-boundary conversion (`UserProfile.swift:79-148`);
  training volume in kg; HRV ms, correct HK units — sound.
- **UserProfile is a mega-blob (P0-adjacent, see CloudKit)** — 695 lines, ~88 vars, carrying
  unbounded arrays (mealHistory, habitEntries, weightHistory, labHistory, outcomeHistory,
  recipes, customFoods…) plus the avatar JPEG, persisted as ONE `StoredProfile` row whose long
  tail is a single JSON `extensionData` blob (`SwiftDataModels.swift:264-327, 427-518`). Only
  momentumHistory (120) and weeklySummaries (26) are capped; mealHistory is capped at 3,650.
- **Protocols embed full `Peptide` value copies (P2)** — every protocol and every generated dose
  entry duplicates the complete database record (description, mechanism, citations)
  (`PeptideProtocol.swift:133`, `SwiftDataModels.swift:183`), bloating the blob and freezing
  stale content; dataset corrections never propagate.
- **Timezone/DST**: mostly careful (start-of-day normalization, DST-gap fallback
  `DataStore.swift:2326-2335`, capped streak walks) — but **`StreakFreezeService.dayKey`
  formats local start-of-day through a UTC ISO formatter (P2)** (`StreakFreezeService.swift:42-45`),
  so freezes shield the wrong calendar day for all UTC+ users who cross the boundary. Three
  different day-key conventions coexist (`LifestyleDataLogic.swift:428-440` local;
  `NotificationService.swift:528-531` deliberately UTC).
- **Meal edit desyncs the day's aggregate (P1)** — `DataStore.updateMealEntry`
  (`DataStore.swift:1060-1064`) replaces the entry but never adjusts `dailyConsumption`,
  violating the invariant documented at `LifestyleDataLogic.swift:123-127`; the calorie ring is
  wrong after any edit, and HealthKit-mirrored samples go stale (delete handles cleanup; edit
  doesn't).
- **`unlogDose` wipes user notes (P3)** (`DataStore.swift:432-450`).
- **PR records never recomputed on session delete/edit (P3)** — delete your 1RM workout and the
  record survives forever.

## SwiftData Findings

- **Configuration is correct for CloudKit**: no `@Attribute(.unique)`, everything optional or
  defaulted (documented at `SwiftDataModels.swift:22-29`), no relationships (rule trivially
  satisfied). Schema V2 declared with a scaffolded (empty, accurate) migration plan.
- **`loadEntries()` is fetch-all with per-row JSON decode at launch (P2)**
  (`SwiftDataRepository.swift:446-463`, called from `DataStore.init:140` on the main actor) —
  cold-launch cost grows linearly forever; each row decodes a redundant embedded Peptide.
  Workout sessions got the right pattern (windowed, capped at 200, real `#Predicate`s,
  `fetchCount` — `SwiftDataRepository.swift:558-644`); dose entries didn't.
- **Fallback containers don't pass `cloudKitDatabase: .none` (P2)**
  (`SwiftDataRepository.swift:191-215`) — `.automatic` may re-attempt CloudKit for the exact
  users the fallback exists for, cascading them to the non-persistent in-memory store.
  **NOT VERIFIED** at runtime; explicit `.none` is the unambiguous fix.
- **`commit()` retry + user-visible failure banner** (`SwiftDataRepository.swift:846-868`) — good.
- **`hasAnyData` omits `StoredPersonalRecord` (P3)** (`SwiftDataRepository.swift:813-831`).

## CloudKit Findings

The single largest engineering risk cluster in the app. Single-device behavior is solid; the
two-device story is not.

- **P0-1 — No remote-change ingestion; stale wholesale upserts revert other devices' writes.**
  Zero listeners for `NSPersistentCloudKitContainer.eventChangedNotification` or remote changes
  anywhere; remote data reaches memory only via one pull-to-refresh (`ProtocolListView.swift:139`)
  or relaunch. `performSaveNow` upserts the *entire* protocols/entries arrays and the whole
  profile on every save (`DataStore.swift:1963-1976`), so device A's stale copy silently reverts
  device B's dose log. Everyday-use cross-device data loss. Confidence high (mechanism fully
  visible; runtime NOT VERIFIED).
- **P0-2 — `StoredProfile` singleton duplication.** `saveProfile`/`loadProfile` use unsorted
  `.first` and insert a new row on miss *or fetch error* (`SwiftDataRepository.swift:467-510`);
  first-launch racing CloudKit's initial import yields two profile rows with no dedup/merge —
  presenting to the user as a wiped profile (meals, habits, labs live in the losing row).
- **P0-3 — Profile blob last-writer-wins.** One CloudKit record for all high-churn collections:
  a meal logged on iPhone and a habit ticked on iPad in the same window race at record level, and
  one device's writes to *every* profile-carried collection are discarded wholesale. Whether a
  multi-MB blob even syncs past CloudKit's record limits is NOT VERIFIED — if not, sync fails
  silently for exactly the power users with the most to lose.
- **P0-4 — Duplicate scheduled dose entries across devices.** `regenerateTodayEntries` guards
  only against the local in-memory day (`DataStore.swift:2173-2184, 2314-2346`); two devices
  opening before sync each mint their own UUIDs → permanent doubled doses, inflated compliance.
- **P1 — Backup omits the Train tab and custom peptides.** `AppBackup` = protocols + entries +
  profile only (`ExportService.swift:564-570`); `StoredWorkoutSession`/`Routine`/
  `CustomExercise`/`PersonalRecord` and `custom-peptides.json` are never exported. The designated
  no-iCloud recovery path silently loses all workout history.
- **P2 — Orphaned entries** possible (no cascade; deletion is an in-memory sweep,
  `DataStore.swift:285-296`) — orphans still count in `totalDoses`/compliance forever.
- **Strengths**: upsert + explicit-deletion save path (built specifically after a CloudKit
  delete-diff data-loss bug); iCloud identity-change teardown preventing cross-account bleed;
  degraded-mode banners.

## HealthKit Findings

- **Reads**: heartRate, HRV(SDNN), restingHeartRate, bodyMass, stepCount, activeEnergyBurned,
  **sleepAnalysis** (`HealthKitService.swift:35-43`). **Writes** (opt-in): dietary energy,
  protein, carbs, fat only (`:138-145, 186-253`). Only one file touches `HKHealthStore`;
  watch/widget targets have no HK entitlement.
- **P0-5 — Purpose-string drift.** `NSHealthShareUsageDescription` (`project.yml:107`) omits
  sleep — which drives Recovery (weight 0.40), Performance Age, and the Health Monitor — and
  claims **"All analysis happens on your device"** while `WeeklySummaryService` sends HRV
  avg/delta, RHR avg, and sleep-hours avg to the Vercel proxy → Anthropic
  (`WeeklySummaryService.swift:156-177`, `server/api/weekly-summary.js:147-155`). Aggregated,
  opt-in, Pro-gated — but the sentence is categorically false. Guideline 5.1.1/5.1.2 material.
- **P1 — Dead background-delivery pipeline.** `cachedSnapshot`/`refreshSnapshot`
  (`HealthKitService.swift:20, 341-398`) run 6 queries + `WidgetCenter.reloadAllTimelines()` on
  every observer fire for 7 types at `.immediate` — and **nothing reads the snapshot** (zero
  consumers, verified). Widgets render no HK data, so the reloads burn the budget the dose
  widgets need. `activeEnergyBurned` exists *only* for this dead path — reading a type you never
  use is its own review liability.
- **P2 — `requestAuthorization` success misread as "granted"** — deny-all users get
  `healthConnected = true` (`DataStore.swift:1557-1571` doc comment claims otherwise) and are
  recorded as `"health_granted"` in the onboarding funnel (`OnboardingView.swift:2220-2231`),
  corrupting metrics. The honest signal (`probeReadAvailability`) already exists.
- **P2 — No app-side HK caching** — hero trio re-runs 5 queries on every dose toggle
  (`HomeView.swift:607-608`); a Today open plus a couple of toggles issues ~20+ round trips.
- **Strengths**: modern async descriptors; genuinely good sleep handling (overlap merge,
  wake-day attribution, nights-with-data averaging); DST-safe day math; external-UUID-anchored
  nutrition writes with precise undo-delete; observer completion called after refresh resolves.

## Swift Concurrency Findings

The `SWIFT_VERSION: "5.0"` comment implies a mess; the code is better than that. ~38 services are
already `@MainActor`; delegate bridges hop correctly; no off-main UI writes were found.

Remaining Swift 6 worklist (P2 as a class, moderate size):
`ThemeManager: @unchecked Sendable` (~230 accent-token call sites — the big one, with honest
`assertMainActor()` debug traps as stopgap), `LocalizationManager` (same shape),
`PersistenceService` (serial-queue-earned, would survive as-is), `AvatarImageCache` (NSCache,
correct), ~10 justified `nonisolated(unsafe)` immutable statics, `@preconcurrency` imports for
HK/WC/UN/MetricKit. P3s: unstructured fire-and-forget tasks in `DataStore.swift:1050,1074` and
HomeView onAppear; a secondary `DataStore()` overwrites `Self.current` and leaks a
NotificationCenter block observer token (`DataStore.swift:192-206`); a fast
`healthConnected` toggle can leave observers running (`PeptideApp.swift:107-113`).
No retain cycles found; `[weak self]` discipline is consistent.

## Performance Findings

Worst-first:
1. **P1 — Full-graph re-serialization per save.** Every dose toggle/water log, after 350 ms,
   synchronously on the main actor: upsert all protocols + all entries (each re-encoding its
   embedded Peptide JSON), re-encode the entire profile blob, rebuild the widget snapshot +
   `reloadAllTimelines()`, rebuild and push the full Watch payload
   (`DataStore.swift:1926-1991, 2043-2053`; `WatchSyncService.swift:38-143`). Fine at month one;
   a main-thread hitch on every toggle at year two — the principal scaling bottleneck. Fix:
   per-collection dirty flags, off-main encoding, and the profile split.
2. **P1/P2 — Progress photos**: stored full-resolution (no downscale,
   `ProgressPhotoStorage.swift:35-48`) and decoded synchronously inside `body` per slot per render
   (`ProgressPhotosCard.swift:194-199`, repeated in `ProgressPhotoCompareView`). Two 48 MP decodes
   ≈ 200+ MB transient memory and scroll hitches. The avatar path already does this right
   (off-main downscale + NSCache) — copy it.
3. **P1 — Dead HK observer→refresh→reload loop** (see HealthKit).
4. **P2 — 931 KB `peptides.json` decoded synchronously on the launch critical path**
   (`PeptideDatabase.swift:12` forced by `DataStore.init:48` inside `PeptideApp.init`).
   `ExerciseLibrary` solved the identical problem with `Task.detached` + lazy `.task`
   (`ExerciseLibrary.swift:44-73`); apply the same.
5. **P2 — `loadEntries()` fetch-all at launch** (see SwiftData).
6. P3s: `peptideDatabase` allocates a fresh 208+n array per access; exercise picker rebuilds and
   re-sorts 800+ items per keystroke; `resolveLastCompletedSet` walks full history with a cache
   invalidated on every set edit; `workoutSummary()` called twice per Movement-card render.

## Memory Findings

No leaks found. Timers are view-lifecycle-bound (`Timer.publish().autoconnect()`); caches are
bounded (`AvatarImageCache` countLimit 6, `BarcodeProductCache`, URLCache bump for OFF thumbs);
singleton listeners are process-lifetime by documented design. The two real memory risks are the
progress-photo full-res decode (above) and the unbounded profile arrays (habitEntries,
labHistory, outcomeHistory, dailyConsumption grow forever; only momentum/weeklySummaries/
mealHistory are capped).

## UI Architecture Findings

- **HomeView is a god-screen (P2)**: ~24 `@State`, 8 sheets, 2 overlays, scroll-geometry +
  preference-key tracking, ~17 services touched. The `DerivedToday` snapshot struct exists
  because render cost already bit once.
- **86 `.sheet` call sites, one path-driven NavigationStack** — consistent but unmanaged; no
  state restoration (`selectedTab` not persisted, acknowledged in comments).
- **Deep-link "mailbox" flags (P3)**: each new deep link adds a flag plus tribal knowledge about
  mount races (the comments document one, `AppState.swift:55-61`); a typed pending-route queue
  would scale better.
- **Nested `NavigationStack` in `WorkoutHistoryView:46`** while also pushed as a destination —
  known SwiftUI misbehavior source (P3, NOT VERIFIED at runtime).
- Careful sheet-chaining across runloop ticks, day-0 empty-state gating, iPad width caps — the
  polish layer is real.

## Today Findings

Eighteen sections in render order; the diagnosis in one line: **Today is still a
peptide-compliance dashboard wearing a fitness app's tab bar.**

| Section | Purpose | Value | Duplication | Verdict |
|---|---|---|---|---|
| WelcomeHeader | Greeting/avatar | Low | Sticky header repeats it | Keep (merge w/ sticky) |
| TodayContextRow | Cycle + date pills | Low | Date above; cycle in ScoreCard | **Remove/merge** |
| TodayJumpBar | Section chips + Log | Med | Two chips duplicate the tab bar | Demote (keep +Log) |
| TodayHabitsHero | Habit ring/streak/chips | **High** | Habits tab | **Keep (lead)** |
| AtlasScoreCard | Gamified score | Med | Watch complication, progress sheet | Keep |
| NotificationIssueBanner | Broken-reminder warning | Situational | — | Keep |
| WeeklySummaryHeroCard | AI recap (Pro) | Weekend | Detail view | Keep (gated) |
| HeroMetricTrio | Adherence/Recovery/Sleep rings | High w/ Health | Adherence = ScoreCard = ScheduleCard; Recovery/Sleep = Biology + grid below | Keep |
| CoachingCard | One-line recommendation | Med | Derived from trio | Keep |
| GoalCountdownCard | Goal-date countdown | Low | — | Demote |
| TodayOverviewCard | Hero dose + insight | Med | Duplicates DailyPlan, Schedule, timeline, widget, tab accessory | **Merge** |
| ProtocolScoreCard | Dose adherence score | Med | Duplicates trio ring + habit streak | **Remove/merge** |
| DailyPlanCard | Dose plan | High (peptide users) | Same entries as ScheduleCard | Merge into one dose section |
| TodayScheduleCard | Dose checklist | High (peptide users) | Same entries as DailyPlan | Merge |
| HomeWellnessSection | Check-in CTA | Med | Feeds insights | Keep |
| HomeMovementSection | Workout count card | Med | Routes to a *legacy duplicate* workout screen; `workoutSummary()` fetched twice per render | **Rewire to Train** |
| TodayTimelineCard | Merged chronological feed | Med | Re-lists everything above | Keep timeline OR per-domain cards — pick one |
| HealthMonitorGrid | HRV/RHR/Sleep ranges | Med | Biology tab + trio | Demote |

**P1 (product)**: today's dose state renders in up to five places on one scroll; training gets one
small card routing to a legacy screen; nutrition has **no section at all** (HomeMealsSection was
removed for a sheet bug and never replaced with anything nutrition-shaped,
`HomeView.swift:347-352`).

## Train Findings

- **The logging core is competitive and partly better than competitors**: synchronous persist on
  every set edit + kill-restore (`WorkoutSessionService.swift:24-28, 253-257`), absolute-date rest
  timer with background notification, prefill from last session, PR engine with an ingest-once
  contract and bodyweight-reps track, muscle heat-map suite (the standout differentiator).
- **P1 (strategic) — the planning layer is dead scaffolding**: `loadRoutines`/`upsertRoutine`
  have zero Feature callers; `startWorkout(routine:)` only ever called with nil; `programs.json`
  and `ProgramCatalog` referenced in doc comments **do not exist**; `supersetGroup`, `rpe`,
  `isWarmup` (write side), `targetPercentOf1RM` are dead fields. Against Hevy/Strong, no
  routines/templates = not competitive for the core lifter loop.
- **P2** — TrainOverview stale after finishing a workout (refresh only on first-appear and
  pull-to-refresh; the finish-notification listener was "next commit" and never landed,
  `TrainOverviewView.swift:66-70, 94-96`).
- **P2** — `startWorkout()` silently deletes a previous active session past a 2 s window
  (`WorkoutSessionService.swift:41-50`) — currently low exposure, a landmine for any future
  Siri/Watch/deep-link caller.
- **P2** — duplicate write/read paths: legacy quick-log writes sets×reps into a note string on an
  exercise-less session (`DataStore.logWorkout:1450-1476` via a sheet living in
  `Features/Meals/Components/WorkoutLogSheet.swift`); `WorkoutDetailView` (legacy "Workout
  Tracker") vs `WorkoutSessionDetailView`; three copies of the session→entry adapter, one of
  which counts warm-ups/incomplete sets differently (P3, inconsistent numbers between Today and
  Train for the same session).
- **P2** — `ExerciseDetailView` has no per-exercise history/PRs/charts/add-to-workout (its own
  header admits the CTA was deferred) — Hevy/Strong make the exercise page the progress hub.
- Missing table stakes: plate calculator, exercise reorder, per-exercise notes UI, RPE input,
  `HKWorkout` write-back (deferred, documented).

## Meals Findings

- **The scanning stack is the app's most differentiated, best-executed feature.** Photo AI with
  confidence-driven review, barcode with cache-first stale-while-revalidate OFF lookups, label-OCR
  fallback, and a cross-catalogue identity check that says "that's shampoo, not food". Undo on
  every path; macro-sum invariant enforced; kJ/kcal legacy traps handled; SSRF-hardened image
  URLs; non-binary BMR handling.
- **P1 — meal edit desyncs daily aggregate** (see Data Findings).
- **P2** — camera-after-library-pick inherits stale EXIF date → wrong-day log
  (`MealScanFlow.swift:99-106` vs `:579`); review screen never shows/allows the landing date.
- **P2** — label OCR stores per-serving values as per-100 g (documented v1 cut,
  `NutritionLabelOCR.swift:24-28`) — the one place macro math is actively wrong.
- **P2** — no adaptive targets (one-shot Mifflin-St Jeor, `NutritionMath.swift:152-194`) — the
  largest table-stakes gap vs MacroFactor.
- **P2** — fiber has a target and OFF capture but is dropped from `MealEntry`/`DailyConsumption` —
  the target can never be measured. Track it or drop it.
- **P3** — no "copy yesterday"; `dailyConsumption` unbounded; timezone drift on local day keys.

## Biology Findings

- Performance Age is a transparent, capped (±8 y), confidence-gated, disclaimed heuristic —
  **defensible as an engagement metric**, more honest than most "biological age" features.
- **P2** — thresholds are not age-normalized (HRV ≥60 ms "younger" at any age,
  `PerformanceAgeEngine.swift:106-121`): systematically tells older users they're older — the
  punitive failure mode. The code itself flags cohort tables as v2; treat that as signal-vs-noise,
  not polish.
- **P2** — confidence gate contradicts its own docs (needs 3-of-4 components, comment claims 2)
  and `BioAgeStateResolver.swift:107` computes building progress as `days/7`, so a user with only
  two data streams pins at "7 of 7 days · 100%" forever with no explanation of what's missing.
- **P3** — Biology partially duplicates Today's Health Monitor grid; differentiation (Bio Age,
  trends, labs, config) is real but the same three numbers live on two tabs.
- Labs: simple, sound manual entry; disclaimer present.

## Protocol Findings

- Data model and scheduling engines are sound (backward-compatible Codable, day-delta week math
  with the `weekOfYear` trap documented, DST-safe boundaries, wash-out wrap, tested).
- **P2** — full `Peptide` value copies embedded per protocol *and per dose entry* (bloat +
  frozen stale content; IDs are stable — store IDs, resolve at read).
- **P2 (compliance tension)** — the 1.4.1 mitigation work is genuinely strong (zero commerce
  language in `peptides.json`, 171 research qualifiers, "Reported in Research" framing with
  citations, persisted disclaimer acknowledgment) — but three surfaces cut against the "we don't
  recommend/calculate" defense: `resolvedDose` falls back to the database `dosageRange`, so
  reminders literally push "BPC-157 • 250-500 mcg" for a user who never entered a dose
  (`PeptideProtocol.swift:84-92`, `NotificationService.swift:425-426`); `RecommendedPeptidesCard`
  says "Recommended"; and the paywall sells "half-life, **dosing** and reconstitution"
  (`PaywallView.swift:327`) while the disclaimer says the app doesn't calculate doses. Require an
  explicit user-entered dose before scheduling reminders, and reword the paywall bullet.
- Prominence is correctly demoted (Library is a full-screen modal off Today's cycle pill and
  Profile); the >3-active-protocols Pro gate is consistent.

## AI Findings

| Feature | Model | Data sent | Validation | Notes |
|---|---|---|---|---|
| Meal scan | claude-sonnet-5 | Photo only (downscaled, ~700 KB) | Typed decode + plausibility clamps (0–5000 kcal etc.) | Strong containment |
| Research chat | claude-sonnet-4-6 | Chat history + RAG context (peptide names) | System-prompt rules only (free text) | Local RAG grounding; no output-side citation verification (P3) |
| Weekly summary | claude-sonnet-4-6 | Aggregates incl. HRV/RHR/sleep averages | Server rebuilds payload via allowlist — exemplary | Offline template fallback; cached per week |

- `CoachingMessageEngine` and `OfflineWeeklySummaryFormatter` are pure local templates (verified —
  no network).
- **P2** — client requests `max_tokens: 1024` for meal scans; proxy silently clamps to 800
  (`MealScannerService.swift:394` vs `anthropic-proxy.js:70`) → busy plates can truncate mid-JSON
  and fail with no signal of the real cause.
- **P3** — client sends `stream: true`; the proxy strips it; chat never streams (buffered
  fallback works). Dead latency feature.
- Where AI is durable value: the meal scanner (differentiator) and the grounded research chat.
  The weekly summary is good but currently unreachable for non-peptide users (see below).

## StoreKit Findings

- **Solid foundation**: StoreKit 2, pessimistic trial-eligibility default (documented), revocation
  + expiration filtering, `.pending` (Ask to Buy) handled, entitlement re-check on every
  foreground, week→days trial conversion, restore double-fire guard, Lifetime correctly exempt
  from auto-renew disclosure, 15 `SKTestSession` tests.
- **P1 — RevenueCat observer mode likely records nothing.** With
  `purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2` (`PeptideApp.swift:32-37`), the
  SDK requires `Purchases.shared.recordPurchase(...)` after each purchase — zero call sites exist.
  The integration's entire stated purpose (dashboard/webhook accuracy) silently doesn't happen.
  NOT VERIFIED against the pinned SDK version.
- **P2 — grace-period/billing-retry subscribers lose Pro**: `expirationDate < Date()` strips
  entitlements Apple says to honor during billing retry; nothing reads
  `Product.SubscriptionInfo.Status`/renewal info (`StoreService.swift:266-267`).
- **P2 — marketing sells gates the code doesn't enforce**: `canAccessCloudSync`/
  `canAccessAllWidgets` referenced nowhere outside tests; widgets/Watch/Live Activities/cloud
  sync are free in code but sold as Pro in the listing (revenue leakage + 2.3.1-adjacent copy
  accuracy).
- **P2 — SAVE-badge inconsistency confirmed** (PaywallView ≥5% threshold vs TrialOfferView any
  positive %) — HANDOFF's lead verified.
- **P3** — hardcoded USD fallback prices on TrialOfferView; stale "3-day trial" header comment;
  gating for AI chat is UI-entry-only (service has no Pro check; the proxy is the backstop).
- **Highest-impact unknown (NOT VERIFIED, needs App Store Connect)**: whether ASC's
  introductory-offer config actually matches the P7D the paywall promises. If ASC still carries
  3-day/14-day offers, every "7 days free" string is a misdescribed charge — worse than the
  build-135 rejection.

## Privacy Findings

- **P0 — the privacy story contradicts the shipped binary.** Store description: "Zero analytics,
  trackers, or third-party SDKs"; privacy label: "collect data? No"; `PrivacyInfo.xcprivacy`:
  `NSPrivacyCollectedDataTypes = []`; docs/privacy.html: "No third-party SDKs that phone home."
  Meanwhile RevenueCat is configured at process start (contacts api.revenuecat.com each launch;
  RC's own guidance requires declaring Purchases + Identifiers), meal photos go to Anthropic, and
  weekly-summary biometric aggregates leave the device. Apple cross-checks SDK privacy manifests
  at submission. The repo even has a documented process for updating these claims
  (`APP_STORE_METADATA.md:334-348`) — followed for the dormant drains, skipped for RevenueCat.
- **Genuine strengths**: funnel tracker is local-only with double-gated (endpoint + consent)
  upload and Atlas-controlled host allowlist; DiagnosticsService is MetricKit-local, capped,
  never uploaded; `NSPrivacyTracking: false` is true; OS logging is `.private`-annotated;
  weekly-summary aggregates strip names/UUIDs/notes.
- **P3** — backups export unencrypted full health-adjacent history (user-initiated; consider a
  passphrase option); FaceID lock is a soft UI gate, documented honestly.

## App Store Compliance Findings

Ranked by rejection likelihood × impact:
1. **P0 — privacy label / manifest / metadata vs RevenueCat + AI data flows** (above). Fix the
   manifest, label, description, privacy.html, and Review Notes together.
2. **P0 — `APP_STORE_REVIEW_RESPONSE.md` is ready-to-paste misinformation**: "no third-party AI
   APIs… no data leaves the device for AI… deterministic on-device rule engine" (§4, §9), "no
   camera" (§1.2), "read-only against Apple Health / NSHealthUpdateUsageDescription intentionally
   absent" (§3.2 — the key exists and write-back ships), "trials: 3-day/14-day". Pasting these
   into App Review would be discoverable misrepresentation. The newer metadata Review Notes fixed
   some but still assert "no third-party AI APIs" (`APP_STORE_METADATA.md:733-734`).
3. **P0 — fabricated social proof**: "4.9 · Loved by 12k+ athletes" on PaywallView,
   TrialOfferView, and OnboardingView (incl. accessibility labels) with no verifiable source, at
   ~v1.0 — Guideline 2.3.1. `check-copy-claims.py` (built to pin numeric claims) doesn't cover it.
4. **P2 — fake 10-minute countdown** on TrialOfferView (nothing changes at 0:00) — pattern under
   active dishonest-paywall enforcement.
5. **P2 — HealthKit purpose string** (sleep omission + on-device claim) — see HealthKit.
6. **P2 — 1.4.1 soft spots** (database dose ranges as reminder defaults; "Recommended" wording;
   paywall "dosing") — see Protocols. Age rating 17+/Medical/Drug-references is correctly
   declared.
7. **Strength**: the 3.1.2 regime (post build-135 rejection) is now excellent — EULA/privacy links
   in description + both paywalls, enforced by `check-store-metadata.py` in CI.

## Testing Findings

- **The "tests don't compile" narrative is stale.** 1,043 test functions in 80 files, gating in
  CI since 2026-08-08 (workflow comment records 1039/0 on `dd5b054`). Engines, persistence
  round-trips, migrations, workout lifecycle, meal scanning, barcode stack, and StoreKit
  (`SKTestSession`) are all covered. Server proxy: 50 node tests, all passing locally.
- **Missing (P0 class)**: HealthKitService beyond two "doesn't crash" tests; WatchSyncService
  (zero); CloudKit fallback-chain selection logic; RevenueCat observer/StoreKit 2 interaction.
- **Missing (P1)**: WeeklySummary trio, StreakFreezeService, TimezoneChangeDetector,
  PendingDoseLogProcessor, BiometricCorrelationEngine (breaks the repo's own every-Engine-tested
  convention).
- **UI tests**: 6 tab-reachability tests + a screenshot harness that asserts nothing. No UI test
  covers onboarding, purchase, meal scan, or workout logging; the UI-test CI step hardcodes
  `iPhone 16` (will flake on runner-image changes).

## Accessibility Findings

Static posture is strong and mechanically enforced: 819 `AppFont.scaled` call sites vs 9 justified
raw sizes; 198 accessibilityLabels; 90 combined rows; 63 reduceMotion references; design-lint +
contrast gate + XXXL screenshot pass. Weak spots: low `accessibilityValue`/`Hint` density (metric
rings can read as unlabeled numbers); **no VoiceOver run has ever been verified on device** —
the entire a11y story is static analysis. HANDOFF admits it.

## Localization Findings

English-only shipping is a deliberate, correctly-reasoned decision (13% catalog coverage —
46/356 sentences; nine translated languages preserved at
`localization/Localizable.translated.xcstrings` with an 80%-coverage restore gate). The blocker is
string extraction (310 sentences), not translation. The only defect: `ROADMAP.md:55` claims
"Complete — 9 locales fully translated" — the one place the story is told wrong. 71 orphaned
catalog keys deserve cleanup.

## Design System Findings

The best part of the repo. Small, semantic token files (AppColor/AppFont/Spacing/glass, 689 lines
of Theme); three-layer enforcement (SwiftLint custom rules, a 22-rule `design-lint.py` **with its
own 44-test suite**, arithmetic WCAG contrast checking of 256 pairs); currently zero errors/zero
warnings, verified in this audit. Nits: rule-count drift across docs (11/20/22); two separate
color-exemption mechanisms that could diverge; the linter's self-tests don't run in CI (they
exist precisely because a rule once went blind).

## Navigation Findings

5 tabs + Profile sheet + Library fullScreenCover; deep links and Spotlight route through
validated AppState mailboxes. Issues: mailbox-flag fragility (P3), no state restoration (P3),
nested NavigationStack in WorkoutHistoryView (P3), Home's Movement card routing to a legacy
duplicate workout screen (P2), two Today jump-bar chips duplicating the tab bar (P3). No dead
ends found; sheet-chaining races are handled deliberately.

## Notifications Findings

The 64-slot budgeting system (soonest-first drop policy, reserved snooze/habit slots, per-slot
coalescing, `ScheduleReport` surfaced to UI, force-quit reconciliation, UTC-anchored IDs) is far
above typical quality. Real bugs:
- **P1 — the dose scheduler's set-diff cancels the weekly-summary notification** after any
  protocol edit (`reconcilePendingState` absorbs the fixed ID; `toRemove` doesn't protect it —
  `NotificationService.swift:190-196`). Edit a protocol Saturday night → no Sunday push. One more
  preserved prefix fixes it.
- **P2 — weekly-summary tap is a no-op**: `userInfo["deeplink"]` is never read;
  `NotificationDelegate` handles only snooze/MARK_TAKEN; local-notification taps don't hit
  `onOpenURL`. The promised "tap to see your week" just foregrounds the app.
- P3s: rest-timer notifications bypass auth state entirely (marketed Lock Screen alert silently
  never arrives for never-prompted users) and its IDs get swept after relaunch mid-timer;
  `timesPerWeek` habits nudge daily by documented design; habit reminders scheduled without an
  auth check.

## Apple Watch Findings

- **P1 — complications are structurally empty on real hardware.** Both watch-side providers read
  `watch_data.json` from the watch's App Group container (`PeptideWatchWidgets.swift:66-68,
  271-274`) — but the only writer of that file is the *phone* (`WatchSyncService.swift:107-115`),
  and App Group containers are per-device. No watch-side code persists received `WatchData` or
  calls `WidgetCenter.reloadTimelines`. The Watch app's own disk-cache read on cold launch is
  dead code for the same reason. NOT VERIFIED on device; container isolation is documented
  platform behavior.
- **P1 (strategic) — no workout capability at all**: dose toggle, stats, water logging only.
  A fitness-first product whose Watch can log a peptide dose but not a set.
- The WCSession messaging layer itself (applicationContext snapshots, sendMessage with
  transferUserInfo fallback, optimistic UI, 10 s watchdog) is genuinely well engineered.
- P2: day-rollover staleness (yesterday's list shows until the phone app next runs).

## Widgets Findings

- Inventory: NextDose (S/M), Compliance (M — same provider re-badged), Nutrition (S/M). Clean
  snapshot pipeline (pure `WidgetSnapshotBuilder`, atomic App Group writes).
- **P1 (strategic)**: `WidgetData` contains zero training fields. The widget gallery for "Atlas,
  the fitness app" offers Next Dose, Daily Compliance, and Nutrition.
- **P2**: single-entry 15-minute `.after` timeline burns the WidgetKit refresh budget (multi-entry
  timelines would render dose transitions with zero refreshes); the midnight entry shows
  yesterday's data until the phone app runs.
- P3: no `widgetURL` deep links (every tap lands on app root); today-list can show only completed
  morning doses while pending evening doses are invisible.

## Live Activities Findings

`DoseWindowLiveActivity` + `DoseLiveActivityService` is an excellently engineered pipeline:
interactive `LiveActivityIntent` log button, token-guarded dismiss preventing double-`end()`
races, staleDate, durable `PendingDoseLogStore` inbox with Darwin-notification wake. Two issues:
the inbox has a small cross-process read-modify-write race that can resurrect an applied marker
and un-log a dose (`PendingDoseLogStore.swift:47-68`, P2 low-probability/high-consequence), and
strategically there is no workout or rest-timer Live Activity — the two most natural fitness
Live Activities don't exist while a dose window gets 605 lines of Dynamic Island treatment (P1
strategic, same theme as widgets).

## CI/CD Findings

- `pr-checks.yml` is excellent: fail-safe path filter, real build + gating unit tests with
  device-ID resolution, SwiftLint, 25% coverage soft-gate, secret-leak guard, design/metadata/
  contrast/dataset gates.
- **P1 — TestFlight builds ship the weekly summary dead**: `ios-testflight.yml` injects only 4 of
  the 6 documented secret slots; `WEEKLY_SUMMARY_ENDPOINT`/`SECRET` are missing while
  `WeeklySummaryService.swift:250-254` reads them. A Pro feature silently unconfigured in every
  TestFlight build.
- **P1 — the 50 server proxy tests never run in CI** (only `node --check`); the code guarding the
  Anthropic key is tested only when someone runs `scripts/check.sh` locally. Same for
  `check-copy-claims.py` and the design-linter's self-tests.
- **P1 — `release.yml` pushes directly to main** via GITHUB_TOKEN, bypassing PR checks; its
  version-bump sed differs from the TestFlight one.
- P2: binary-size gate is label-opt-in and warn-only (README calls it gating); auto-version
  `1.2.<run_number>` needs a manual bump after each App Store release (documented time bomb);
  UI-test step hardcodes iPhone 16.

## Documentation Drift

| Claim | Actual | Risk | Fix |
|---|---|---|---|
| "Zero third-party SDKs / no data collected / no external AI" (metadata, privacy label, manifest, privacy.html, Review Notes) | RevenueCat at launch; Claude meal scan/chat/summary; biometric aggregates off-device | **Rejection + false public claims** | Update all five surfaces together |
| `APP_STORE_REVIEW_RESPONSE.md`: no camera, read-only HealthKit, 3/14-day trials, on-device AI | Three camera flows; HK write-back ships; P7D; Claude proxy | Misinforming App Review | Rewrite before any submission |
| "Swift 6.0" (README:9, HANDOFF:96, ROADMAP:12, CLAUDE.md:7) | `SWIFT_VERSION: "5.0"`, strict concurrency minimal | Agents/devs write against wrong assumptions | Say "Swift 5 mode, Swift 6 migration pending" |
| HANDOFF "current in-flight: PR #161" | 8 PRs landed since, incl. RevenueCat (#168) | Next session re-does/contradicts work | Rewrite HANDOFF |
| "PeptideTests doesn't compile" (project.yml:299, pr-checks comment, screenshots.yml, HANDOFF:83) | 1,043 tests gating and green | Automation may skip the test target | Delete stale comments + `test-compile` job |
| ROADMAP:55 "Localization: Complete — 9 locales" | English-only, 13% coverage, deliberate withhold | High — contradicts a safety decision | "Withheld — see localization/README.md" |
| ROADMAP "7-day monthly / 14-day annual trials" | Both P7D | Pricing-copy drift caused a past rejection | Update |
| README "six env-var slots" injected | TestFlight injects four | Feature ships dead | Fix workflow |
| README "binary-size delta gating" in PR checks | Label-opt-in, warn-only | Implies a gate that doesn't exist | Reword |
| README "eleven design-lint rules" / check.sh "20" | 22 | Trivial | Have the script print it |
| `prompts/codebase-audit.md` "HealthKit is read-only; any save is a bug" | Opt-in nutrition write ships | A future audit "fixes" the write path | Update |
| README "gitignored `Secrets.xcconfig`" | No xcconfig ignore rule exists | One `git add .` from committing the proxy secret | Add the rule |

## Dead Code

Removal-candidate list (do not delete without the noted checks):
- `PersistenceService.saveProtocols/saveEntries/saveProfile` — **not** removable, despite an
  earlier revision of this list saying "zero callers". They have no *production* caller, but
  `MigrationServiceTests` and `PersistenceRoundTripTests` hold `PersistenceService.shared` and
  call them to seed the legacy JSON the JSON→SwiftData migration then imports, so deleting them
  would gut that suite's coverage of the migration. The foot-gun is real (app code calling one
  writes JSON nothing reads) — defuse it by narrowing visibility or documenting the constraint,
  not by deletion.
- `DataServiceProtocol` — one conformer, zero consumers, drifted API. Delete or actually use for
  test doubles.
- `HealthKitService.cachedSnapshot`/`refreshSnapshot` + heartRate/activeEnergy observation — zero
  consumers (or make it the shared cache the views need — pick one).
- Dead training model fields until UI exists: `supersetGroup`, `targetPercentOf1RM`, `rpe` input,
  `isWarmup` write side; routine store plumbing (`loadRoutines`/`upsertRoutine`).
- `StoreService.canAccessCloudSync`/`canAccessAllWidgets`/`canAccessFullAnalytics`/
  `canAccessExport`/`canAccessUnlimitedProtocols` — unreferenced outside `StoreServiceTests`
  (either enforce or remove and fix the listing copy; the live protocol gate is
  `requiresPro(activeProtocolCount:)`). Note `canAccessAIFeatures` is NOT in this list — it is
  enforced at `WeeklySummaryService.swift:41`.
- Legacy quick-log workout path (`DataStore.logWorkout` + `WorkoutLogSheet`) and
  `WorkoutDetailView` "Workout Tracker" — superseded by the session pipeline.
- `test-compile` CI job; stale `.storekit`-era comments ("3-day trial"); export `version: "1.0"`
  vs supported `"2"`; 71 orphaned localization keys; `UserProfile.workoutHistory` (retire after
  the CloudKit-compat window).

## Technical Debt

- **P0** (data loss / rejection / trust): CloudKit sync cluster (remote-change ingestion, profile
  dedup, entry dedup, blob split); privacy/metadata/review-response drift; fabricated social
  proof; HealthKit purpose-string drift.
- **P1**: backup omits training data; RevenueCat recordPurchase; weekly-summary notification
  swept + dead tap; TestFlight secrets; proxy tests not in CI; release.yml bypass; meal-edit
  desync; save-path re-serialization; progress photos; dead HK pipeline; Today/widget/Watch
  strategic rebalance; routines UI (or delete the scaffolding).
- **P2**: streak unification; view→repo bypasses; grace-period entitlement; StreakFreeze UTC
  keys; fallback container `.none`; peptide-copy embedding; god-file splits; Swift 6 migration
  (ThemeManager first); HK auth semantics; adaptive targets; label-OCR serving math.
- **P3**: everything else catalogued above.

## Competitive Benchmark

- **vs Hevy/Strong (training)**: Atlas matches or beats on rest timer, prefill, kill-restore, PR
  detection, and muscle heat-mapping (ahead). It loses on routines/templates/programs (absent),
  supersets/RPE/warm-ups (absent), exercise-page progress hubs, plate calculator, and Watch
  logging (absent). Verdict: the logger is table-stakes-complete; the *planning* loop that
  retains lifters is missing.
- **vs MacroFactor/Cronometer (nutrition)**: Atlas is ahead on capture (photo AI + barcode +
  label OCR + identity check beats both apps' scanning UX), behind on adaptive targets
  (MacroFactor's moat) and micronutrients (Cronometer's moat — probably a deliberate ignore).
  Missing conveniences: copy-day, water target UI.
- **vs Whoop/Athlytic/Bevel (recovery)**: Atlas has the inputs (HRV/RHR/sleep) and a recovery
  score, but no training-load/strain concept and no load↔recovery link — the core loop of that
  category. Performance Age is a reasonable engagement layer, not parity.
- **vs Gentler Streak / Apple Fitness**: habit/momentum system is competitive.
- **Realistic wins**: (1) scanning-first nutrition UX, (2) muscle-map-driven training insight,
  (3) the peptide/protocol niche where no polished competitor exists, (4) privacy-respecting AI
  summaries. **Should ignore**: full food-database ownership, micronutrient depth, social feeds,
  Whoop-grade strain modeling.

## Architecture Future State

```
UI (SwiftUI Features — thinner: flows split into per-step files)
 ↓ @Environment
Feature stores (Today / Train / Meals / Biology / Habits slices of today's DataStore)
 ↓
Domain engines (existing *Engine/*Logic — unchanged; + one unified StreakEngine)
 ↓
Repositories (SwiftDataRepository behind a protocol; single write path — no view → .shared)
 ↓
SwiftData/CloudKit (+ remote-change ingestion) · HealthKit (cached facade) · StoreKit ·
WCSession · Proxy clients
```

- **Remain**: the single-store Observation pattern (do NOT adopt heavy MVVM/TCA), the engine
  layer, the shell-model + JSON-blob SwiftData design for *low-churn* data, the proxy, the
  design system, the notification budgeter.
- **Split**: `UserProfile`'s high-churn arrays (mealHistory, habitEntries, labHistory,
  dailyConsumption) into per-record `@Model` rows — the pattern `StoredWorkoutSession` already
  proved. This one change fixes the LWW blob, the write amplification, and the record-size risk.
- **Move**: workout reads/writes behind one facade; JSON encoding off the main actor; deep-link
  mailboxes into a typed route queue.
- **Merge**: the three streak implementations; the two workout detail screens; the duplicated
  session→entry adapters.
- **Become protocols**: `SwiftDataRepository` (test seam) — and delete `DataServiceProtocol`.
- **Become actors**: none required — `@MainActor` + the existing patterns are sufficient;
  ThemeManager/LocalizationManager should become `@MainActor` observables, not actors.
- **Delete**: dead code list above.
- **Stay simple**: no modularization into SPM packages yet; no DI framework; no reactive layer.

## KEEP
Single-store architecture; memoization system; engine layer; scanning stack; muscle-map suite;
workout persistence invariant; rest timer; PR engine; notification budgeter; WCSession messaging
layer; Live Activity pipeline; proxy (auth/limits/App Attest); AuthService keychain hygiene;
backup import hardening; design system + enforcement; onboarding experiment/funnel infra;
1.4.1 mitigation framing; 3.1.2 metadata regime; CI pr-checks.

## IMPROVE
CloudKit sync (ingestion + dedup + blob split); save path (dirty flags, off-main encode); Today
(consolidate dose sections, add nutrition, rewire movement card); exercise detail page; Bio Age
(age-normalized thresholds, honest building state); adaptive nutrition targets; label OCR serving
math; entitlement grace period; weekly summary reachability (de-gate from doses); widget
timelines; HealthKit auth semantics + caching; streak unification; docs (HANDOFF/ROADMAP/
CLAUDE.md truthfulness).

## DEMOTE
HealthMonitorGrid on Today (Biology owns it); GoalCountdownCard; TodayJumpBar tab-duplicating
chips; TodayContextRow.

## REMOVE
Fake countdown timer; "4.9 · 12k+" social proof (until a real rating exists); dead code list;
ProtocolScoreCard (merge); legacy quick-log workout path + WorkoutDetailView; false claims in
metadata/review docs; database-dose fallback in reminders (require user-entered dose).

## FREEZE
Peptide database content expansion; new Biology surfaces; localization (until string extraction);
Swift 6 flip (until ThemeManager/LocalizationManager land); new AI features beyond the three that
exist; SPM modularization.

## BUILD NEXT
(after the fix waves) Routines/templates UI on the existing store; workout + rest-timer Live
Activity and a training widget; Watch set logging; adaptive nutrition targets; exercise progress
hub; training-load ↔ recovery link.

## DO NOT BUILD
An owned food database; micronutrient tracking; social/community feeds; a second AI provider or
generic chatbot surfaces; server-side user accounts/backend (the no-backend posture is a privacy
asset); Android/cross-platform; in-house analytics beyond the existing local funnel.

## P0 Fixes
1. Reconcile privacy manifest + label + description + privacy.html + Review Notes with
   RevenueCat and the three AI data flows; rewrite `APP_STORE_REVIEW_RESPONSE.md` (camera,
   HealthKit write, trials, AI). *Severity: rejection/false claims; effort: S; confidence: high.*
2. Remove/substantiate "4.9 · 12k+ athletes" (3 surfaces) and the fake countdown. *S; high.*
3. Fix `NSHealthShareUsageDescription`: add sleep, drop/qualify "all analysis on-device". *S; high.*
4. CloudKit integrity wave 1: subscribe to remote-change events + reconcile before
   `performSaveNow`; dedupe/merge `StoredProfile` rows on load; day-scoped entry dedup.
   *Data loss; effort: M–L; high on mechanism.*
5. Add `WEEKLY_SUMMARY_*` secrets to `ios-testflight.yml`; run server tests +
   checker self-tests in CI; gitignore `Secrets.xcconfig`; set a non-zero
   `ANTHROPIC_DAILY_REQUEST_BUDGET` in every deployment. *S; high.*

## P1 Fixes
Backup completeness (training tables + custom peptides → AppBackup v2); split profile blob
(high-churn arrays → own models); meal-edit aggregate resync; RevenueCat `recordPurchase` (or
remove the SDK and the claims problem with it); weekly-summary notification preserve-prefix +
deep-link handling; grace-period entitlement via subscription status; verify ASC intro-offer =
P7D (needs ASC access — highest-impact unknown); dead HK pipeline removal; progress-photo
downscale + async decode; peptides.json off the launch path; `loadEntries` windowing;
Watch complication data path (persist on watch + reload timelines); Today consolidation;
release.yml through PR checks.

## P2 Fixes
Streak unification (freeze-aware, one engine); StreakFreeze UTC day-key; fallback containers
`.none`; view→repo bypass cleanup; store peptide IDs not copies; SAVE-badge threshold alignment;
Pro gating vs listing copy (gate or stop selling); label-OCR serving handling; adaptive targets;
fiber decision; Bio Age cohort thresholds + building-state honesty; HK auth probe routing;
Swift 6 migration (ThemeManager first); god-file splits; `startWorkout` destructive path guard;
TrainOverview refresh hook; ExerciseDetailView progress hub; widget multi-entry timelines;
PendingDoseLogStore CAS-ish guard; missing P0/P1 test list (HealthKitService, WatchSyncService,
WeeklySummary trio, StreakFreeze, TimezoneChangeDetector).

## P3 Fixes
Note-preserving unlog; PR recompute on delete; adapter unification; nested NavigationStack;
widgetURLs; USD fallbacks; stale comments; orphaned localization keys; copy-day; a11y
value/hint pass; VoiceOver device run.

## Recommended Development Sequence
1. **Wave 0 — Truth (days):** P0 items 1–3 + 5. No feature risk, removes submission risk.
2. **Wave 1 — Integrity (1–2 sprints):** CloudKit wave 1, backup completeness, meal-edit resync,
   weekly-summary notification fixes, grace period, RevenueCat decision.
3. **Wave 2 — Foundation (1–2 sprints):** profile-blob split (behind the schema-V3 migration),
   save-path dirty flags, launch-path perf (peptides.json, loadEntries), dead-code removal,
   streak unification.
4. **Wave 3 — Product rebalance (2–3 sprints):** Today consolidation + nutrition section,
   training widget + workout/rest Live Activities, Watch set logging, exercise progress hub.
5. **Wave 4 — Retention (ongoing):** routines/templates, adaptive targets, load↔recovery link.
Swift 6 flip and localization ride along when their prerequisites clear.

---

# THE NEXT 10 THINGS ATLAS SHOULD DO

1. **Make every public claim true (metadata, privacy manifest/label, review notes, purpose
   strings, social proof, countdown).** Why: multiple independent P0 rejection vectors and a
   trust asset — the app's honesty framework — currently contradicted by its own marketing.
   User impact: none visible; Business: removes the largest submission risk; Technical: trivial.
   Dependencies: none. Difficulty: low. Before: decide RevenueCat's fate (it drives the label).
   NOT changed: the proxy architecture, the 1.4.1 framing, the storekit config.
2. **CloudKit integrity wave (remote-change ingestion, profile dedup, entry dedup).** Why: the
   only remaining everyday data-loss class. User: multi-device logs stop silently reverting;
   Business: data loss is the one unforgivable failure for a health log; Technical: unlocks
   trust in sync for everything later. Dependencies: none. Difficulty: medium-high (test on two
   devices). Before: write the two-device test plan. NOT changed: the upsert+deletion save
   design (keep it — extend it).
3. **Complete the backup (training tables + custom peptides).** Why: the designated no-iCloud
   recovery path loses the Train tab. Difficulty: low. Before: bump AppBackup to v2 with a
   decode-compat test. NOT changed: the import hardening pipeline.
4. **Split the profile blob.** Why: fixes LWW conflict loss, write amplification, and record-size
   risk in one move; the pattern is already proven by `StoredWorkoutSession`. Difficulty: high
   (migration). Dependencies: item 2 first (ingestion makes the migration safe to observe).
   Before: schema V3 plan + staged rollout. NOT changed: shell-model design for low-churn data.
5. **Fix the monetization integrity set (grace period, recordPurchase-or-remove-RC, ASC P7D
   verification, SAVE badge, gate-or-stop-selling Pro features).** Why: paying customers
   currently lose access on billing retry; analytics record nothing; the trial promise is
   unverified. Difficulty: low-medium; ASC check needs human access. NOT changed: StoreKit 2
   core, pessimistic eligibility.
6. **Ship the training glanceables (workout + rest-timer Live Activity, training widget, Watch
   set logging) and fix Watch complications.** Why: the single biggest positioning-vs-surface
   gap; retention lives on the wrist and Lock Screen. Difficulty: medium-high. Dependencies:
   none technical; reuse the excellent dose Live Activity pipeline. Before: Today consolidation
   design so the story is coherent. NOT changed: the dose pipeline itself.
7. **Consolidate Today.** One dose section instead of five, a nutrition section restored, the
   movement card rewired to Train, HealthMonitor demoted. Why: daily-open value and clarity —
   retention's front door. Difficulty: medium. Before: analytics on section engagement if any
   exist (funnel tracker is local; accept judgment). NOT changed: the habit hero, the trio, the
   derived-snapshot pattern.
8. **Routines/templates UI on the existing dead store.** Why: the #1 competitive gap vs
   Hevy/Strong; the persistence layer already exists. Difficulty: medium. Before: decide
   supersets/RPE scope (recommend: routines first, supersets second, skip %1RM). NOT changed:
   the logging flow.
9. **Performance wave (save-path dirty flags + off-main encode, launch-path decodes, progress
   photos, dead HK pipeline, entry windowing).** Why: the app gets slower every month a user
   stays; fix before the user base ages into it. Difficulty: medium. NOT changed: the
   memoization system.
10. **Adaptive nutrition targets + weekly summary for non-peptide users.** Why: closes the
    MacroFactor table-stakes gap and un-gates the recap from doses — the two changes that make
    the nutrition/recovery story self-sufficient. Difficulty: medium. Before: pick the
    adaptation model (simple trailing-expenditure estimate is enough). NOT changed: NutritionMath
    invariants.

# THE NEXT 5 THINGS ATLAS SHOULD NOT DO

1. **Do not rewrite the architecture (MVVM/TCA/SPM modularization).** The single-store +
   engines pattern is coherent, tested, and fast to develop in. The problems are specific
   (blob, sync, god-files), not systemic. A rewrite would burn the year for negative return.
2. **Do not build an owned food database or micronutrient tracking.** OFF + AI scanning is the
   differentiator; Cronometer's moat took a decade. The evidence bar set in this audit's brief
   ("strong evidence Atlas needs it") is not met.
3. **Do not expand the peptide surface (more entries, commerce-adjacent features, dose
   calculators).** The current framing survives 1.4.1 scrutiny because it is reference-shaped
   and demoted; every step toward recommendation-shaped increases the risk on the whole app.
   Maintain, don't grow.
4. **Do not flip Swift 6 / strict concurrency as a big-bang.** The debt is moderate and fenced;
   flip per-target after ThemeManager/LocalizationManager land, or the migration will block
   feature work for weeks with no user-visible gain.
5. **Do not ship the nine withheld localizations (or any new market surface) before string
   extraction reaches the 80% gate.** The English-only decision is safety-motivated and correct;
   ROADMAP's "Complete" claim is the bug, not the withholding. Similarly, do not add analytics
   SDKs — the "local-only, consent-gated" posture is a marketable asset the privacy copy can
   finally be truthful about.
