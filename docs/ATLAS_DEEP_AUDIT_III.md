# Atlas — Deep Audit III (Full File-by-File Coverage Sweep)

Unlike Deep Audit I (phased remediation plan) and II (six thematic
deep-dives), this audit is a **coverage sweep**: every one of the
~481 Swift files is read and reported, organized by directory section.
Each file gets a purpose line and any findings; clean files are marked
clean so coverage is explicit and nothing is silently skipped.

Findings deduped against Deep Audit I (`ATLAS_AUDIT_AND_POLISH_PLAN.md`)
and II (`ATLAS_DEEP_AUDIT_II.md`) — those remain the source of truth for
already-cataloged items; this document records what those passes did not.

**Severity:** Critical = crash / data loss / security / wrong health
number / App Store rejection · High = broken feature / lost revenue /
real race · Medium / Low = correctness or polish.

**Status:** 🔄 in progress — sections fill in as the per-section
agents report.

| # | Section | Files | Status |
|---|---------|-------|--------|
| 1 | App + Intents | 21 | ✅ 21/21 |
| 2 | Models | 28 | ✅ 28/28 |
| 3 | Data + Shared + Watch/Widgets | 25 | ✅ 25/25 |
| 4 | DesignSystem | 40 | ✅ 40/40 |
| 5 | Services A | 40 | ✅ 40/40 |
| 6 | Services B | ~37 | ⏳ |
| 7 | Features/Home | 48 | ⏳ |
| 8 | Features/Meals | 33 | ⏳ |
| 9 | Features/Profile | 28 | ⏳ |
| 10 | Features/Train | 24 | ⏳ |
| 11 | Features/Protocols | 22 | ⏳ |
| 12 | Features/Biology+Labs+Library+Database | 26 | ⏳ |
| 13 | Features/Onboarding+Habits+AIResearch+Auth+Sharing+WeeklySummary | 32 | ⏳ |
| — | server/ | 9 | ✅ covered by Deep Audit I & II |

---

## Section 1 — App + Intents (21/21 files)

Most files clean (AppState, EntryAnalytics, RecipeDataLogic,
VialInventoryLogic, WidgetSnapshotBuilder, IntentDataStore, the food/
recipe entities). `DataStore.swift` carries the weight of the findings.

**High**
- **`DataStore.swift` `applyImport` (~1984-2013) — restore-import can ghost-delete CloudKit-delivered records.** The diff-based delete classifies any protocol/entry ID present on disk but not yet in the in-memory arrays (e.g. records a CloudKit sync delivered since the last `reloadFromDisk`) as "dropped" and deletes them, propagating the deletion to CloudKit — the same class the main save path fixed with `pendingProtocolDeletions`, still open in the import path. *Fix:* track/exclude pending-deletion IDs, or drop the diff-delete and rely on upsert (accepting orphan records over silent deletion). *(Verify against current line numbers before fixing.)*
- **`DataStore.swift` `updateProtocol` merge (~530-558) — second daily dose lost on edit.** The completion-preserve dedup matches on `peptide.id` alone, so for a `timesPerDay: 2` protocol both the AM and PM logged entries match the same key and one is overwritten when the protocol is edited. *Fix:* match on the full scheduled time (minute granularity), not just `peptide.id`.

**Medium**
- **`DataStore.swift` `setPeptideSchedule` (~564-610) — no completion rescue.** Unlike `updateProtocol`, it `removeAll`s and regenerates today's entries with no completed-entry preservation; logging a dose then changing that peptide's schedule loses the logged dose. *Fix:* port the `updateProtocol` completion-preserve block.
- **`LabDataLogic.swift:75` — trend noise-floor divide-by-zero.** `threshold = abs(previous.value) * 0.05` is 0 when a prior lab value is exactly 0, bypassing the noise floor so any delta reads as a trend. *Fix:* guard `previous.value != 0`.
- **`LifestyleDataLogic.swift:383-406` — dead code post-Plan C.** `logWorkout`/`deleteWorkout`/`workoutSummary` still write/read the legacy `profile.workoutHistory` array that `DataStore.logWorkout` now bypasses (routes through the repo); any caller reaching these creates zombie entries never rendered. *Fix:* delete them (CLAUDE.md "no dead code").
- **`NotificationDelegate.swift:43-71` — `MARK_TAKEN` toggles by `(protocolId, hour, minute)`.** Embeds no entry UUID, so a `timesPerDay: 2` protocol toggles both slots from one notification. *Fix:* put the entry UUID in `userInfo`.
- **`NotificationDelegate.swift:26-38` — snooze `center.add(request)` drops errors.** No completion handler; a scheduling failure vanishes silently. *Fix:* use the completion-handler overload and log.
- **`PeptideApp.swift:403-449` — notification setup `.task` lives on a computed `mainContent` view** and can re-fire on view rebuilds (delegate swap is not idempotent). *Fix:* move to a one-shot `.task` on `WindowGroup` or guard with a `@State` flag.
- **`PeptideIntents.swift:63-66` + `PeptideEntity.swift:64-66` — double `MainActor.run` hop** in `entities(matching:)` (every sibling uses one); collapse to a single hop for Siri-resolution latency.
- **`LogMealIntent.swift:44-47` — `foodID.split(separator:).last`** is fragile for malformed multi-colon IDs; use `maxSplits: 1`.

