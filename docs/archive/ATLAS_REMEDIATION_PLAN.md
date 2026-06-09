# Atlas — Complete Remediation Plan

Branch: `claude/audit-onboarding-experience-LEVSs`
Companion docs: `ONBOARDING_AUDIT.md`, `ONBOARDING_ACTION_PLAN.md`

This is the **comprehensive plan** to close every open finding from the
six audit passes run on this branch. Items are grouped by priority
phase, each with effort, files touched, dependencies, and acceptance
criteria. Total scope: ~40 open items across 5 phases.

---

## Audits run (for reference)

1. **Initial onboarding audit** (3 agents) — flow, security, integration
2. **Polish-pass audit** (1 agent) — minimalism cuts
3. **Post-polish audit** (3 agents) — compile, security, integration
4. **Feature audit: Train** — workout logging
5. **Feature audit: Meals** — scanner + nutrition
6. **Feature audit: Biology + Insights + HealthKit** — biomarkers, weekly summary
7. **Feature audit: Library + Protocols + Sharing + StoreKit** — paywall, share cards

Already-shipped fixes: documented in commit log on the branch (~35 commits).

---

## Phase 0 — Build verification (BLOCKING, you own)

Cannot ship anything else without this. ~30 minutes.

| # | Item | Owner | Effort |
|---|------|-------|--------|
| 0.1 | `git pull` + `xcodegen generate` + `xcodebuild build` on iOS Simulator | You | 5 min |
| 0.2 | Paste any compile errors to me | You | 5 min |
| 0.3 | I patch | Me | reactive |
| 0.4 | `xcodebuild test` to verify the new test suites pass | You | 5 min |
| 0.5 | Walk the onboarding flow once on simulator | You | 10 min |

**Likely first-build risks**: SwiftData round-trip for `AffiliateApplication`,
the new `WorkoutSessionService.FinishedWorkout` struct call sites,
`Color(hex:)` UInt cast on any callers I missed.

---

## Phase 1 — Critical user-data + security (must ship before TestFlight)

12 items. ~3 working days. All within my reach.

### 1.1 — HealthKit selective-grant detection
**Severity**: CRITICAL — UI lies to user
**Audit**: Biology C1 + C2
**Files**: `Services/HealthKitService.swift`, `Features/Biology/BiologyView.swift`, `Features/Home/Components/HealthMonitorGrid.swift`
**Strategy**: After `requestAuthorization`, probe each read type by attempting an
`HKSampleQuery` with a 1-result limit. Surface a "Some types unavailable —
tap to fix in Settings" inline cue when count < 7. Track per-type grant on
`profile.healthGrantState: [HKQuantityTypeIdentifier: Bool]?`.
**Effort**: 4 hours
**Acceptance**: Grant only HRV in iOS Settings → reopen app → Bio Age card
shows "Connect sleep to unlock", Recovery card uses 2-of-3 partial math.

### 1.2 — Train H3: bodyweight habits never produce PRs
**Severity**: HIGH — user-data correctness
**Audit**: Train H3
**Files**: `Services/PRDetectionEngine.swift`
**Strategy**: A bodyweight push-up at 0 kg should still log a `repsPR`. Replace
`bestE1RM > 0` threshold with `bestReps > existingRecord.bestReps`. Add
explicit `.bodyweightReps` `DetectedPR` case.
**Effort**: 2 hours + 2 hours tests
**Acceptance**: 25 push-ups → PR fires. 30 next session → another PR fires.

### 1.3 — Spotlight recipe deep-link silently dropped
**Severity**: HIGH — user action ignored
**Audit**: Meals HIGH 1
**Files**: `Features/Home/Components/HomeMealsSection.swift`, `Features/Lifestyle/Components/FoodLibraryFlow.swift`
**Strategy**: Promote `pendingFoodLogID` consumption out of first-mount only.
On `appState.pendingFoodLogID` change while sheet is already up, dispatch
`resolveDeepLink(newValue)` into the live FoodLibraryFlow via a new
`onDeepLinkChange` binding.
**Effort**: 2 hours
**Acceptance**: Open FoodLibrary on Meals tab → tap recipe in Spotlight →
recipe sheet presents over the existing library.

