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
| 7 | Features/Home | 48 | ✅ 48/48 |
| 8 | Features/Meals | 33 | ✅ 33/33 |
| 9 | Features/Profile | 28 | ✅ 28/28 |
| 10 | Features/Train | 24 | ✅ 24/24 |
| 11 | Features/Protocols | 22 | ✅ 22/22 |
| 12 | Features/Biology+Labs+Library+Database | 26 | ✅ 26/26 |
| 13 | Features/Onboarding+Habits+AIResearch+Auth+Sharing+WeeklySummary | 32 | ✅ 32/32 |
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

## Section 8 — Features/Meals (33/33 files)

Clean: MealsContainerView, BarcodeScannerView, TodaysMealsCard, MealEntryRow,
LogMealEntryPicker, the picker/category presentational cards, scanner
feedback/overlay, the check-in cards, MealStreakBadge, SegmentedCalorieRing,
LoggedCaloriePanel.

**High**
- **`BarcodeScanFlow.swift:971, 999` — OCR scans mis-attributed and may corrupt scan history.** An OCR-derived product (barcode prefixed `"ocr:"`) is tagged `.openFoodFacts` (it came from on-device Vision, not OFF), and `BarcodeScanHistory.recordLog` is then called with the `ocr:<uuid>` barcode — `normalize` expects 8-14 digit codes, so this can throw/corrupt the history actor. *Fix:* guard `ocr:` like `custom:` is guarded — tag `.manual` and skip `recordLog`.
- **`FoodLibraryFlow.swift:1413-1469` — zero-calorie OFF product logs silently despite the warning.** `reviewMacros` shows a `zeroCaloriesPer100g` banner, but the "Add to today" button only disables on `loggable(for:) == nil`, which returns non-nil for a 0-kcal product → user logs a 0-macro entry into today's totals/rings. *Fix:* also gate the button on `!zeroCaloriesPer100g` (or return nil from `loggable` when all macros are 0).
- **`RecipeLogConfirmSheet.swift:125` — recipe with deleted ingredients is unloggable with no recovery.** All-zero `totals` (ingredients since deleted) disables "Log to today" with no message; the only exit is Cancel. *Fix:* show an inline "ingredients missing — edit the recipe" warning and allow dismissal.

**Medium**
- **`MealScanFlow.swift:469-498` — duplicate library foods on multi-word names.** Dedup normalizes to `lowercased()` but stores the `.capitalized` name; a re-scan returning different casing for a multi-word food ("Banana Bread" vs "banana bread") fails the match and silently creates a duplicate. *Fix:* dedup and store against the same normalized key.
- **`FoodLibraryFlow.swift:188-199, 399` — double OFF network call on submit.** Pressing Submit while the debounce sleep is in-flight fires both the debounced and the direct search; the result-guard dedupes display but still hits OFF's rate limit twice. *Fix:* cancel the in-flight debounce task on submit.
- **`FoodLibraryFlow.swift:1632-1663` — search spinner flickers during rapid typing** because `defer { isSearching = false }` clears it for cancelled (replaced) tasks. *Fix:* only clear on the guard-passing completion path.
- **`FoodLibraryFlow.swift:755-769` — evicted OFF favorites silently vanish** on the Favorites tab when there's no active search to repopulate the cache. *Fix:* surface "N favorites couldn't load."
- **`ProgressPhotosCard.swift:61-63` — double-write race** stores two copies of one photo if the picker fires twice before `loadAndPersist` clears `pickerItem`. *Fix:* an `inFlightTask` guard like MealScanFlow.
- **`BarcodeScanFlow.swift:104-111, 706-711` — auto-close double-`onClose()` window** (Undo at the timer boundary) and untracked concurrent OCR tasks on rapid photo picks (phase flash). *Fix:* add a `loggedSnapshot == nil` guard; store/cancel the OCR task.
- **`NutritionTargetsEditor.swift:392-447` — `.zero` overloaded as "unset" sentinel** can auto-apply the recommendation over a user's real 0-calorie target, and Save is enabled at `calories: 0` (flat rings). *Fix:* use `Optional<NutritionTargets>` for "unset"; disable Save at 0 kcal.
- `EditNutritionSheet.swift:67` / `CustomFoodEditorSheet.swift:53-59` — `.numberPad` blocks decimal correction; locale comma-decimal parse only works by accident of fallback ordering (try `Double(trimmed)` first).
- `MealEntryEditorSheet.swift:88` delete dialog says "today's totals" even after a date edit to another day; no lower date bound (a 1900 entry pollutes all-time aggregates).
- `RecipeEditorSheet.swift:263` / `RecipeComponentEditorSheet.swift:406` — deleted recipe ingredients silently undercount the live macro preview with no "(1 missing)" cue; `.wholePackage` components have no edit-to-grams affordance.

