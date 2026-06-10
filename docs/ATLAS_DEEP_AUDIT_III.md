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
| 2 | Models | 28 | 🔄 |
| 3 | Data + Shared + Watch/Widgets | 25 | 🔄 |
| 4 | DesignSystem | 40 | 🔄 |
| 5 | Services A | ~38 | ⏳ |
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

_Sections are appended below as each agent completes._