### 1.4 — MealsContainerView double-mount fires duplicate sheets
**Severity**: HIGH — UX broken when both Today + Meals tabs mounted
**Audit**: Meals MED 10
**Files**: `Features/Home/Components/HomeMealsSection.swift`, `Features/Meals/MealsContainerView.swift`
**Strategy**: Either remove HomeMealsSection from Today (was "Phase D" intent
per the file comment), or gate the deep-link sheet on `appState.selectedTab`.
Recommend: deprecate the Today-tab mirror entirely and surface a single
"View meals" link instead.
**Effort**: 3 hours (decision: remove mirror)
**Acceptance**: Spotlight tap from anywhere lands one sheet, no double-stack.

### 1.5 — `OpenFoodFactsService` kJ/kcal ambiguity silently logs 4× less calories
**Severity**: HIGH — user-data correctness on legacy US barcodes
**Audit**: Meals MED 5
**Files**: `Services/OpenFoodFactsService.swift`
**Strategy**: Read `nutriments["energy-kcal_100g"]` first. Only fall back to
`energy_100g` after inspecting `nutriments["energy_unit"]` — reject the
divide-by-4.184 unless unit is verified kJ.
**Effort**: 2 hours + curl-fixture tests
**Acceptance**: A barcode with `energy_unit: "kcal"` and `energy_100g: 2000`
returns 2000 kcal, not 478.

### 1.6 — Train M1: set-delete unreachable (.swipeActions outside List)
**Severity**: HIGH — user can't delete a misclicked set
**Audit**: Train M1
**Files**: `Features/Train/Components/SetEditorRow.swift`, `Features/Train/Components/WorkoutExerciseCard.swift`
**Strategy**: Replace `.swipeActions` with an inline trash-icon button visible
on long-press OR migrate the sets `VStack` to `List` (heavier refactor).
Recommend: long-press → confirmation menu with Delete.
**Effort**: 3 hours
**Acceptance**: Long-press a set row → "Delete this set" appears → tap →
set removed.

### 1.7 — Train H1: custom-exercise creation UI missing
**Severity**: HIGH — niche-lift users have no path
**Audit**: Train H1
**Files**: `Features/Train/ExerciseLibraryView.swift`, `Features/Train/ExercisePickerSheet.swift`, new `Features/Train/CustomExerciseEditorSheet.swift`
**Strategy**: Add "Create custom exercise" CTA in the picker's empty-result
state and as a permanent footer row. Sheet collects name + primary muscle
+ secondary muscles + equipment. Submits via existing
`SwiftDataRepository.upsertCustomExercise`. Reload library on save.
**Effort**: 6 hours
**Acceptance**: Search "landmine" → empty → tap "Create" → land in new
exercise editor → save → new entry appears in picker.

### 1.8 — Train H2: rest timer entirely absent
**Severity**: HIGH — feature claimed in ROADMAP, doesn't exist
**Audit**: Train H2
**Files**: `Features/Train/ActiveWorkoutView.swift`, `Features/Train/Components/SetEditorRow.swift`, new `Features/Train/Components/RestTimerOverlay.swift`
**Strategy**: When user taps the complete-set circle, kick a countdown using
`TrainingPreferences.restTimerDefault` (or per-exercise override). Overlay
sits above the keyboard with skip/extend/end buttons. Local notification
fires when app is backgrounded so user knows when to start the next set.
**Effort**: 8 hours
**Acceptance**: Complete a set → 90s timer appears → background app → push
notification at 90s "Time to lift".

### 1.9 — Train C2 follow-up: WorkoutHistoryView needs detail navigation
**Severity**: MEDIUM-HIGH — history list lacks per-session drill-down
**Audit**: Train C2 partial follow-up
**Files**: `Features/Train/WorkoutHistoryView.swift`, new `Features/Train/WorkoutSessionDetailView.swift`
**Strategy**: Wrap each row in `NavigationLink` to a detail view that shows
per-exercise sets, PRs detected at the time, perceived effort, notes.
**Effort**: 4 hours
**Acceptance**: Tap row → detail view → all sets listed → back to history.