**Low / Consider**
- `OutcomeCorrelationCard.swift:23` hardcodes a `+` prefix so a negative delta renders "+−0.8" — adopt `BiometricCorrelationCard`'s signed formatting.
- `MacroSummaryRow.swift:31` water target hardcoded 100oz (≈3L, excessive for a 60kg user) — future NutritionTargets expansion.
- `WeightLogSheet.swift:72` whitespace-stripping parse turns "7 0 5" into 705kg; `WeightTrackingCard.swift:204` "this week" delta spans two weeks when the last entry is stale.

---

## Section 7 — Features/Home (48/48 files)

Many files clean (HomeContainerView, the picker/grid presentational cards,
PersonalRangeIndicator, ProtocolScoreCard, StackCompletenessCard,
TodayScheduleCard, SectionAnchorTracker). The findings cluster into four
themes; the HomeView `body`-work itself is already A6.

**Real bugs**
- **`SmartCyclePlannerCard.swift:74` — invalid SF Symbol renders blank.** `"checkered.flag"` isn't a symbol; it's `"flag.checkered"` (used correctly in GoalCountdownCard). *Fix:* rename.
- **`TodayTimelineCard.swift:108` (and `WeeklySummaryHeroCard`, others) — hardcoded `"HH:mm"` ignores the 12/24-hour locale setting.** *Fix:* `.dateTime.hour().minute()` / `timeStyle = .short`.
- **`NotificationIssueBanner.swift:32` — negative reminder count string** when `scheduled > requested`. *Fix:* `max(0, …)`.
- **`CycleTransitionCard.swift:17` — `Divider().foregroundStyle(…)` is a no-op** (Divider ignores it); the intended hairline never tints.
- **`BiometricCard.swift:108` — possibly-dead `.neutral` direction arm** — verify against `HealthRangeService.Direction`.

**Medium — per-render cost (extends A6 beyond HomeView)**
Formatters allocated inside render/build paths: **`TodayOverviewSnapshot.swift:183`** (`NumberFormatter()` every `build`, called per HomeView body pass), **`WeeklySummaryHeroCard.swift:329`** (two formatter pairs per ready-card render). O(n) scans / sorts in `body`: **`HomeMealsSection.swift:87`** (`mealsByCategory()`+`mealEntries()`), **`HomeWellnessSection.swift:21`** (`outcomeHistory` filter, 700+ entries), **`AchievementsPreviewCard.swift:14`** (sort), **`ProfileStacksCard.swift:19`** (sort), **`HabitsHomeCard.swift:160`** (`chip(for:)` re-runs `summary`+`weeklyProgress` per chip, ignoring the cached `todaySummaries` — ~16 scans/render), **`HomeMovementSection.swift:15`** (`workoutSummary()` called twice). *Fix pattern:* hoist formatters to `static let`; compute snapshots into `@State`/`let` once.

