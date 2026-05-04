# Codebase Audit Prompt

> Copy-paste this entire prompt into a Claude Code session to perform a full runtime-correctness audit of PeptideX.

---

You are performing a runtime-correctness audit of **PeptideX** — a native iOS SwiftUI app (Swift 6.0 strict concurrency, deployment target iOS 18.0) for tracking peptide supplementation protocols. The codebase is mature: a single `@MainActor @Observable` `DataStore` (~600 LOC) holding `protocols: [PeptideProtocol]`, `entries: [ProtocolEntry]`, `profile: UserProfile`, `customPeptides: [Peptide]`; an 827-LOC `StackRecommendationEngine` split across `+Context`, `+Scoring`, `+Warnings`; a hybrid persistence layer (`SwiftDataRepository` canonical + legacy JSON via `PersistenceService` + `MigrationService`); 5-tab navigation (Home, Peptides, Protocols, Analytics, Profile); 14 achievements; StoreKit 2 paywall; bundled `peptides.json` (208 peptides, ~931 KB); Apple Watch app + 4 widget surfaces; 10 localizations; and 17+ XCTest files. The app is **health-adjacent** — dose data integrity is non-negotiable.

This is a **bug hunt**, not a rewrite. Find runtime failures, data-loss paths, and concurrency violations and fix them with minimal, surgical edits.

## NON-NEGOTIABLE CONSTRAINTS

- **Swift 6 strict concurrency**: All `DataStore` mutations and SwiftUI state writes must remain on `@MainActor`. Cross-actor hops via `Task { @MainActor in ... }` or `MainActor.assumeIsolated` are intentional — flag missing isolation, not present ones.
- **`DataStore` is the single source of truth**. Views read it via `@Environment(DataStore.self)`. Never mutate `protocols` / `entries` / `profile` / `customPeptides` from outside `DataStore` methods.
- **Cache invariants**: `cacheVersion` MUST increment on every mutation of `protocols` or `entries` (the `didSet` blocks do this — never bypass). Day-rollover-dependent caches (`todayEntries`, `weeklyCompletion`, `currentStreak`, `nextDose`) MUST call `bumpVersionIfDayChanged()` before reading. Reading any of these from a non-`@MainActor` context is a bug.
- **Persistence path**: All writes go through `DataStore.save()` → `SwiftDataRepository`. Direct `UserDefaults` / `FileManager` calls outside `PersistenceService` / `SwiftDataRepository` / `Logger` are violations.
- **Migration ladder**: `MigrationService.shared.migrateIfNeeded()` runs in `PeptideApp.init`. Any new persisted field added since the last shipped version requires a migration step. Never silently change the persisted shape.
- **Notification limit**: iOS allows **64** scheduled local notifications app-wide. `NotificationService` enforces this with per-protocol consolidation and a `lastReport.droppedProtocolIDs` audit trail — never schedule directly via `UNUserNotificationCenter`. Bypassing this is a P0 bug.
- **HealthKit is read-only**. PeptideX never writes to Apple Health. Any `HKHealthStore.save(...)` call is a bug.
- **Recommendation safety**: `StackRecommendationEngine+Warnings` is medical-adjacent. Warnings (interaction, contraindication, redundant signal, dose-stacking, cycle conflict, frequency conflict, beginner risk) MUST be returned for unsafe stacks. A regression that suppresses a warning is P0.
- **Subscription gating**: Free-tier limit (3 active protocols), Pro-only features (full analytics, HealthKit correlation, all widgets, Watch, cloud sync) flow through `StoreService` entitlement checks. Bypassing entitlements in non-test code is a bug.
- **Localization**: New user-facing strings go to `Peptide/Resources/Localizable.xcstrings` and are accessed via `String(localized:)` or `LocalizedStringKey`. Hardcoded English strings in views are bugs.
- **No `print` in shipping code** — use `Logger` (`os.Logger` wrapper). `print` calls are bugs.
- **Dark color scheme is forced**: `.preferredColorScheme(.dark)` at the root. Never override per-view.
- **Preflight**: After fixes, run `xcodebuild test -scheme Peptide -destination 'platform=iOS Simulator,name=iPhone 16'` plus `swiftlint --strict`.

---

## Context Loading (read these first, in this exact order — parallelise where the harness allows)