### 1.10 — Biology HIGH 7: Bio Age dataDays approximation
**Severity**: HIGH — gives confident readings on 1 day of data
**Audit**: Biology H7
**Files**: `Services/BioAgeStateResolver.swift`, `Services/HealthKitService.swift`
**Strategy**: Add `HealthKitService.actualHRVDayCoverage()` that runs an
`HKSampleQuery` over the past 30 days and returns `Set<Date>` of days with
samples. Resolver passes the real count to `PerformanceAgeEngine`.
**Effort**: 4 hours
**Acceptance**: 1 day of HRV → confidence < 0.4 → "Building baseline" copy.
30 days of HRV → confidence > 0.9 → real Bio Age estimate.

### 1.11 — Biology HIGH 8: WeeklySummary cache key TZ bug
**Severity**: HIGH — cache misses + wrong week payload for east-of-UTC users
**Audit**: Biology H8
**Files**: `Services/WeeklySummaryEngine.swift`, `Services/WeeklySummaryService.swift`
**Strategy**: Replace `ISO8601DateFormatter` with a hand-formatted
`yyyy-MM-dd` from a Calendar set to user's TZ. Add a one-time migration
that re-keys any cached summaries from UTC → local key (or just bumps the
cache key version to `v2`).
**Effort**: 3 hours
**Acceptance**: JST device computes weekStart that matches the
locally-visible week, cache round-trips.

### 1.12 — Sharing P1.6: per-protocol card shows global adherence
**Severity**: HIGH — misleading data on a shareable artifact
**Audit**: Sharing P1.6
**Files**: `Features/Sharing/CycleCardModel.swift`, `App/DataStore.swift`
**Strategy**: Add `DataStore.adherence(forProtocol: UUID) -> Double` that
filters entries by `protocolId` before computing. `CycleCardModel.forProtocol`
consults that instead of `dataStore.averageCompliance`.
**Effort**: 2 hours + tests
**Acceptance**: User with two protocols (one 90%, one 30%) shares the 30%
one → card shows 30%, not the global average.

---

## Phase 2 — Should ship soon (revenue + UX correctness)

11 items. ~2 working days. All within my reach.

### 2.1 — Lifetime tier surfaced on PaywallView
**Audit**: Library P1.10
**Files**: `Features/Profile/Components/PaywallView.swift`
**Strategy**: Add a third pricing card next to annual + monthly. Label "Best
value · One-time payment" with a "LIFETIME" badge. Use the same
`startMonthlyTrial` → `purchase(lifetimeProduct)` plumbing.
**Effort**: 3 hours

### 2.2 — Savings badge 0% edge case
**Audit**: Library P1.9
**Files**: `Features/Profile/Components/PaywallView.swift`
**Strategy**: Switch from `Int` cast to `Int(round(...))` and lower the
display threshold to `>= 5%` so a real 8% saving renders as "8% OFF"
instead of "0% OFF" hidden.
**Effort**: 30 min

### 2.3 — Pending purchase feedback in `PaywallView` (not just TrialOfferView)
**Audit**: Library P0.5 partial
**Files**: `Features/Profile/Components/PaywallView.swift`
**Strategy**: Switch the `_ = try await storeService.purchase(product)` call
to `storeService.purchaseWithOutcome(product)`; surface pending as inline
banner "Awaiting approval — we'll unlock Pro automatically."
**Effort**: 1 hour

### 2.4 — Pro biomarkers persist after downgrade
**Audit**: Biology MED 11
**Files**: `Features/Biology/BiomarkerListSection.swift`
**Strategy**: Filter `visibleBiomarkers` by `storeService.isProUser ||
!biomarker.isProTier` before rendering. Pro user who lapses sees only the
free tier; their saved Pro choices re-appear on re-subscribe.
**Effort**: 1 hour

### 2.5 — Biomarker units honor `profile.bodyMetrics.unit`
**Audit**: Biology MED 10
**Files**: `Features/Biology/Biomarker.swift`, `Services/BiomarkerSeriesService.swift`
**Strategy**: `Biomarker.displayUnit(for: MeasurementUnit)` returns "lb" /
"in" / "°F" when imperial. `BiomarkerRow` + detail sheet + change-text
formatter all consume it.
**Effort**: 3 hours