**Low / Consider**
- `PeptideApp.swift:299` + `:286` — `try?` on `Task.sleep` before showing the What's-New tour can skip it on fast background/foreground cycles; and `bootstrapForFreshInstallIfNeeded` called mid-onboarding *might* stamp the version seen and suppress the tour — **flagged uncertain**, verify `WhatsNewService`.
- `DataStore.swift:1694` `saveDebounceMs: UInt64` cast to `Int64` at use; `:625/:631` redundant double `bumpVersionIfDayChanged()`; `bestStreak` (active-only) vs `totalDaysLogged` (all) diverge for paused protocols — document or reconcile.
- `LifestyleDataLogic.swift:436` per-call `ISO8601DateFormatter` allocation on main-thread hot paths.
- `TravelModeLogic.swift:95-107` two identical `DateFormatter`s; `ShowStreakIntent.swift:58-62` concatenated `LocalizedStringResource` breaks RTL.

**Disputed (recorded, not actioned):** `DataStore.swift:1882-1910` achievement-check flag "TOCTOU" — the agent itself notes all code is `@MainActor` with serial Task enqueue, so concurrent execution is impossible; it's a readability/flag-semantics nit, not a race.

---

## Section 3 — Data + Shared + Watch/Widgets (25/25 files)

Clean: the training `@Model`s, `PeptideAtlasSchema`, compatibility/
timing data, `MockProfile/Protocols`, `WidgetData`, `CrossProcessNotification`,
the three Watch views (DoseListView, DoseRowView, WatchStatsView).

**High**
- **`Shared/PendingDoseLogStore.swift:47-55` — `enqueue` dedup TOCTOU** (already C7). Two processes (Live-Activity double-tap) both read before either writes, so `!current.contains(log)` doesn't hold → double-log. *Simplest fix:* stop deduping in `enqueue`; let duplicates land and dedupe on `drain` (single actor) — cheaper than `NSFileCoordinator`.

**Medium**
- **`PeptideWatch/Services/WatchStore.swift:116-126` — `isSending` can stick `true` forever.** On the reachable path `isSending` is cleared only in `sendMessage`'s `replyHandler`; if the phone deactivates mid-flight and neither reply nor error handler fires, every further Watch tap is permanently disabled. *Fix:* add a ~10s watchdog that forces `isSending = false`.
- **`MockEntries.swift:20` — the "seeded" generator isn't seeded.** It seeds from `protocol_.name.hashValue`, but Swift `String.hashValue` is per-process randomized, so preview/screenshot data differs every launch — defeating `SeededGenerator`. *Fix:* use a stable hash (`utf8.reduce(0){ $0 &* 31 &+ UInt64($1) }`).
- **`SwiftDataModels.swift:102, 333` — silent corruption wipes data to defaults.** `EncodedSchedule` and `BodyMetrics` decode via `try?`, so a genuinely-corrupt blob is indistinguishable from a legacy payload and silently resets the user's schedule/metrics with no log. *Fix:* take the bare-fallback only on `DecodingError.keyNotFound`; log+rethrow other errors (mirror the `ProfileExtension` path already in the file).
- **`PeptideWatch/PeptideWatchApp.swift:26-30` — conditional Nutrition tab resets the pager.** Omitting the tab when `nutrition == nil` means a WCSession push that flips it non-nil changes the tab count and SwiftUI jumps the user back to page 0. *Fix:* always insert the tab, show an empty state inside when nil.
- **`WatchStore.swift:91-103` — optimistic `totalToday = updated.count`** overwrites the phone-authored total; if the phone filtered entries the compliance ring flickers wrong until next sync. *Fix:* keep `watchData.totalToday`.
- **Widget file reads swallow IO errors** — `PeptideWidgets.swift:112,384`, `PeptideWatchWidgets.swift:66`, both Watch/iOS providers use `try? Data(contentsOf:)`; a partial write (crash mid-write) renders an empty widget silently. *Fix:* distinguish file-not-found (expected) from real errors and log; consider coordinated reads.
- **`DoseWindowLiveActivity.swift:597-605` — `Color(hex:)` duplicated** from the app target; any RGB-extraction drift gives the widget a different vial tint than the app. *Fix:* move the helper to `Shared/`.
- **`LogDoseLiveActivityIntent.swift:48-50, 69-79` — silent drops:** a malformed `entryId` returns `.result()` with no log; `activity.update` is awaited without `try/catch` so a since-ended activity throws unhandled. *Fix:* log the bad UUID; wrap the update in `do/catch`.
- **`PeptideDatabase.swift:185` — `stableUUID(from:)`** bit-shifts `id >> 32` (always 0 for 1-208 IDs, misleading) and falls back to a random `UUID()` on malformed hex (non-deterministic). *Fix:* format the literal directly; treat malformed hex as a programming error, not a silent random ID.