If a stated path is missing, say so explicitly rather than fabricating.

1. **`CLAUDE.md`** — coding standards, context-management rules, plugin inventory
2. **`ROADMAP.md`** — what's shipped (v1.0), what's queued (v1.1 reliability, v2.0 SwiftData/CloudKit, v2.5 ecosystem, v3.0 AI/community). Don't propose work that's already on the roadmap as a "bug."
3. **`Peptide/App/PeptideApp.swift`** — `@main` entry, scene phase handling, biometric lock gate, notification authorization flow, `tabViewBottomAccessory` (iOS 26+) wiring
4. **`Peptide/App/DataStore.swift`** (~600 LOC) — every mutation path; understand the cache layer (`cacheVersion`, `bumpVersionIfDayChanged`, `_todayEntries`, `_currentStreak`, `_bestStreak`, `_nextDose`, `_weeklyCompletion`, `_entriesByDay`)
5. **`Peptide/App/AppState.swift`** + **`Peptide/App/NotificationDelegate.swift`** — tab state, foreground notification routing, action handlers
6. **`Peptide/Models/`** — `Peptide.swift`, `PeptideCategory.swift`, `PeptideProtocol.swift` (note `peptideSchedules: [UUID: ProtocolSchedule]` per-peptide overrides), `ProtocolEntry.swift`, `ProtocolStatus.swift`, `UserProfile.swift`, `WeekDayStatus.swift` — single source of truth for shapes
7. **`Peptide/Services/SwiftDataRepository.swift`** — canonical persistence, fallback-store handling, `isInoperable` / `isUsingFallbackStore` flags
8. **`Peptide/Services/PersistenceService.swift`** + **`Peptide/Services/MigrationService.swift`** — JSON legacy + migration ladder. Note current schema version.
9. **`Peptide/Services/NotificationService.swift`** — 64-limit consolidation, `ScheduleReport`, action categories (`Mark as Taken` / `Snooze`)
10. **`Peptide/Services/StackRecommendationEngine.swift`** + extensions (`+Context`, `+Scoring`, `+Warnings`) — 12-signal scoring, 7 warning types, validated stacks
11. **`Peptide/Services/StackAdjustmentEngine.swift`** — alterations to existing stacks (clickable alerts feature)
12. **`Peptide/Services/OnboardingRecommendationEngine.swift`** — onboarding-time recommendation
13. **`Peptide/Services/DailyScheduleEngine.swift`** — schedule expansion to dose entries; off-by-one risks live here
14. **`Peptide/Services/HealthKitService.swift`** — read-only authorization, background delivery, observer queries
15. **`Peptide/Services/StoreService.swift`** — StoreKit 2 transaction stream, entitlement source of truth
16. **`Peptide/Services/AchievementService.swift`** — 14 achievement IDs, toast pipeline
17. **`Peptide/Services/AuthService.swift`** + **`Peptide/Services/BiometricService.swift`** — Sign in with Apple + Face ID lock
18. **`Peptide/Services/WatchSyncService.swift`** + **`Shared/WatchData.swift`** + **`Shared/WidgetData.swift`** — App Group payloads
19. **`Peptide/Services/ExportService.swift`** — CSV / JSON export (PDF planned, not shipped)
20. **`Peptide/Services/ReviewPromptService.swift`** — review-prompt timing rules
21. **`Peptide/Services/LocalizationManager.swift`** — runtime locale override; the `.id(...)` modifier in `PeptideApp.swift` re-renders the tree on locale change
22. **`Peptide/Data/PeptideDatabase.swift`** + **`Peptide/Data/SwiftDataModels.swift`** + **`Peptide/Data/PeptideCompatibilityData.swift`** + **`Peptide/Data/PeptideTimingData.swift`** — peptide knowledge base
23. **`Peptide/Resources/Products.storekit`** — productID truth: `com.peptidesai.app.pro.monthly` / `com.peptidesai.app.pro.annual` / `com.peptidesai.app.pro.lifetime`. Subscription group `73E561C3-3E5C-4246-BA5E-C40ABB32278D`.

After context load, state: **"Context loaded. Migration version=N. Services loaded: [count]. Recommendation engine warning types: [count]. Proceeding to Phase 1."**

---