### 2.6 — `LabEntryEditor` input validation
**Audit**: Biology MED 12
**Files**: `Features/Labs/Components/LabEntryEditor.swift`
**Strategy**: Per-biomarker reasonable ranges (e.g. testosterone 100-2000
ng/dL). `DatePicker(in: ...today)` to reject future dates. Inline error
chip on out-of-range.
**Effort**: 4 hours

### 2.7 — Meals MED 7: duplicate-scan protection
**Audit**: Meals MED 7
**Files**: `Features/Lifestyle/Components/BarcodeScanFlow.swift`
**Strategy**: Before confirm, check if `dataStore.profile.mealHistory` has an
entry with the same `sourceID` in the last 60 minutes. If yes, show an
"Already logged 30 minutes ago — log again?" confirmation.
**Effort**: 2 hours

### 2.8 — Meals MED 9: MealEntryEditor allows full macro + time edit
**Audit**: Meals MED 9
**Files**: `Features/Lifestyle/Components/MealEntryEditorSheet.swift`
**Strategy**: Add inline number fields for calories/protein/carbs/fat and a
date picker. Submit via `dataStore.updateMealEntry`. Removes the
"delete-and-re-log" footer copy that breaks history.
**Effort**: 4 hours

### 2.9 — Insights / Pause-nudge / "+N" pill follow-ups
**Audit**: Library P2.13–15
**Files**: `Features/Sharing/ShareCardRenderer.swift`, `Features/Protocols/ProtocolBuilderView.swift`, `Features/Sharing/CycleCardModel.swift`, `Features/Home/Components/HabitsHomeCard.swift`
**Strategy**:
- `ShareCardRenderer.filename` → drop the `peptidex-` prefix
- ProtocolBuilderView preview label → "1080 × 1920" (matches actual export)
- Unify `forStack` vs `forProtocol` cycleDay clamping → both use `max(1, ...)`
- HabitsHomeCard "+N" chip → swap to `arrow.up.right.square` icon
**Effort**: 1 hour total

### 2.10 — Sharing P1.8 follow-up: also mask injection-site references
**Files**: `Features/Sharing/CycleCardView.swift`
**Strategy**: Audit-pass already noted "Injection sites are never shared" — but
verify the share card doesn't render any site info under maskCompoundNames.
**Effort**: 30 min

### 2.11 — Empty workout session can't be exited gracefully (Train M3)
**Audit**: Train M3
**Files**: `Features/Train/ActiveWorkoutView.swift`, `Services/WorkoutSessionService.swift`
**Strategy**: On `scenePhase == .background` with `completedSetCount == 0`,
auto-discard after a 24h timeout. Or expose Discard on the toolbar
regardless of state.
**Effort**: 2 hours

---

## Phase 3 — Architectural / scale fixes (1-2 weeks)

7 items. These are bigger refactors — best done in a separate branch with
real test coverage and a TestFlight cohort to catch regressions.

### 3.1 — Habits CloudKit blob bloat (Habits H3)
**Severity**: HIGH — silent failure at year 2-3 for power users
**Audit**: Habits H3
**Strategy**: Split `HabitEntry` out of `ProfileExtension` into a separate
SwiftData `@Model` `StoredHabitEntry` keyed by `(habitId, day)`. CloudKit
syncs per-record instead of as part of the profile blob. Migration: read
existing `profile.habitEntries`, write to SwiftData, drop the field from
ProfileExtension.
**Effort**: 2-3 days incl. migration testing
**Risk**: Real data loss if migration is wrong. Feature-flag for one
TestFlight cycle.

### 3.2 — HabitsView heatmap rebuild on every render (Habits M3/M4)
**Strategy**: Memoize summaries + heatmaps via a custom `EquatableView`
wrapper or `@State` cache keyed by `(habitId, entriesHash)`. SwiftUI will
skip re-render when the inputs haven't changed.
**Effort**: 4 hours
**Risk**: Stale-cache bugs if invalidation is wrong.