**Medium — unstructured tasks & stale state**
- **`HomeView.swift:568, 559` — `onAppear`/`onChange` spawn unstored `Task`s** (hero/health/summary loads, score-change); tab re-entry stacks up to 6 concurrent HealthKit queries. *Fix:* one stored cancel-and-replace `Task`/`.task(id:)`.
- **`DoseLoggingSheet.swift:17` — state seeded from `entry` at `init`** is stale if the sheet is reused for a different entry without `.id(entry.id)` (latent; today it's one-at-a-time).
- **`TodayContextRow.swift:68`, `WeeklyProgressCircles.swift:26` — `Date()` called inside `body`** → "Day N"/today-highlight lag across midnight; thread the parent's `date` down instead.
- **`HealthSummaryCard.swift:50` — `.task` with no `id:`** never re-fires after a HealthKit grant on re-appear.
- `HeroMetricTrio.swift:68` empty→full snapshot flicker could fire the adherence-crossing haptic spuriously; `StackAdjustmentSheet.swift:122` `onChange(of: diff.removed…)` recomputes the full diff in the comparator; assorted cosmetic uncancelled animation tasks (StreakCounterView, WelcomeHeader, AchievementToastView).

**Should Fix — organizational: 10 components misfiled under `Features/Home/Components/`** but rendered only by other tabs — `HealthSummaryCard`, `StackWarningCard`, `StackCompletenessCard`, `CycleTransitionCard`, `StackAdjustmentSheet`, `StackAlertDetailSheet`, `SmartCyclePlannerCard`, `RecommendedPeptidesCard` (Protocols), `HomeMealsSection` (Meals), `VialShelfCard` (ProtocolList). A dev looking under `Features/Protocols/` misses all of them. *Fix:* migrate to their host feature dirs.

**Low / Consider**
- Dead injected deps: `AchievementToastView.swift:7` (`DataStore`), `CycleCompletionPromptSheet.swift:19` (`dismiss`), `AvatarPreset.swift:94` (`_ = rect`).
- `TodayJumpBar.swift:142` hardcoded RGB gradient bypasses the theme; `StackAlertDetailSheet.swift:26` button label by `title.contains(...)` string-matching is localization-hostile; `RecommendedPeptidesCard.swift:97` `ForEach` keyed by `\.offset`.
- `ProfileCustomizationSheet.swift:281` `isSourceTypeAvailable(.camera)` in a ViewBuilder (precompute in `@State`); `:768` parameter shadowed by same-name `store`.
- `HomeStickyHeader.swift:90` re-hashes raw JPEG bytes per render via `AvatarImageCache` (ties to §5's High avatar-cache key finding).

---

## Section 9 — Features/Profile (28/28 files)

Clean: GoalsSectionCard, AboutSection, AchievementsSection, CycleCardShareSection,
HealthConnectionCard, LabsEntryCard, the badge/mockup/toolbar/entry tiles,
PrivacySummaryView (claims-vs-drains now resolved), TravelModePromptSheet.

**High — money & data**
- **`PaywallView.swift:64-69` + `StoreService.swift:18-19` — trial eligibility defaults `true`, so an ineligible user can be charged full price.** Before `loadProducts()` resolves, the CTA reads "Get started for free"; a user who already used their trial and taps in that window is charged the full annual price immediately. *Fix:* default both flags `false`, set true only after `isEligibleForIntroOffer`; show "Continue"/skeleton until products load.
- **`PaywallView.swift:587-635` — auto-renew disclosure wrongly applied to the Lifetime (one-time) plan** — "Subscription auto-renews… cancel in Settings" is factually wrong for a non-subscription and is an App Store 3.1.2(a) accuracy/rejection risk. *Fix:* make the disclosure (and the "Cancel any time" subCTA at `:533`) conditional on the selected product being a subscription.
- **`PaywallView.swift:686-696` — `restore()` has no in-flight guard**; the footer button and the error-banner retry can both fire concurrent `AppStore.sync()` + `updatePurchasedProducts()`. *Fix:* an `isRestoring` flag symmetric with `isPurchasing`.
- **`ExportSection.swift:78-90, 152-178` — silent export failure.** When `writeCSV`/`writeJSON` return `nil` (disk full / sandbox error) the `if let url` simply no-ops, no error set, no share sheet — the user believes the export worked. (Only the PDF path has a `do/catch`.) *Fix:* add the `else { exportError = … }` to every write block.

**Medium**
- **`PaywallView.swift:64-69` — no auto-dismiss when already Pro.** A user who upgraded on another device still sees the paywall; after `loadProducts()` check `isProUser` and `dismiss()`.
- **`ReconstitutionCalculator.swift:88-93` — dose can exceed one syringe with no warning.** The 50-10,000mcg range allows >100 U-100 units; the diagram silently pegs at full and `dosesPerVialString` shows "0 doses/vial". *Fix:* warn when `unitsOnSyringe > 100`. (Also reinforces the A2 framing — keep it a converter with honest bounds.)
- **`BodyMetricsCard.swift:77` — imperial height shown as decimal inches** ("71 in") instead of `5'11"`. *Fix:* feet+inches for imperial. (Same units family as A4.)
- **`AppearanceSettings.swift:111-130` — denial path double-persists and double-cancels** via the `onChange` chain plus inline calls; consolidate to one mutation path.
- **`RestoreBackupSheet.swift:249-272` — bare `Task`+`try?` sleep runs against a dismissed sheet**; `BackupImportService.apply` can fire post-dismiss. *Fix:* cancellation check / `.task` lifecycle.
- **`AccountSection.swift:38-39` — "Try Again" re-launches the Apple ID sheet even on user-canceled sign-in.** Suppress retry for `.canceled`.
- **`ProfileView.swift:142` — `memberDuration` shows "1 month" for a future `memberSince`** (mis-dated restore); `max(0, …)`.

**Low / Consider**
- `ScreenshotModeRow.swift:26` + `WeeklySummaryToggleRow.swift:29-88` — Toggle-inside-Button dual mutation paths are structurally redundant (don't double-fire today, fragile under a press-style wrapper); consolidate to the Toggle binding.
- `ExportSection.swift:5` reads `StoreService.shared.isProUser` unobserved (works via paywall-dismiss re-render; make `@State` explicit).
- `AppearanceSettings.swift:72` hardcodes "Dark" appearance value; `ReconstitutionCalculator.swift:240` integer test via `truncatingRemainder` is float-fragile; `DiagnosticsSection.swift:79` use `.first` not `[0]`; `AccountSection.swift:20` cloud-sync row is a one-shot snapshot (document).

---

## Section 10 — Features/Train (24/24 files)

Clean: BodyAnatomy, TrainNavigation, ExerciseRow, the chip rows, MuscleHistorySheet.

**High**
- **`WorkoutExerciseCard.swift:72` — SwiftData fetch up to 10×/sec per exercise.** `previousSetLookup()` runs in a `@ViewBuilder` evaluated every render; with the rest timer at 10Hz and N exercise cards, that's 10·N `loadWorkoutSessions()` fetches/second (amplifies B6). *Fix:* parent precomputes a `[exerciseID: SetEntry]` once and passes it in; or cache in `@State` keyed on `entry.id`.
- **`TrainOverviewView.swift:54-57` — overview goes stale after finishing a workout.** `refresh()` only runs on mount/pull; the promised post-finish broadcast was never added, so "Recent workouts" and the muscle heatmap don't update until you leave and return. *Fix:* `.onChange(of: sessionService.activeSession?.id)` → `refresh()` on the non-nil→nil transition.

**Medium**
- **`WorkoutHistoryView.swift:27` — nested `NavigationStack`** inside TrainContainerView's stack → double back button / broken hierarchy on iOS 18. *Fix:* drop the inner stack (outer already registers the destination). *(Same nested-stack class as ProtocolBuilder §11.)*
- **`ExerciseImageView.swift:114 — `guard image == nil` blocks reload** when the view instance is recycled for a new `url`, showing the previous exercise's image. *Fix:* reset `image = nil` at the top of `load()`.
- **`RestTimerOverlay.swift:160 — ring jumps backward on +15** because `totalSeconds` isn't extended when `targetEnd` is pushed out. *Fix:* extend `totalSeconds` by the delta.
- **`ActiveWorkoutView.swift:113 — stranded on nil finish.** If `finishWorkout()` returns nil the alert dismisses with no active session and no finish screen. *Fix:* `else { dismiss() }`.
- **`WorkoutDetailView.swift:43-53 — misleading legacy label.** `entryFromSession` renders "9×6" (total-sets × avg-reps) which reads as "9 sets of 6"; integer-division avg also lossy. (Legacy adapter, now under Train.)
- Per-render recompute (memoize via `@State`/`.task`): `WorkoutHistoryView.swift:108` (`Dictionary(grouping:)`+sorts), `WorkoutFinishView.swift:20` / `WorkoutSessionDetailView.swift:16` / `ExerciseDetailView.swift:13` (`library.lookup` per exercise, re-fires on any `@Observable` library change), `TrainingCalendarGrid.swift:332`; `TrainContainerView.swift:153` full fetch on every NavigationLink resolve (pass the value through the enum).
- `ExercisePickerSheet.swift:53` fire-and-forget `library.load()` race shows raw exercise ID until reload; `CustomExerciseEditorSheet.swift:110` double-tap Save mints two IDs (memoize in `@State`).

**Low**
- `WorkoutSessionDetailView.swift:146` "X sets" header counts warmups (wrong number vs the working-set-filtered finish screen); `RestTimerState` `completeNow()`==`cancel()` (one is redundant/comment wrong); `ExerciseImageView.swift:80` dead `didStart`; `SetEditorRow.swift:139` raw color literal; `WeeklyMuscleHeatmap.swift:45` includes unfinished sessions; `SetEntry.swift:72` Epley vs Brzycki for low-rep PRs (document); `ActiveWorkoutView`/`RestTimerOverlay` stored-`let` `Timer.publish` is fragile if SwiftUI re-creates struct fields (prefer `@State`/`.task`).

---

## Section 11 — Features/Protocols (22/22 files)

**High — data loss (corroborates §1)**
- **`setPeptideSchedule` (`DataStore.swift:596-604`, called from `ProtocolDetailView.swift:291`) permanently erases logged doses.** Editing a peptide's schedule strips today's entries and regenerates *without* the `completedToday` preservation `updateProtocol` has — losing `completed`/`actualDose`/`actualTime`/`injectionSite`/`notes`. Worse, the removed entries are added to `pendingEntryDeletions`, so the CloudKit copy is deleted too and a restore can't recover them. *Fix:* extract `updateProtocol`'s preservation merge into a shared helper, call it here, and exclude logged IDs from the deletion set. *(Two agents converged on this — §1 found the omission, §11 found the call site + CloudKit angle. Upgraded to High.)*

**Medium**
- **`DoseDayMap.swift:85,105 — calendar ignores per-peptide schedule overrides.** Uses `proto.schedule` (protocol default) for every peptide, so a custom-scheduled peptide shows dots on the wrong days and the wrong dose/time. *Fix:* `proto.schedule(for: peptide.id)`.
- **`DoseDayMap.swift:130` + `CycleBands.swift:77 — washout weeks shown as active.** `isDayInCycle`/`isProtocolActive` use only the on-cycle length, so an 8-on/4-off protocol shows scheduled dots and a continuous band through washout weeks 9-12. *Fix:* window = `(cycle+washout)*7` with an on-cycle-portion check.
- **`ProtocolBuilderView.swift:136,166 — nested `NavigationStack` + duplicate destinations** inside a sheet → community-stack push lands in a modal with no Back/Cancel. *Fix:* drop the inner stack (outer ProtocolListView already registers both) or use separate sheets.
- **`ProtocolListView.swift:136 — unconditional "Done"** is a no-op when the view is a tab root rather than a sheet. *Fix:* gate on an `isModal` flag.
- **`ProtocolsStackHealthSection.swift:75 — uncancelled `Task.sleep` chain** opens the adjustment sheet on a stale warning if the user navigates away first.
- **`ScheduleEditor` — `intervalAnchor` not user-editable**; "Every N days" always anchors to `Date()` at builder-open with no correction path. *Fix:* expose a `DatePicker` or default to `startDate`.
- **`ProtocolBuilderView.swift:46 — silent dismiss** when every appended peptide already exists (no feedback); **`:709` `generateDefaultTimes` is dead code.**

**Low / Consider**
- `ProtocolDetailView.swift:277` registers `navigationDestination(for: Peptide.self)` on a pushed view (shadow hazard); `:192/:206` duplicate `.sectionAppear(index: 4)`; `PeptideScheduleSheet.swift:240` duplicate `accessibilityLabel`; `ProtocolNotesTimeline.swift:176` context-menu delete has no confirmation (the edit-sheet path does); `TrackCalendarSection.swift:30` recomputes `DoseDayMap.build` + bands every body pass (memoize).

---

## Section 12 — Biology + Labs + Library + Database (26/26 files)

Clean: BiologyConfig, EditBiomarkersSheet, BioAgeParticleCluster,
BiomarkerSparkline, CommunityStackCard, AddToStackSheet, DosageInfoSection,
PeptideRow, CategoryFilterChips. **Verified resolved:** LabsView modal now has
a Done button; PeptideListView iPad stale detail pane is fixed; `Biomarker`'s
conversion helpers are correct (the gap is in consumers — see below).

**High**
- **`BioAgeHeroSection.swift:169` — building-state shows a wrong "N of 3 signals connected" count.** `buildingLabel` multiplies `progress` by 3 treating it as a signal-fraction, but the resolver now emits `dataDays / 7` (a days fraction) — two comments in the file directly contradict each other. A user with 4/7 days sees "2 of 3 signals connected" regardless of which HealthKit types actually responded. *Fix:* render "N of 7 days of data" from `BioAgeStateResolver.minBaselineDays`.
- **A4 render sites pinned (extends the deferred A4).** `BiomarkerRow` subtitle via `BiomarkerSeriesService.changeText` (`:229` uses `biomarker.unit`, metric-only) and `BiomarkerDetailSheet.swift:79,313` (hero number + delta) both render metric for imperial users ("72.0 kg" not "158.7 lb"). This is exactly the multi-file unit-threading I flagged A4 needs — thread `MeasurementUnit` through `BiomarkerSeriesService.snapshots`→`changeText`/`formatValue` and into the detail sheet, applying `displayValue`/`displayUnit`. (Watch the temperature-delta offset noted in A4.)

**Medium**
- `BioAgeHeroSection.swift:116 — unlocked bio-age number has no `accessibilityValue`** for younger/older (confirms C14); VoiceOver gives only the number.
- `LabsView.swift:153 — context-menu "Delete latest" has no confirmation** unlike every other delete path (the edit-sheet path confirms). *Fix:* `.confirmationDialog`.
- `BiomarkerDetailSheet.swift:176-252 — 90-day chart axis labels** render as raw "76d/62d" for most 14-day-stride ticks (`dayLabel` only special-cases 6 offsets); and `:56` `.task` guard `historicalSnapshot == nil` blocks re-fetch on re-present (use `.task(id: biomarker)`).
- `LabPanelDetailView.swift:201 — `chartXStride` uses `.weekOfYear` for all spans ≤180 days** → near-empty axis for users with a couple of draws; add a `≤14 → .day` case.
- `BiomarkerListSection.swift:65 — `.task(id: visibleBiomarkers.hashValue)`** relies on non-contractual hash stability; key on the values directly.
- `StackLibraryView.swift:8 — per-keystroke filter** scans `peptideAbbreviations` inline in computed vars; move to an `@Observable` VM with `didSet` (like `PeptideListViewModel`).
- `CommunityStackDetailView.swift:63 — peptides resolved twice** (cache + inside `buildPreviewProtocol`) so the preview card and peptide list can diverge.
- `PeptideDetailView.swift:296 — `navigationDestination(for: PeptideProtocol.self)` declared deep inside a `ScrollView`** rather than at the stack root (undefined if a sibling destination exists).

**Low / Consider**
- `BioAgeDial.swift:151` / (and `LabEntryEditor.swift:41` `String(value)` scientific-notation risk) — formatter allocations / number formatting; `PeptideListViewModel.swift:50` `localizedCaseInsensitiveContains` per keystroke (pre-lowercase index); `ResearchLinksSection.swift:23` divider keyed on possibly-duplicate `id`; `CommunityStackDetailView.swift:288` auto-dismiss `Task.sleep` on a possibly-dismissed view; `LabsView.swift:137` `.preferredColorScheme(.dark)` on a section rather than the stack root.

---

## Section 13 — Onboarding + Habits + AIResearch + Auth + Sharing + WeeklySummary (32/32 files)

Clean: WhatsNewPage, HabitRowCard, CycleMilestonePromptSheet, EmailCapturePage,
ConsistencyChart, HeroIcon/HeroLogo, NotificationPreviewCard, OnboardingBackground,
ReadyHero, ThemeChoicePage, DailyTargetsPage (logic).

**Dead code — verified (6 files, 0 external refs; instantiated only in their own `#Preview`)**
`CreatorAttributionPage`, `RecommendationsPage`, `OnboardingProgressBar`,
`WelcomeFeatureBadge`, `AddMedicationPreviewPage`, `DailyTargetsPage` under
`Features/Onboarding/Components/` — the live onboarding uses inline equivalents.
Same pattern as the Insights cluster deleted in Phase 8.1. *Fix:* delete all six.

**Medium**
- **`CycleCardView.swift:356 — force-unwrap `UnicodeScalar(65 + idx)!` over the unbounded peptide list** in the accessibility label (the visual row is `.prefix(4)`-capped, the a11y loop isn't); semantically wrong past 26 compounds, invalid scalars past ~191. *Fix:* cap to 26, drop the force-unwrap.
- **`OnboardingView.swift:331/343 + 339/369 — duplicate `.onAppear` and `.onChange(of: page)`** on the root ZStack; framework-undefined ordering means the funnel can log the wrong step name on a resumed cold launch. *Fix:* merge each pair.
- **`OnboardingView.swift:2206 — `requestHealth()` `Task` lacks `@MainActor`** (the sibling `requestNotifications()` has it) — Swift 6 isolation gap. *Fix:* `Task { @MainActor in … }`.
- **`AIResearchView.swift:257 — verify the `replyStream(history:newUserPrompt:)` contract** — `priorHistory` drops the just-appended user turn on the assumption the service re-adds it; if it doesn't, the user's question is silently omitted from context every turn. *Flagged uncertain — needs a test.*
- **`HabitHeatmap.swift:63 — `DateFormatter` allocated per render** in `monthLabels`; **`HabitEditSheet.swift:346`** empty `weekdays` silently expands to all days on save (data-inconsistency masked).
- **`CycleCardModel.swift:97 — `forStack` doesn't normalize `earliestStart` to start-of-day** (unlike `forProtocol`), so cycle-day can be off by one across timezones.
- **`ShareCardSheet.swift:171 — `try?` swallows render failure** → "Rendering…" spinner stuck forever; **`CycleCardView.swift:374`** rebuilds `CIContext`+QR every render (QR is a constant — hoist to `static let`).

**Low / Consider**
- `WeeklySummaryDetailView.swift:40` + `ShareCardSheet`/`refreshPreview` + `WhatsNewTourSheet:313` + `TrialOfferView:175` — uncancelled `Task`s/animations on dismiss (cosmetic, pattern-wide); `AIResearchView.swift:282` O(n) `lastIndex` per streaming chunk; `LockScreenView.swift:57` immediate biometric prompt before render; `BodyMetricsPage.swift:237` imperial-inches `% 12` truncation (round); `OnboardingView.swift:1604` uses `UIAccessibility.isReduceMotionEnabled` directly instead of the environment; `ShareCardRenderer.swift:39` writes PNG to `temporaryDirectory` (prefer caches); `PastWeeksSection.swift:92` deleted-summary placeholder renders empty with no "no longer available" state; `AffiliateApplySheet.swift:159` hides the data-egress disclosure entirely when no prefill.

---

_Sections are appended below as each agent completes._

---

## Cross-section synthesis & priorities

12 of 13 sections complete (~472 files; Section 6 / Services B pending and
will be folded in). This pass was a coverage sweep, so most findings are
Medium/Low; the list below is the net-new signal worth acting on, ranked.

### Net-new ship-blockers (ranked)

1. **Logged-dose data loss on schedule edit** (§1+§11, two agents converged)
   — **FIXED this session.** `setPeptideSchedule` erased completions and
   queued them for CloudKit deletion.
2. **Paywall charges an ineligible user full price** (§9) — trial
   eligibility defaults `true`, so "Get started for free" can show before
   products load and the tap bills full annual. Plus the Lifetime plan
   shows subscription auto-renew copy (App Store 3.1.2(a)). Money +
   compliance — fix before submission.
3. **OCR scans corrupt scan-history** (§8) — `ocr:` barcodes flow into
   `BarcodeScanHistory.recordLog`, which expects numeric codes; also
   mis-attributed as OpenFoodFacts.
4. **Zero-calorie products log past their own warning** (§8) — wrong
   macros enter today's totals.
5. **Wrong Bio-Age "N of 3 signals" label** (§12) — a days-fraction is
   rendered as a signal count.
6. **Silent export failure** (§9) — CSV/JSON write failures give the user
   no feedback.
7. **Imperial users see metric numbers/labels** (§12 pinned the exact A4
   render sites: `BiomarkerSeriesService.changeText` + `BiomarkerDetailSheet`).

### Cross-cutting patterns (fix the cause, not each instance)

- **Work in `body`** — formatter allocations and O(n) scans/sorts on every
  render across Home/Profile/Biology/Train/Protocols (extends A6 well
  beyond HomeView). Pattern fix: hoist formatters to `static let`; compute
  snapshots into `@State`/`let` once.
- **Uncancelled `Task`/animations on dismiss** — pervasive (Home, Train,
  Onboarding, Sharing, WeeklySummary); cosmetic individually, systemic in
  aggregate. Adopt a stored-task cancel-on-`onDisappear` idiom or `.task(id:)`.
- **Nested `NavigationStack`s** — WorkoutHistoryView (§10) and
  ProtocolBuilderView (§11) nest inside an outer stack → double back button
  / modal dead-ends on iOS 18.
- **`Toggle`-inside-`Button` dual mutation paths** — ScreenshotModeRow,
  WeeklySummaryToggleRow (§9); consolidate to the Toggle binding.
- **Hardcoded `"HH:mm"` / `DateFormatter` formats** ignore the 12/24-hour
  locale (§7, others).
- **Imperial-unit gap (A4)** is broader than weight — height (§9), temp,
  waist; all the render sites are now enumerated.
- **Dead code** — 6 onboarding components (**deleted this session**), plus
  dead DesignSystem primitives (§4: GlassCardModifier, GlassStatPill) and
  service helpers.

### Fixed from the sweep this session

- Logged-dose preservation in `setPeptideSchedule` (+ the CloudKit-deletion
  gap that also affected `updateProtocol`).
- Deleted 6 verified-dead onboarding components.
- `flag.checkered` SF Symbol (blank icon) + negative reminder-count guard.

### Correction to a prior finding

§1's "`updateProtocol` dedup matches `peptide.id` alone → loses the second
`timesPerDay:2` dose" was a **misread** — the dedup also matches minute
granularity (`DataStore.swift:550`), so it's correct. The real bug was the
missing preservation in `setPeptideSchedule` (now fixed).

### Recommendation

The branch is now very large and entirely unreviewed. The highest-leverage
move remains: **open the PR, get CI green, and work the ranked ship-blockers
above** (paywall + OCR/zero-cal data + Bio-Age label) — not another audit
pass. The per-render and uncancelled-task patterns are best handled as
focused refactors in a compile-capable session, not blind.
