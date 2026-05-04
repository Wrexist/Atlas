# Longevity, Data-Integrity & Stress Testing Prompt

> Copy-paste this entire prompt into a Claude Code session to perform deep data-integrity bug hunting and long-term reliability testing on PeptideX.

---

You are running an exhaustive longevity, data-integrity, and stress test of **PeptideX** — a SwiftUI iOS 18+ health-tracking app where dose data is **safety-critical** (users plan their supplementation around what's logged). The codebase is mature: a single `@MainActor @Observable` `DataStore`, hybrid persistence (`SwiftDataRepository` canonical + legacy JSON via `PersistenceService` + `MigrationService`), an 827-LOC `StackRecommendationEngine` with 7 warning types, `NotificationService` enforcing the iOS 64-notification limit, and an existing test surface of 17+ XCTest files (`DataStoreTests`, `StackRecommendationEngineTests`, `PersistenceRoundTripTests`, `MigrationServiceTests`, `NotificationServiceTests`, `DailyScheduleEngineTests`, `AchievementServiceTests`, `OnboardingRecommendationEngineTests`, `StackAdjustmentEngineTests`, `InsightEngineTests`, `PeptideDoseCalculatorTests`, `BodyMetricsTests`, `AuthServiceTests`, `ExportServiceTests`, `HealthKitBackgroundDeliveryTests`, `LocalizationManagerTests`, `ReviewPromptServiceTests`).

The test goal: **365+ days of simulated usage**, **multiple cycle transitions**, **timezone changes**, **app version migrations**, **64-notification overflow**, and **CloudKit conflict scenarios** — with zero data loss, zero suppressed safety warnings, zero notification overflow, and stable performance.

**Existing tests are canonical — read them before writing one. Duplicate scenarios are a code-review blocker.**

## NON-NEGOTIABLE CONSTRAINTS

- **Swift 6 strict concurrency**: All test code that touches `DataStore` runs on `@MainActor`. Mark test methods that touch the store with `@MainActor` or wrap in `await MainActor.run`.
- **Use the existing test scaffolding** — the `DataStore.init(seedSampleData:)` constructor is your fixture entry point. Don't recreate it.
- **Use `MockProtocols`, `MockEntries`, `MockProfile`, `MockPeptides`** for fixtures — don't duplicate fixture data
- **Persistence tests use a temporary `SwiftDataRepository`** — never the real shared instance. Inspect `PersistenceRoundTripTests` for the pattern.
- **Migration tests** — import the migration version constant; never hardcode a version number
- **Dose-data integrity is sacred** — a test that loses an entry, even in an edge case, is a P0 finding even if the production path "never reaches" that state
- **Notification limit (64) is hard** — every test that schedules notifications must assert the consolidation invariant from `NotificationService.lastReport`
- **HealthKit is read-only** — any test that asserts a write to HealthKit is wrong
- **Run `swiftlint --strict`** before marking any phase complete; never bypass
- **Use the StoreKit configuration** (`Peptide/Resources/Products.storekit`) for purchase-related tests — the `_failTransactionsEnabled` flag is your knob

---

## Phase 0: Inventory the Existing Test Stack

Before writing any test, list and read:

### Canonical infrastructure (read fully)
1. **`PeptideTests/`** — list every file; for each, note the scenarios covered (one line each)
2. **`Peptide/App/DataStore.swift`** init paths — understand the seed flow, the cache layer, day-rollover handling
3. **`Peptide/Services/SwiftDataRepository.swift`** — fallback-store conditions; `isInoperable` / `isUsingFallbackStore`
4. **`Peptide/Services/MigrationService.swift`** — version constant, migration steps shipped to date
5. **`Peptide/Services/NotificationService.swift`** — 64-limit consolidation algorithm, `ScheduleReport` shape

### Multi-day / longevity surfaces (read fully)
6. **`PeptideTests/DataStoreTests.swift`** (~7.9 KB, 20 tests) — baseline coverage; what's the longest-running scenario?
7. **`PeptideTests/PersistenceRoundTripTests.swift`** (~14.9 KB, 23 tests) — round-trip patterns; gaps if any
8. **`PeptideTests/MigrationServiceTests.swift`** (~6.6 KB) — migration ladder coverage
9. **`PeptideTests/StackRecommendationEngineTests.swift`** (~27.5 KB, 39 tests) — the safety-critical engine; verify warning coverage by type
10. **`PeptideTests/NotificationServiceTests.swift`** (~9.9 KB) — 64-limit assertions
11. **`PeptideTests/DailyScheduleEngineTests.swift`** (~7.9 KB) — schedule expansion edges
12. **`PeptideTests/InsightEngineTests.swift`** (~9.1 KB) — insight generation
13. **`PeptideTests/AchievementServiceTests.swift`** (~7.1 KB) — achievement unlock invariants
14. **`PeptideTests/StackAdjustmentEngineTests.swift`** (~9.5 KB) — alteration suggestions
15. **`PeptideTests/OnboardingRecommendationEngineTests.swift`** (~4.8 KB) — first-stack recommendation
16. **`PeptideTests/PeptideDoseCalculatorTests.swift`** (~4.5 KB) — vial / dose math
17. **`PeptideTests/BodyMetricsTests.swift`** (~4.4 KB) — metric persistence and validation

### Service tests
18. **`PeptideTests/AuthServiceTests.swift`** — Sign in with Apple state machine
19. **`PeptideTests/ExportServiceTests.swift`** — CSV/JSON export roundtrip
20. **`PeptideTests/HealthKitBackgroundDeliveryTests.swift`** — background delivery toggling (read-only)
21. **`PeptideTests/LocalizationManagerTests.swift`** — locale override + RTL handling
22. **`PeptideTests/ReviewPromptServiceTests.swift`** — prompt-timing rules

After loading, output:
```xml
<existing-coverage>
  <data-store>What DataStore scenarios are covered, longest simulated duration, mutation paths exercised.</data-store>
  <persistence>SwiftData round-trip status, JSON-legacy round-trip, fallback-store handling.</persistence>
  <migration>Versions covered by tests, missing migration steps if any.</migration>
  <notifications>64-limit overflow coverage, action-handler tests.</notifications>
  <recommendation-engine>Coverage by warning type (interaction / contraindication / redundant / dose-stack / cycle / frequency / beginner-risk).</recommendation-engine>
  <schedule-engine>Day-of-week edges, time-zone, DST, h:mm a parsing edges.</schedule-engine>
  <storekit>Purchase / restore / fail / billing-issue coverage.</storekit>
  <healthkit>Auth / background-delivery / read paths.</healthkit>
  <watch-widgets>Sync / payload-shape / App Group writes.</watch-widgets>
  <gaps>The 5 biggest gaps in priority order.</gaps>
</existing-coverage>
```

---

## Phase 1: Multi-Day Simulation Stress

> Before writing, **state which file you'll extend** vs. which you'll create. Default to extending; only create if the scenario doesn't fit any existing file.

### 1A. 365-Day DataStore Lifecycle
Extend `DataStoreTests.swift` if not covered. Simulate a full year:
- Each day: `regenerateTodayEntries()`, toggle 80% of doses, occasionally pause/resume a protocol, occasionally edit schedules, occasionally add/remove peptides mid-protocol
- After each simulated day:
  - `protocols`/`entries`/`profile` round-trip through `SwiftDataRepository` cleanly
  - `cacheVersion` invariant: every mutation path increments, every cache reader sees a consistent snapshot
  - `currentStreak` / `bestStreak` / `weeklyCompletion` / `nextDose` recompute correctly after `bumpVersionIfDayChanged` simulation (manipulate `Calendar.current` via a test calendar)
  - `entries` count remains bounded (no unbounded growth from `appendTodayEntries` reruns — the idempotency guard must hold)
  - `WidgetData` payload size stays <16 KB (App Group write efficiency)
- After 365 days, validate: no `NaN` compliance, no negative streak, no future-dated `actualTime`, `totalDaysLogged` ≤ 365, every entry's `protocolId` resolves to an existing protocol or a deleted one with explicit handling

### 1B. Cycle Transitions
Most protocols have `cycleLengthWeeks: Int`. Simulate 3 cycles:
- Mid-cycle pause → resume: schedule continuity preserved, entry generation correct from resume date
- Cycle end → status `.completed`: today's entries stop generating, history preserved
- Cycle end → user starts next cycle: new protocol, history of previous cycle visible in `seasonHistory`-equivalent (achievements, total doses)
- Washout period (gap between cycles): no scheduled doses, streak handles correctly (does it pause or break?)

### 1C. Timezone Travel
- Start in PST, simulate a flight, switch device timezone to JST
- `nextDose` recomputes against new timezone
- `todayEntries` rolls over correctly (the user's "today" changes)
- Streak calculation honours the device timezone, not UTC
- DST forward and backward transitions: no doubled or missing entries on the boundary day

### 1D. Schedule Edge Cases
Extend `DailyScheduleEngineTests`:
- Weekday math: `dayOfWeek == 1` (Sunday) → ISO 7. Verify Sunday-only protocols generate on Sundays.
- Preferred-time parsing: `"h:mm a"` with `Locale(identifier: "en_US_POSIX")`. Verify under device locale set to French, German, Japanese (must still parse `"8:00 AM"`).
- Times-per-day = 1, 2, 3, 4 — generation correctness for each
- Per-peptide schedule overrides (`PeptideProtocol.peptideSchedules`): when peptide A has a custom schedule and peptide B uses the protocol default, both must resolve correctly on the same day
- Adding a peptide mid-day: `addPeptide(toProtocolId:)` must remove only the new peptide's entries for today before regenerating, never wipe other peptides' progress

### 1E. Mutation Storm
- 1,000 rapid `toggleEntry` calls on the same entry — final state stable, no doubled save races
- `updateProtocol` mid-day with reduced peptide list — entries for removed peptides stripped from today, remaining peptides' completion preserved
- Delete protocol while a notification action is mid-flight — `WatchSyncService.onMarkComplete` for a deleted entry must no-op gracefully

### 1F. Recommendation Engine Coverage by Warning Type
Extend `StackRecommendationEngineTests`:
- **Interaction warning**: build a stack that triggers it. Assert it returns. Add a peptide that should *not* trigger it, assert silence.
- Same for **contraindication, redundant signal, dose-stacking, cycle conflict, frequency conflict, beginner risk**
- Asymmetry test: stack A+B vs. stack B+A produce same warnings (order-independence)
- Empty stack → no warnings, no crash
- 1-peptide stack → no interaction warnings
- `BodyMetrics`-sensitive recommendations — the score with metrics vs. without should differ predictably
- `experienceLevel`-sensitive: beginner-risk warnings on a beginner profile, suppressed on advanced

### 1G. Stack Adjustment Engine
Extend `StackAdjustmentEngineTests`:
- Unsafe stack → suggested edits resolve every warning (the engine's job)
- Safe stack → no edits suggested
- Cycling-conflict stack → cycle-shift suggestion or peptide-removal suggestion, never both
- Adoption of a suggestion produces a stack that itself passes the recommendation engine cleanly (round-trip)

> **Phase 1 checkpoint**: state `"Phase 1 complete. Tests written: [list]. Tests already covered: [list]. All pass: [yes/no]. Proceeding to Phase 2."`

---

## Phase 2: Persistence, Migration & Recovery

### 2A. SwiftData Round-Trip Stress
Extend `PersistenceRoundTripTests`:
- Save a 365-day, 5-protocol, ~3,000-entry dataset → reload → byte-equal? Date-precision-equal? UUID-stable?
- Save with `actualTime`, `actualDose`, `injectionSite`, `notes` populated → reload preserves
- Save with `peptideSchedules` overrides set on 2 of 4 peptides → reload preserves dictionary keys exactly
- Save with `customPeptides` populated → reload preserves and the database union (`peptideDatabase`) reflects them

### 2B. Migration Ladder
Extend `MigrationServiceTests`:
- For every prior persistence schema, a fixture file roundtrips through the migration ladder to current
- A save with a missing optional field migrates without throwing; defaults populate correctly
- A save with an unknown future version triggers graceful degradation, never an empty-state wipe
- A save with a corrupted single record is quarantined; the rest of the dataset survives (the `||` not `&&` invariant in `DataStore.init`)

### 2C. Fallback-Store Behaviour
- `repo.isInoperable == true` → `lastError` banner set; mutations succeed in-memory; warning visible to user
- `repo.isUsingFallbackStore == true` → in-memory writes work, `lastError` set, app remains usable
- Recovery: on next launch with a working repository, persisted state from before the fault loads (the fault didn't overwrite good data)

### 2D. CloudKit / SwiftData Conflict (per ROADMAP v2.0)
If cloud sync is partially wired (`isCloudSyncEnabled` reflected somewhere):
- Two-device simulation: device A logs entry X, device B logs entry Y simultaneously → both survive after merge
- Conflicting edits to the same protocol on two devices → last-writer-wins or field-level merge — verify the chosen strategy and assert it
- Offline-first: device offline, logs entries, comes online, syncs, no duplicates
- If cloud sync is *not* yet implemented, document that explicitly rather than fabricating tests

> **Phase 2 checkpoint**: `"Phase 2 complete. Persistence tests: [list]. Migration tests: [list]. All pass: [yes/no]. Proceeding to Phase 3."`

---

## Phase 3: Notification Integrity

### 3A. 64-Limit Consolidation
Extend `NotificationServiceTests`:
- 1 protocol, 3 peptides, 4 timeslots/day, 7 days/week = 84 raw reminders. Verify consolidation algorithm reduces below 64 (likely by per-timeslot bundling per `ROADMAP.md` description) without losing schedule coverage.
- 5 active protocols simultaneously: assert which protocols get dropped, assert `lastReport.droppedProtocolIDs` populated, assert `DataStore.droppedReminderProtocolNames` returns the right names sorted
- Pause a protocol mid-day: its scheduled reminders cancel cleanly
- Delete a protocol: its scheduled reminders cancel cleanly
- Toggle `doseRemindersEnabled` off: all scheduled reminders cancel
- Toggle back on without changing protocols: reminders restored to the previous state

### 3B. Action Handler Routing
Extend `NotificationServiceTests` or create `NotificationDelegateTests`:
- "Mark as Taken" action delivered → routed via `NotificationDelegate` → `DataStore.toggleEntry` invoked with correct entry ID
- "Snooze" action → reschedules in 15 minutes (or whatever the configured snooze is); other day's reminders unaffected
- Action received for a deleted entry → graceful no-op, no crash
- Action received while app cold-launching → deferred until `DataStore` is ready

### 3C. Authorization State Machine
- `.notDetermined` → request → granted → schedules
- `.notDetermined` → request → denied → toggle off + cancel all + persist
- `.denied` on launch → cancel all + toggle off + persist (current `PeptideApp.mainContent` flow — verify via test)
- `.authorized` on launch → reschedule for active protocols

---

## Phase 4: Performance & Memory

### 4A. DataStore Read Hot-Paths
Extend `DataStoreTests`:
- `todayEntries` — average <2ms over 1,000 reads (cache hit). First read after invalidation <20ms.
- `currentStreak` over a 365-day dataset — average <5ms cached, <50ms cold
- `weeklyCompletion` — same budgets
- `entriesByDay` — same; this is the foundation cache

### 4B. Save Path
- `save()` over a 5-protocol, 3,000-entry dataset — <100ms p50, <200ms p99 on iPhone 14 simulator
- WidgetData write + WidgetCenter reload — <30ms
- WatchSync update — <30ms
- AchievementService check — <10ms

### 4C. Memory Footprint
- Cold launch → peak memory after first render <80 MB on iPhone 14 simulator with full 208-peptide DB loaded
- Background → foreground after 1 hour idle — no memory growth
- Open every tab once — cumulative memory growth <10 MB (no view-tree leaks)

### 4D. Bounded State
- `entries` — verify no unbounded growth across 365 days. Old entries (>1 year) — are they pruned, archived, or kept forever? Confirm and document.
- `customPeptides` — unbounded by design; assert at least no per-launch duplication
- WidgetData — bounded to top 3 upcoming doses (per `DataStore.updateWidgetData`)

### 4E. Render Hot-Paths
- `HomeView` re-render count when toggling a single dose — should be 1, not N (no reactive thrash from cache invalidation)
- `ProtocolListView` row stagger — doesn't drop frames on first mount with 3 protocols
- `AnalyticsView` Swift Charts — first render <100ms with 365 days of data

---

## Phase 5: Localization & Accessibility

### 5A. Locale Coverage
Extend `LocalizationManagerTests`:
- For each of the 10 locales (`en`, `es`, `zh-Hans`, `ja`, `de`, `fr`, `pt-BR`, `ko`, `ru`, `ar`):
  - `String(localized: ...)` resolves for every key in `Localizable.xcstrings`
  - No missing-translation fallback to English (a smoke test that grep counts equal counts in source)
  - RTL (Arabic) flips layout direction; verify `LocalizationManager.layoutDirection` correct
  - Date / time / number formatting goes through `.formatted(...)` not hardcoded format strings
- Pluralization correctness: "1 dose" vs. "N doses" varies by locale; verify xcstrings plural rules

### 5B. Accessibility
- Every icon-only button has an `accessibilityLabel`
- Dynamic Type up to `.accessibility5` doesn't truncate critical content in `HomeView`, `ProtocolListView`, paywall
- `accessibilityReduceMotion` honoured (animations gracefully degrade per the `app-feel-polish` audit)
- VoiceOver: `GlassProgressRing` exposes percentage as a label, `weeklyCompletion` exposes day-by-day status
- High Contrast: glass blur surfaces have sufficient text contrast

---

## Phase 6: Triage & Fix

### Priority 1 — Data-Loss / Safety
- Any path that loses a logged dose entry
- Any path that suppresses a recommendation engine warning
- Save corruption that survives across launches
- Notification overflow that drops critical-time reminders silently
- Migration that drops a field on the way to current schema
- Cache desync that surfaces stale `currentStreak` / `weeklyCompletion` to the user

### Priority 2 — Functional Bugs
- Schedule generation off-by-one (timezone, DST, weekday math)
- Day-rollover entries duplicating or missing
- Notification action routed to wrong entry
- StoreKit purchase / restore broken
- HealthKit auth state inconsistent with stored profile
- Watch sync miss / duplicate complete

### Priority 3 — Performance / Footprint
- Cache miss rates >20% during normal use
- `save()` latency exceeding budgets
- Memory growth from view-tree retention
- WidgetData write race

### Priority 4 — Localization & Accessibility
- Hardcoded English in user-visible code paths
- Missing accessibility labels
- Reduce-motion regressions

For every fix:
1. Read the file
2. Make the surgical change
3. Add or extend the test
4. State the issue ID, fix, and that the test now passes

Run:

```
swiftlint --strict
xcodebuild test -scheme Peptide -destination 'platform=iOS Simulator,name=iPhone 16'
```

before marking done.

---

## Deliverables

1. **Inventory** — what's already covered, top-5 gaps
2. **New test files / extensions** — listed by path, with the scenarios they exercise
3. **Bug list** — severity, location, repro, fix
4. **Persistence proof** — 365-day round-trip green, every shipped migration version round-trips
5. **Notification proof** — 64-limit consolidation invariant asserted
6. **Recommendation proof** — every warning type has an assertion that fires + an assertion that doesn't fire
7. **Perf budgets enforced** — added to the relevant test files
8. **Localization proof** — every locale has key coverage
9. **All fixes applied** — lint + tests green