### 3.3 — Habit reminder scheduling (Habits M10)
**Severity**: MEDIUM — UI implies working reminders; reality is no-op
**Strategy**: Extend `NotificationService` with
`scheduleHabitReminder(_ habit: Habit) async`. One `UNCalendarNotificationTrigger`
per scheduled day for `.weekdays`, one for daily, one morning nudge for
`.timesPerWeek`. Identifier scheme `"habit.\(uuid).\(weekday)"`.
DataStore mutators (`addHabit/updateHabit/archiveHabit`) call
`NotificationService.refreshHabitReminders(for: habit)`.
**Effort**: 1 day

### 3.4 — Lab PDF OCR (Biology MED 13)
**Severity**: MEDIUM — feature claimed in ROADMAP but doesn't exist
**Strategy**: Mirror `MealScannerService` pattern — Claude vision endpoint
with structured output schema for biomarkers. UI: `LabPDFImportSheet` →
`PhotosPicker` or `DocumentPicker` for PDF → Claude vision call →
review/edit extracted values → bulk save via `setLabValue`.
**Effort**: 2 days
**Dependency**: Vercel proxy already exists; just add `/api/lab-ocr` endpoint.
You own the proxy work.

### 3.5 — AI Research real streaming (Library P1.11)
**Severity**: LOW-MED — feature claims streaming but isn't
**Strategy**: Switch `AIResearchService.send` to `URLSession.bytes(for:)`
SSE parser. Stream tokens into a `@Published var streamingReply`. UI
shows tokens as they arrive instead of a static spinner.
**Effort**: 1 day
**Dependency**: Vercel proxy needs to forward streaming (not buffer).

### 3.6 — Background-delivery observer on simulator (Biology MED 14)
**Severity**: LOW — simulator-only behaviour
**Strategy**: When `enableBackgroundDelivery` throws on simulator, still
register the observer query for foreground refreshes. The error means "no
BG delivery", not "no observers at all".
**Effort**: 1 hour

### 3.7 — Funnel-tracker drain plumbing
**Severity**: MEDIUM — local data only, can't run cohort analysis
**Strategy**: `OnboardingFunnelTracker.drain(to: URL) async throws` POSTs
the snapshot. Mark drained snapshots in UserDefaults so retries are idempotent.
You wire the endpoint to PostHog/Supabase.
**Effort**: 4 hours my side, 1 day backend yours

---

## Phase 4 — Polish / nice-to-haves (1 week, low priority)

15 items. Ship in small batches between TestFlight cycles.

### 4.1 — Train calendar locale (M2)
Monday-pivot is hardcoded — respect `Calendar.current.firstWeekday`.
30 min.