## Phase 1: Discovery — DO NOT FIX YET

Scan systematically. Focus order: `DataStore` mutations → persistence layer → `NotificationService` → `StackRecommendationEngine+Warnings` → `DailyScheduleEngine` → tab views (Home, Protocols, Database, Analytics) → `StoreService` → onboarding flow.

### Critical (data-loss, medical-safety, or crash)

- **Data loss on save failure** — `SwiftDataRepository` falls back to in-memory; any path that overwrites the user's protocols/entries with an empty array on load failure is P0
- **Cache desync** — a mutation on `protocols`/`entries` that bypasses the `didSet` (e.g. `protocols[index].peptides.append(...)` is fine because didSet fires on the `[index]` subscript reassignment, but mutating a nested struct's stored property through a non-mutating function is not — verify)
- **Day-rollover bugs** — readers of `todayEntries` / `currentStreak` / `weeklyCompletion` / `nextDose` that don't go through `DataStore` (so don't trigger `bumpVersionIfDayChanged`) — surfaces stale data after midnight
- **Notification overflow** — anything that schedules without going through `NotificationService.shared.scheduleNotifications(for:)` and respecting the 64-limit consolidation
- **Suppressed safety warnings** — `StackRecommendationEngine+Warnings` returns must reach the UI uncensored. Filter / sort / dedup that drops a warning category is P0.
- **Off-by-ones in `DailyScheduleEngine`** — weekday math (`isoDayOfWeek = dayOfWeek == 1 ? 7 : dayOfWeek - 1`), preferred-time parsing (`h:mm a` with `Locale(identifier: "en_US_POSIX")`), cycle-week boundaries
- **Concurrency violations** — non-`@MainActor` access to `DataStore`/SwiftUI state, missing `await` on async repo calls, `Task` without explicit isolation
- **HealthKit writes** — any `HKHealthStore.save(_:withCompletion:)` is forbidden; we are read-only
- **Receipt-trust regressions in `StoreService`** — accepting a `Transaction` without `verificationResult.payloadValue` checks, or treating `.unverified` as entitled
- **Notification authorization race** — flow in `PeptideApp.mainContent`: deny path must clear scheduled notifications and persist the toggle. Verify no orphaned notifications survive a denial.
- **Biometric lock bypass** — any path from `LockScreenView` → `mainContent` that doesn't set `isUnlocked = true`, or any path that re-renders `mainContent` without re-evaluating `isUnlocked` after backgrounding
- **CloudKit / SwiftData inconsistencies** — `repo.isCloudSyncEnabled` reflected truthfully in UI; conflict resolution; partial-fetch on cold start

### High Priority

- **Force-unwraps and `try!`** in production paths
- **Empty `catch {}` blocks** swallowing errors silently — at minimum `Logger.app.error(...)` them
- **Stub / TODO / FIXME / HACK** in shipping code
- **`@State` that should be `@Observable` / `@Bindable`** — leaks across re-renders
- **`ObservationIgnored` misuse** — used to skip cache invalidation tracking is correct; used to skip user-visible state is a bug
- **Locale-sensitive date parsing without `Locale(identifier: "en_US_POSIX")`** — schedule preferred-times use `"h:mm a"` and MUST pin POSIX locale; user-facing displays use `.formatted(...)` and SHOULD use the device locale
- **Notification consolidation mistakes** — same protocol scheduled twice on a reschedule, missing cancellation on protocol delete, ghost reminders after `status` flip to `.paused`/`.completed`
- **Achievement double-fire** — `AchievementService.shared.checkAchievements` re-firing for an already-unlocked ID across sessions
- **Streak edge cases** — missed day in middle of week, day with zero scheduled doses, timezone change while app is backgrounded
- **Widget timeline staleness** — `WidgetCenter.shared.reloadAllTimelines()` not called after relevant mutations; App-Group write race
- **Watch sync drift** — `WatchSyncService.onMarkComplete` toggling an entry that's already complete, or for a stale entry ID (deleted protocol)
- **Dead nav routes** — `appState.selectedTab = .x` where `x` isn't a `case` of `AppTab`

### Medium Priority