**Low / Consider**
- `WatchNutritionView.swift:57-74` water buttons share `isSending` with dose toggles — unnecessary mutual exclusion; split the flags.
- `PeptideWidgets.swift:500` `ForEach(meals, id: \.category)` fragile to duplicate categories — key on offset like the dose row does.
- `SwiftDataModels.swift:6-16` + `+Training.swift` — four duplicated JSON codec singletons; consolidate to one internal file.
- `MockPeptides.swift:18-28` random `UUID()` per launch for fallback fixtures — fix IDs if any test references them.
- `PeptideDatabase.swift:131` synchronous ~750KB bundle load on first `.shared` access (main thread); fast in practice, document or background it.

**Verified clean (recorded):** `WatchStore` correctly omits `didReceiveUserInfo` — `transferUserInfo` flows Watch→phone and the phone's `WatchSyncService` handles it; only relevant if a future phone→Watch `transferUserInfo` is added.

---

## Section 2 — Models (28/28 files)

Clean: CommunityStack, OutcomeEntry, PeptideCategory, ProtocolNote/Status,
Recipe, WeekDayStatus, and the entire `Training/` taxonomy (AnatomicalMuscle,
CustomExercise, Equipment/MuscleGroup, Exercise, PersonalRecord, Program,
Routine, SetEntry, TrainingPreferences, WorkoutSession).

**High / Medium**
- **`Habit.swift:105` — `isDue` fails open.** `.weekdays` scheduling falls back to `?? true` when `HabitWeekday.from(date:)` returns nil → the habit is treated as due *every* day. *Fix:* `?? false` (fail closed). One char.
- **`LabValue.swift:227-254` — sex-biased reference ranges show female users wrong "in range" states.** Testosterone (264-916 ng/dL), hematocrit, etc. are male ranges applied regardless of `bodyMetrics.sex`. *Fix:* `typicalRange(for: BiologicalSex)`, or return `nil` for sex-specific panels rather than a misleading band.
- **`Habit.swift:196` — `HabitEntry.init` doesn't normalize `date` to start-of-day** despite its documented contract (OutcomeEntry does); a caller that forgets produces duplicate same-day entries that break per-day uniqueness. *Fix:* `self.date = Calendar.current.startOfDay(for: date)` in the init.
- **`ProtocolEntry.swift:15-23` — `completed` participates in both `==` and `hash(into:)`.** Mutating `completed` (a `var`) on an entry used as a `Dictionary` key / in a `Set` changes its hash and orphans it. *Fix:* exclude `completed` from `==`/`hash`, make it `let`, or document the hazard loudly.
- **`PeptideProtocol.swift:227-231` — `cycleProgress` uses raw `timeIntervalSince(startDate)`** without start-of-day normalization while `cycleEndDay` is normalized, so a protocol started at 11pm shows ~95% on the final day until midnight. *Fix:* normalize `startDate` to `startOfDay` for both elapsed and total. (Same family as the known endDate/cycleEndDay drift.)
- **`PeptideProtocol.swift:244-251` — `weekNumber` clamps to `cycleLengthWeeks` through the entire wash-out**, so an 8-on/4-off user reads "Week 8" for all 4 wash-out weeks. *Fix:* don't consult `weekNumber` in wash-out (let `CyclePhaseEngine` own that state) or expose a wash-out flag.
- **`UserProfile.swift:348` — `avatarImageData` stored inline in the profile JSON** (CloudKit-synced); a large avatar + long history arrays can approach the CloudKit 1MB record-payload ceiling and break sync. *Fix:* store the avatar as a separate CloudKit Asset, not inline base64.

