# ATLAS DATA INTEGRITY IMPLEMENTATION REPORT (Master Implementation 04)

Implements the highest-priority findings from the Atlas Data
Architecture Audit. All nine audit findings were re-verified against
the current `main` (57f528c) before any change; none had already been
fixed. Every change is the smallest one that eliminates its risk;
SwiftData, CloudKit, the local-first write model, offline behaviour,
the Watch queue and the existing JSON→SwiftData migration are all
preserved.

## Changes made (by phase)

### Phase 1 — Watch duplicate delivery (fixed)
`onMarkComplete` blindly called `toggleEntry`, so a duplicate
WCSession delivery (the Watch's `sendMessage`-error →
`transferUserInfo` fallback can double-deliver) flipped a completed
dose back to incomplete. `DataStore` now has idempotent
`markEntryComplete` / `markEntryIncomplete`, and both Watch callbacks
route through them.

### Phase 2 — Persistence failure vs projections (fixed)
`performSaveNow()` updated the widget and Watch snapshots even when
the SwiftData commit failed, leaving projections showing state that
reverted at next launch. Projections now run only on commit success in
`performSaveNow`, `logWorkout`, and `deleteWorkout`; the failure
banner behaviour is unchanged and verified by test. (Live Activities
remain on their own reconcile path — see Remaining risks.)

### Phase 3 — StoredProfile multi-device conflict (fixed — Option A, scoped)
Decision: **Option A (field split), scoped to the high-churn areas**,
not Option B. Rationale from actual usage: meals and habit check-ins
are logged several times per day per device, momentum accrues daily,
weigh-ins/labs/outcomes are frequent, while nutrition targets, biology
config, creator attribution etc. are write-once/rare — so splitting
the churny areas removes nearly the whole conflict surface for the
cost of eight additive optional columns, with no row-model migration
risk. Option B (dedicated SwiftData rows) remains the right long-term
home for meals and labs if volume grows; deferred deliberately.

New `StoredProfile` columns: `mealsData`, `habitsData`,
`momentumData`, `weightHistoryData`, `labsData`, `outcomesData`,
`foodLibraryData`, `summariesData`. Reads prefer the column and fall
back to the same key in the legacy `extensionData` blob (no up-front
data migration, nothing discarded); the next save promotes blob data
into the columns. `update(from:)` assigns only columns whose bytes
changed (encoder now uses `.sortedKeys` for deterministic output), so
untouched fields stay clean for CloudKit's field-level merge.

### Phase 4 — Migration verification (fixed)
`MigrationService` now runs the import inside a save batch, then
verifies by **reading back and comparing protocol IDs, entry IDs, and
the profile** (not "some data exists"). Any mismatch or failed commit
rolls the partial import back and leaves the JSON in place for retry;
only a verified import archives the legacy files.

### Phase 5 — Weekly summary cache (fixed)
Cached summaries carry a SHA-256 fingerprint of the aggregate's
user-editable inputs (compliance, streak, outcomes, nutrition, labs);
both cache short-circuits (service + HomeView) treat a mismatch as a
miss. HealthKit series are excluded from the fingerprint so passive
sample arrival doesn't re-fire the paid AI call. Pre-fingerprint cache
entries regenerate once.

### Phase 6 — PR consistency (fixed)
`DataStore.deleteWorkout` captures the session's exercise IDs, then
`PRDetectionEngine.recompute(exerciseIDs:)` deletes those records and
re-ingests the **full** history (new uncapped
`loadAllWorkoutSessions()` — the 200-row UI cap would silently drop
older records), scoped to the affected exercises. A PR either rolls
back to the best surviving session or disappears with its last source.
Finished sessions are not editable in the UI today, so delete is the
only reachable invalidation path.

### Phase 7 — Entry loading scale (fixed)
Cold launch and reloads fetch a 400-day window with a `#Predicate`
pushed into SQLite (covers Today, calendar month, 13-week detail,
year+ streaks), then an append-only async backfill hydrates the tail
so exports and lifetime totals still see everything. Backup import
diffs against a new ID-only projection. The backfill is cancelled on
import and screenshot-mode entry.

### Phase 8 — Profile singleton identity (fixed)
`StoredProfile` gains a deterministic `singletonKey` and an
`updatedAt` stamp (no unique constraints — CloudKit forbids them).
`loadProfile`/`saveProfile` route through `canonicalProfileRow`, which
detects duplicate rows (two devices racing first launch), keeps the
newest deterministically, adopts any slice column the winner lacks
from the losers, and deletes the rest.

### Phase 9 — Workout input validation (fixed)
`SetEntryLimits` (weight 0…1000 kg, reps 0…500, non-finite → 0)
clamps at the service boundary (`updateSet`) and in the editor
bindings. Weight 0 stays valid (bodyweight track); elite performance
is never rejected.

### Phase 10 — CloudKit regression coverage (added)
Schema-level tests assert no unique attributes anywhere in the
versioned schema, all seven models are declared, the
container+migration-plan initializes, and the version chain ends at
the live schema. Hardware plan: `docs/CLOUDKIT_HARDWARE_TEST_PLAN.md`.

### Phase 11 — Data deletion cleanup (fixed)
`AuthService.deleteAccount()` now also clears legacy JSON, archived
`.migrated` files, custom peptides, the widget snapshot, and progress
photos. `.migrated` archives expire after 90 days
(`cleanUpExpiredArchivedLegacyFiles`, run at launch; touches archive
names only). HealthKit samples are deliberately untouched — policy and
rationale in `docs/DATA_ERASURE_POLICY.md`.