### 4.2 — Train M4: addExercise carries previous weight
After exercise picked, seed first set with `lastCompletedSet` weight rather
than 0. (Hooks into Train C1's existing `lastCompletedSet` helper.)
30 min.

### 4.3 — Train M5: MuscleGroup/AnatomicalMuscle abductors inconsistency
Pick canonical mapping (glutes recommended) and update both files. 15 min.

### 4.4 — Train M6: WeeklyMuscleHeatmap calendar-day window
`Calendar.startOfDay(for: cutoff)` instead of `addingTimeInterval(-7*86400)`.
30 min.

### 4.5 — Train low items (L1–L6)
VoiceOver labels on SetEditorRow, exercise picker empty state fallback,
deep-link support in TrainNavigation, etc. 3 hours total.

### 4.6 — Meals L11: `NutritionMath` calorie sum mismatch
Round macros first, then derive calories from `proteinG*4 + carbsG*4 +
fatG*9` so the sum always equals the displayed calories. 30 min.

### 4.7 — Meals L12: `NutritionMath.activityMultiplier` user-configurable
Add `activityLevel` to `BodyMetrics` or `TrainingPreferences`; default
moderate. Onboarding's experience step could feed this. 2 hours.

### 4.8 — Meals L13: HealthKit zero-macro samples
Write explicit zero samples so Apple Health daily totals reflect the
complete day. 30 min.

### 4.9 — Meals L14: `NSPhotoLibraryAddUsageDescription` for future save-to-library
Add to `Info.plist` so it's there when you add the feature. 5 min.

### 4.10 — Meals L15: Dinner→snack at 22:00 cutoff is too early
Move cutoff to 22:30 or surface a soft "We picked Snack — change?" prompt.
15 min.

### 4.11 — Biology L16-L20: RecoveryScoreEngine isPartialData false-flag,
WeightDelta30d window, WeeklySummary weekday locale-blindness,
OfflineFormatter chip visibility, BiomarkerSeriesService sample threshold.
3 hours total.

### 4.12 — Library P2.14: weekNumber doesn't show cycle number
Add a `cycleNumber` computed on `PeptideProtocol` so `MiniStat` reads
"Cycle 3 · Week 2". 1 hour.

### 4.13 — HabitEditSheet IconGrid wrap on Form row
Verify on iPad and adjust to scroll if grid overflows. 1 hour QA + fix.

### 4.14 — Onboarding goal+date scroll-to-reveal on iPhone SE
`ScrollViewReader.scrollTo(goalDateAnchorID)` after goal pick so the date
chips pull into view automatically. 1 hour.

### 4.15 — Habits L7: `timesPerWeek` engagement gate
`HabitsService.weeklyProgress(for:entries:) -> (count: Int, target: Int)`
helper; HabitsHomeCard shows "2 of 3 this week" for those habits. 3 hours.

---

## Phase 5 — Strategic / external (your call)

Things that need product decisions or external infrastructure.

### 5.1 — Decide HealthKit data minimization
**Question**: do we want to ask for all 7 types up-front, or split into
"core" (HRV, sleep) and "extended" (RHR, weight, steps, energy, height)?
Apple's selective-grant friction is real. Worth A/B testing.

### 5.2 — Decide peptide branding scope (revisit)
The rebrand to "Atlas — health & fitness" is live, but PeptideDetailView,
PeptideListView, AIResearchView, ProtocolBuilderView still use the
peptide-tracker language. Should those tabs:
- Stay as-is (advanced users understand peptide context)
- Be renamed (Library → Stack, Protocols → Schedule, etc.)
- Be moved behind a "Stack" tab that aggregates them

This is a multi-day rewrite if you go with option B or C.

### 5.3 — Backend: Promo offer JWT signing for creator codes
Per ROADMAP item 5.1 / original HANDOFF note 4. The creator code captures
+ displays the discount but no price modification happens. Wiring requires
App Store Connect promo offers + server-signed offer JWT.
**Effort**: 1 day infra, 4 hours app integration.

### 5.4 — Backend: Funnel analytics drain
Stand up Supabase or PostHog endpoint, plug `OnboardingFunnelTracker.drain`
in. Local snapshot already structured for 1:1 replay.

### 5.5 — Backend: Email retargeting (Resend)
`EmailSubscription` records ride local-only today. Wire to Resend with a
7-day cron job that re-engages users who didn't convert. Email template
+ unsubscribe flow needed.

### 5.6 — Backend: Affiliate intake endpoint
`AffiliateApplication` records ride local-only. Wire to a creator-program
intake endpoint (Supabase RPC or similar). Review queue + dashboard.

### 5.7 — Watch app verification
Per HANDOFF — scaffold exists but needs real-device testing. Build the
PeptideWatch target in Xcode, verify dose-toggle round-trip works on
paired devices.

### 5.8 — iPad layout pass
Per ROADMAP — `PeptideListView` already branches on `horizontalSizeClass`.
Apply the same `NavigationSplitView` treatment to Home / Lifestyle /
Profile. Multi-day pass on actual iPad.

### 5.9 — App Store metadata + screenshots refresh
Reflect the Atlas health & fitness positioning. Update
`APP_STORE_METADATA.md`, screenshots in `docs/app-store/`, App Store
Connect description.

### 5.10 — Localization
The new English copy from this branch needs translation into the 9
declared locales (es, zh-Hans, ja, de, fr, pt-BR, ko, ru, ar). Run via
your existing translation pipeline.

---

## Execution sequence — what to land in what order

```
WEEK 1 — Phase 0 + start Phase 1
  Day 1   Build / test / smoke (B1-B5 from earlier action plan)
  Day 2   Phase 1.1 (HK grant probe)
  Day 3   Phase 1.2 (bodyweight PR) + 1.3 (Spotlight recipe)
  Day 4   Phase 1.4 (Meals double-mount) + 1.5 (OFF kcal)
  Day 5   Phase 1.6 (Train set-delete) + 1.10 (Bio Age days) + 1.11 (TZ cache)

WEEK 2 — Finish Phase 1, ship to TestFlight
  Day 1-3 Phase 1.7 (custom exercise) + 1.8 (rest timer)
  Day 4   Phase 1.9 (workout detail) + 1.12 (per-protocol adherence)
  Day 5   TestFlight beta build

WEEK 3 — Phase 2 (revenue + UX)
  Day 1-2 2.1 (lifetime tier) + 2.2 (savings badge) + 2.3 (pending)
  Day 3   2.4-2.6 (biomarker units, validation, Pro-gating)
  Day 4   2.7-2.8 (meals dup + editor)
  Day 5   2.9-2.11 (polish bundle)

WEEK 4 — TestFlight #2, gather feedback
  Real-user pass. Watch for issues from Phase 1 fixes on real devices.
  Fix anything blocking; defer rest to phase 3.

WEEK 5-6 — Phase 3 (architectural)
  Habit CloudKit split is the big one. Branch from main, feature-flag,
  TestFlight to 5-10 users for one cycle, then promote.

WEEK 7+ — Phase 4 (polish) ships in small commits between TestFlight cycles.

PHASE 5 items happen as the backend / product decisions are made.
```

---

## Acceptance gates per phase

**Phase 1 done = all Critical and High audit findings closed.** Test plan
includes: deny-all HealthKit, bodyweight workout, Spotlight recipe tap from
deep within the app, free-tier protocol cap probe via every entry point,
JST device weekly summary cache round-trip, share card with single-protocol
adherence, full Train flow (start → log → finish → see PR → see in History).

**Phase 2 done = all P1 / revenue items closed.** Acceptance includes:
purchase all three tiers, Pro biomarker disappears on downgrade and
reappears on re-up, lab value rejection on out-of-range, duplicate barcode
scan within an hour gets prompt.

**Phase 3 done = no architectural debt above MEDIUM remains.** Acceptance
includes: power user with 5 years × 5 habits relaunches without blob
serialization stall, habit reminders fire on the configured days even from
cold start, lab PDF OCR extracts a real bloodwork PDF accurately.

**Phase 4 done = backlog cleared.** No specific gate; ship as time allows.

**Phase 5 done = product strategy locked + backends stood up.** Outside
this engineering plan.

---

## What I can execute vs what you own

**I can execute end-to-end (Phases 1, 2, 3, 4):**
~50 distinct fixes, mostly self-contained. Ship in batches; commit and
push as I go.

**You own (Phase 0 + Phase 5):**
- Build verification + paste compile errors back to me
- Real-device testing (iPhone + iPad + Watch)
- TestFlight uploads + tester recruitment
- App Store Connect product config (lifetime tier price)
- Vercel proxy updates (lab OCR endpoint, AI streaming)
- Backend stand-up (Supabase / PostHog / Resend)
- Apple Developer config (capabilities, signing)
- Strategic calls in §5.1, §5.2
- App Store metadata + screenshots
- Localization through your translator pipeline

**We collaborate on:**
- Phase 3.1 (CloudKit habit split) — I write the migration, you
  TestFlight-verify before promoting
- Phase 1.1 (HK probe) — I write per-type detection, you confirm UX on
  real device with selective grant
- Phase 1.8 (rest timer) — I write logic, you tune default rest seconds
  with real workouts

---

## How to drive this

Pick a starting point and tell me. Highest impact-per-effort:
1. **Phase 0** — do it now, ~30 min
2. **Phase 1.1, 1.2, 1.3, 1.5, 1.6, 1.10, 1.11, 1.12** in that order — all
   ~2-4 hours each, ship as one batch with one TestFlight build
3. **Phase 1.7, 1.8, 1.9** — biggest Train-tab fixes; recommend a separate
   day each
4. **Phase 2** as a single sprint once Phase 1 is in TestFlight
5. **Phase 3** as its own branch
6. **Phase 4** as time permits