**Low / architectural**
- **SwiftUI imported into 4 model files** (`Habit`, `OutcomeEntry`, `LabValue`, `MealEntry`) for `.tint`/`.icon` Color props — couples models to UI, violating the layer boundary `PeptideCategory.swift` explicitly keeps. Move tints to DesignSystem extensions.
- **`UserProfile.swift:344` (+ hand-rolled `init(from:)` at :535)** — every default-valued property must be mirrored with a `decodeIfPresent` line by hand; a forgotten mirror throws on old data. Document the invariant or go fully synthesized.
- `UserProfile.swift:324,407` — `dailyConsumption`/`streakFreezeDays` `yyyy-MM-dd` keys built ad-hoc at call sites; centralize the formatter to avoid non-Gregorian-locale key drift.
- `Peptide.swift:6` `ResearchLink.id` should be `let`; `WeeklySummary.swift:113` computed `id` from `weekStart` is intentional but undocumented; `CustomFood.swift:86` silently floors `servingGrams == 0`; `Exercise.swift:77` full-body detection excludes powerlifting/olympic categories (document intent); `UserProfile` not `Equatable` (would let SwiftUI filter re-renders).

---

## Section 4 — DesignSystem (40/40 files)

Large overlap with the known Liquid Glass backlog (Phases 5-7) and the
Dynamic-Type sweep (A9) and ThemeManager isolation (B9) — those are
deduped out below. New, distinct findings:

**Medium — correctness**
- **`ColorTheme.swift:37` — `AppColor.success` is aliased to `accentPrimary`.** On the Graphite theme `accentPrimary` is near-black (`0x3F3F3D`), so every success indicator (toasts, checkmarks, "in range") renders near-invisible and fails contrast. *Fix:* give `success` a fixed semantic green independent of theme.
- **`VialPalette.swift:249` — `"mots-c"` inference key is unreachable dead code.** `normalize()` strips the hyphen, so only the next line `"motsc"` ever matches. *Fix:* delete the dead key. And **`:253-255`** — `melanotan`/`mt1`/`pt141` infer `.other` but their curated cap tints are antiAging rose-gold, so a `category: nil` call site renders a mismatched cap. *Fix:* map to `.antiAging`.
- **`MetricRing.swift:175` — celebration `Task` has no cancellation handle**; if the ring is removed before ~380ms it writes `celebrationScale` on an orphaned view. *Fix:* store the task, cancel in `.onDisappear`. (The `:113` double-animation driver is already cataloged in Phase 7.)
- **`GlassProgressRing.swift:40-47` — re-mount teleports instead of animating** (the `hasAppeared` guard sets value with no animation on every mount after the first), and the file is named `GlassProgressRing` but only contains `GlassProgressBar`. *Fix:* animate on re-mount; rename the file.
- **`Typography.swift:18` — `AppFont.caption` silently maps to `.caption2`** (the smaller style), so callers expecting standard `.caption` get 13pt not 14pt. *Fix:* rename to `caption2` and add a true `caption`, or document loudly.
- **`KeywordHighlighter.swift:41` — highlighted spans use fixed 17pt** while the surrounding body uses Dynamic-Type `.body`; at accessibility sizes highlights render *smaller* than body text. *Fix:* `Font.system(.body, weight: .semibold)`.

**Dead code / duplication (CLAUDE.md "no dead code")**
- **`GlassCardModifier.swift` — exact duplicate of `GlassCard`**, one call site (`PeptideRow`). Delete, inline `GlassCard { }`.
- **`GlassStatPill` (`GlassStat.swift:34`) — zero call sites** outside its own preview. Delete or mark planned.
- **`AnimationConstants.swift:67` — `motionAware(_:reduceMotion:)` defined but never called** — ironically the exact helper the reduce-motion gap (B5) should route through. Adopt it or delete.
- `GlassNavBar` dead (already Phase 6.1); `FadeSlideModifier` vs `StaggeredAppear` near-duplicates (3 vs 89 call sites) — consolidate.

**Low / Consider**
- `MetricRing:153-177` inline spring tuples should be `AppAnimation` tokens; `GlassSegmentedControl:41` duplicated `optionLabel` body; `GlassSegmentedControl:72` shared `matchedGeometryEffect` string id can collide between two instances.
- `SyncToast.swift:17` `Task` stored in non-Equatable `@State` — prefer `.task(id:)` for reliable cancellation.
- `ExpandableText.swift:20` `renderedText` re-runs the keyword highlighter 3× per render pass — extract to a `let`.
- `Haptics.swift:58` generators created-and-discarded per call with no `prepare()` — first latency-sensitive `impact(.heavy)` (weight log commit) may miss.
- `GlassEffectCompat.swift:17` two `liquidGlass` overloads → consolidate with defaults.
- Reduce-motion guards missing on `GlassPressStyle`, `FadeSlideModifier`, `PulseModifier` (fold into B5); raw `system(size:)` in `GlassEntryRow`/`GlassTextField`/`EmptyStateView`/`PremiumPromoCard` (fold into A9). `PremiumPromoCard` BrandGlyphMark placeholder already Phase 7.
- `AppTheme.swift` `DisplayMode.light` carries dead surface area behind the force-clamp (already Phase 5.2).