## Data migration changes
- The new `StoredProfile` columns are purely additive
  optional/defaulted attributes and ship via Apple's inferred
  lightweight migration under the existing V2 declaration — the same
  path the `.unique` removal and the original `extensionData` column
  used. A declared V3 sharing the same live `@Model` classes was tried
  and reverted: SwiftData computes duplicate version checksums from
  one editable model and aborts at container creation (CI run 416);
  the trap is documented in `PeptideAtlasSchema.swift`.
- No destructive migration of `extensionData`: legacy blobs are read
  through fallbacks and promoted on the next save.

## Files changed
- `Peptide/App/PeptideApp.swift` — Watch callbacks → idempotent methods
- `Peptide/App/DataStore.swift` — idempotent marks; projection gating;
  PR recompute hook; windowed load + backfill; test counters
- `Peptide/Services/SwiftDataRepository.swift` — commit-failure test
  seam; profile reconciliation; windowed/ID-only/uncapped fetches
- `Peptide/Data/SwiftDataModels.swift` — profile column split, slices,
  residual blob, change-minimal updates, sorted-keys encoder
- `Peptide/Data/PeptideAtlasSchema.swift` — inferred-migration note
- `Peptide/Services/MigrationService.swift` — read-back verification,
  rollback, archive cleanup hook
- `Peptide/Services/PersistenceService.swift` — archive retention,
  clearAll includes archives
- `Peptide/Services/AuthService.swift` — full erasure sweep
- `Peptide/Services/ProgressPhotoStorage.swift` — `deleteAll()`
- `Peptide/Services/PRDetectionEngine.swift` — `recompute`, restricted ingest
- `Peptide/Services/WeeklySummaryService.swift` — fingerprinted cache
- `Peptide/Services/WorkoutSessionService.swift` — set clamping
- `Peptide/Models/WeeklySummary.swift` — `sourceFingerprint`
- `Peptide/Models/Training/SetEntry.swift` — `SetEntryLimits`
- `Peptide/Features/Home/HomeView.swift` — freshness-aware cache read
- `Peptide/Features/Train/Components/SetEditorRow.swift` — clamped bindings
- `docs/` — erasure policy, hardware test plan, this report

## Tests added (28 new)
- `DataStoreTests` — watch duplicate complete/incomplete; projections
  not updated on commit failure (P0/P1)
- `ProfileSyncIntegrityTests` — concurrent-edit both-facts-survive,
  byte-level column disjointness, updatedAt change detection, legacy
  blob fallback + promotion, singleton creation, duplicate
  reconciliation, reload stability (P1)
- `MigrationServiceTests` — commit-failure rollback + retry, missing
  rows, ID mismatch, faithful-import pass, archive retention, clearAll
  reaches archives (P2)
- `WeeklySummaryServiceTests` — invalidated on source edit, legacy
  entry stale, deterministic fingerprint (P1)
- `PRConsistencyTests` — deleted session rolls back/removes PR, scoped
  recompute, limits clamping, service-boundary clamping (P0)
- `EntryLoadingScaleTests` — 10k-row windowed fetch under budget,
  window+tail partition, backfill hydration, ID projection (P2)
- `CloudKitSchemaCompatibilityTests` — no unique attributes, model
  roster, container init, version chain (P2)

## Tests passing
The container this work ran in has no Swift/Xcode toolchain, so the
suite could not be executed locally. Both Python CI gates that can run
locally pass (`design-lint.py --all`: 0/0; `check-store-metadata.py`:
OK). The full suite runs in `pr-checks.yml` (macOS, `xcodebuild test`)
on push — treat a green `build-check` there as the verification gate.

## Manual hardware tests required — NOT VERIFIED ON HARDWARE
- Every scenario in `docs/CLOUDKIT_HARDWARE_TEST_PLAN.md`, especially:
  concurrent independent profile edits merging (Phase 3), duplicate
  profile reconciliation across devices (Phase 8), the in-place
  schema upgrade over real data, and Watch duplicate delivery under weak
  connectivity.
- No CloudKit multi-device behaviour claimed here has run on devices.

## Remaining risks
- **Live Activities** still update from in-memory state before the
  debounced save lands; they self-heal via reconcile-on-activation and
  were left untouched to preserve the audited Live Activity
  idempotency. Risk window ≈ the 350 ms debounce.
- **Mixed app versions on two devices**: a pre-split build reads only
  the legacy blob, so data written by a post-split build is invisible
  to it (and its saves won't carry the split areas). Converges once
  both devices update; same class of risk as any schema evolution.
- **Same-feature concurrent edits** (both devices log a meal in the
  same sync window) still resolve last-writer-wins within that one
  column.
- **Duplicate-profile reconciliation** keeps the newest row and adopts
  only missing columns; a genuinely forked pair (both rows modified
  everywhere) resolves to the newest rather than a deep merge.
- Schema.Attribute uniqueness introspection (`isUnique`) guards the
  known failure; other CloudKit incompatibilities (e.g. a future
  non-optional no-default field) surface only in the hardware pass.

## Deferred improvements
- Option B promotion of meals/labs into dedicated SwiftData row models
  (right long-term move once volume or query needs demand it).
- Coupling Live Activity updates to save success.
- Message IDs/nonces on Watch payloads for true dedupe (guarded
  idempotency makes them unnecessary for the current two actions).
- An in-app surface to view/clear `.migrated` archives before the
  90-day expiry.