- **Duplicated logic** — same helper reimplemented across services (check `DailyScheduleEngine` and `EntryGrouping` first; canonical home is `Services/`)
- **Hot-path perf** — O(n²) inside list views, unmemoised expensive computations in body of high-frequency-redraw views (Home, Today's doses)
- **Inefficient `entriesByDay` callers** — recomputing instead of reading the cached property
- **Unused `@Environment` properties** — leak retain-cycles in long-lived `@Observable` classes
- **Mixed Swift Charts API usage** — inconsistent axis configuration across `Analytics/Components/`
- **`UserDefaults` writes outside `PersistenceService`** — direct calls bypass migration

### Low Priority

- **Hardcoded English strings** — every user-visible string belongs in `Localizable.xcstrings`
- **Hardcoded magic numbers** that should live near `Theme/`, `AnimationConstants.swift`, or recommendation-engine config
- **Stale comments** that no longer match the code
- **Missing `accessibilityLabel`** on icon-only buttons; missing Dynamic Type support on custom typography

---

## Phase 2: Report

> **Reason before classifying.** For every Critical candidate, trace the failing path: what user action triggers it? Which line crashes / corrupts state? Which warning gets suppressed? A nullable access is only a bug if the code path can reach it with the value nil. Downgrade `[HIGH]` confidence if you can't trace a concrete path.

Output every finding as:

```xml
<issue id="N" severity="critical|high|medium|low">
  <location>relative/path.swift:line</location>
  <category>Concurrency | Cache | Persistence | Migration | Notifications | Recommendation Safety | Entitlements | HealthKit | Watch | Widget | Locale | Stub | Dead Code | Perf | Accessibility | Other</category>
  <problem>One sentence: what's wrong.</problem>
  <repro>One sentence: the user action or state that triggers it.</repro>
  <fix>One sentence: minimal change.</fix>
  <confidence>HIGH | MEDIUM | LOW</confidence>
</issue>
```

`HIGH` = code path traced to failure. `MEDIUM` = strong pattern match with a known failure mode. `LOW` = heuristic, needs verification.

**Phase 2 checkpoint** — state: `"Phase 2 complete. Found N critical, N high, N medium, N low. Proceeding to Phase 3."`

If >25 issues, fix Critical + High first and ask before continuing.

---

## Phase 3: Fix

Work Critical → Low. For each:

1. Read the file (if not already loaded)
2. Make the **minimal** focused fix — never refactor surrounding code
3. Mark the issue resolved by ID
4. **Behavioural-change gate**: if the fix touches `DataStore.swift`, `MigrationService.swift`, `SwiftDataRepository.swift`, `NotificationService.swift`, `StackRecommendationEngine*.swift`, or `StoreService.swift` beyond a one-line correction → flag and ask before proceeding

Special cases:
- **Persistence-shape changes** → bump `MigrationService` version, add a migration step, add a round-trip test in `PeptideTests/PersistenceRoundTripTests.swift`. Never silently change the schema.
- **New persisted field** → ensure default value covers fresh install AND migrated install.
- **Notification logic** → add or extend a test in `PeptideTests/NotificationServiceTests.swift` that asserts the 64-limit consolidation invariant.
- **Recommendation warning** → add or extend a case in `PeptideTests/StackRecommendationEngineTests.swift` proving the warning still fires for the unsafe stack.
- **Swift 6 isolation fix** → confirm the change compiles under strict concurrency without `@preconcurrency` escape hatches.

**Phase 3 checkpoint** — state: `"Phase 3 complete. Fixed N. Running test suite."`

Then run:

```
swiftlint --strict
xcodebuild test -scheme Peptide -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
```

If anything fails, investigate root cause — never `// swiftlint:disable` or skip a test. Stage only the files you touched (no `git add -A`).

---

## Rules

- DO NOT refactor working code that has no bug — this is a bug hunt
- DO NOT add features, comments, or docs
- DO NOT reformat, restyle, or reorganise unless that's literally the bug
- DO NOT modify a test unless the test itself is wrong (wrong assertion, not a test failing because of a real bug)
- DO NOT introduce a new dependency, plugin, or Swift package
- DO NOT bypass `swiftlint --strict` or skip the test scheme — fix root causes
- DO NOT touch `Peptide/Resources/Products.storekit` unless the bug is literally a product-ID typo
- DO NOT move work that's already on `ROADMAP.md` into the bug list — that's feature work, not a bug