---

## Section 5 — Services A (40/40 files)

Clean: Affiliate, BarcodeProductCache, BioAgeStateResolver, BiometricService,
CreatorCodeService, DataServiceProtocol, DrainEndpoint, EntryGrouping,
FoodSpotlightService, Logger, MealScannerService (prior fixes confirmed in place).

**High**
- **`AvatarImageCache.swift:25` — wrong avatar can be returned.** The NSCache key is `data.hashValue`, which is per-process randomized *and* not collision-resistant — two different images can collide and the cache returns the wrong one. *Fix:* key an `NSCache<NSData, UIImage>` on the `Data` itself, or hash with a stable collision-resistant digest (e.g. SHA-256 prefix).

**Medium**
- **`HealthKitService.swift:638` — DST off-by-one in `dailyQuantity`.** End date is `startOfDay + 86_400` (hardcoded seconds); on a 23h/25h DST day the window is wrong. *Fix:* `calendar.date(byAdding: .day, value: 1, to: startOfToday)`.
- **`ExerciseLibrary.swift:65` — fatal trap on duplicate exercise IDs.** `Dictionary(uniqueKeysWithValues:)` crashes if `exercises.json` ever has a dup id (bad OTA/edit). *Fix:* `uniquingKeysWith: { first, _ in first }`.
- **`CommunityStackService.swift:64` — synchronous bundle load on `@MainActor init`** blocks startup decoding a few-hundred-KB JSON. *Fix:* move to `Task.detached`/lazy like `ExerciseLibrary` does.
- **`NotificationService.swift:175-179` — cold-start notification budget undercount.** `reservedSlots` reads the in-memory `currentIDs` tracker, empty before `reconcilePendingState`, so dose reminders can consume all 64 slots and habit reminders silently fail. *Fix:* call `reconcilePendingState()` before the first `scheduleNotifications`, or count live pending requests.
- **`NutritionLabelOCR.swift:281` — regex recompiled per line.** `NSRegularExpression(pattern:)` is built fresh in `firstNumber`, called 30-50× per label scan. *Fix:* cache as `private static let`.
- **`ExportService.swift:41` — `DateFormatter` allocated every `monthlyBuckets` call.** Hoist to `private static let`.
- **`BiometricCorrelationEngine.swift:113` — mean for on/off-dose HRV** lets one sick-day outlier flip a finding's direction. *Fix:* median (matches the rest of the pipeline). (Related to B16/B17.)
- **`LocalizationManager.swift:5` — `@unchecked Sendable` + `didSet` writes UserDefaults** with no isolation (already B9); confirm all write sites are `@MainActor`, then annotate `@MainActor`.

**Low / Consider**
- `AIResearchService.swift:211` redundant `?? nil` on a double-optional (use `.flatMap`); `:358` `maxHistoryTurns=39` sends 40 total — confirm the server cap is inclusive.
- `AchievementService.swift:36` saves the whole array on every check even when nothing unlocked — gate on a dirty flag (hot path via DataStore.save).
- `BiomarkerSeriesService.swift:116` `weightSnapshot` uses count-based `.suffix(days)` not date-window (doc says "within the window" — inaccurate, differs from HealthKit paths).
- `BarcodeScanHistory.swift:197` encode failure dropped silently — log it.
- `ExerciseLibrary`-style: `CycleCompletionService:54` / `CycleMilestoneService` have public `init` alongside `.shared` (CLAUDE.md says singleton) — make `init` private/DEBUG.
- `InsightEngine.swift:33` weekday-name array with index-0 placeholder is crash-adjacent (guarded today); `:211` low-median off-by-one on even arrays (immaterial at the 30-min gate).
- `BackupImportService.swift:241` unreachable `.dryRun` `fatalError` arm is refactor-fragile.
- `DoseLiveActivityService.swift:121` redundant `await MainActor.run` (already on the actor).
- `AppAttestService.swift:108-144` GET-challenge and POST-register share one endpoint URL — fine if the server dispatches by method; **flagged uncertain**.

---

_Sections are appended below as each agent completes._
