import Foundation

/// One-shot migration from the legacy free-form `WorkoutEntry`
/// log (`profile.workoutHistory`) to the structured
/// `StoredWorkoutSession` table. Runs once per user at app launch
/// when the marker `profile.workoutLegacyMigrationCompleted` is
/// false.
///
/// **Mapping** — each `WorkoutEntry(name, sets, reps, duration)` becomes
/// a `WorkoutSession` with:
///   - `name`             = entry.name
///   - `startedAt`        = entry.date
///   - `finishedAt`       = entry.date + entry.durationMinutes * 60
///   - `exercises`        = []     (legacy log had no per-exercise breakdown)
///   - `note`             = "Legacy quick-log · N sets × M reps"
///
/// The exercise breakdown is deliberately empty rather than synthesising
/// a placeholder `Exercise` — legacy entries genuinely carried no
/// per-exercise detail, and inventing a fake compound would mislead
/// future analytics. The note string preserves the sets/reps fidelity
/// the user originally entered so nothing is silently dropped.
///
/// After a successful migration, `profile.workoutHistory` is cleared
/// and the marker is set so the migration is idempotent across
/// relaunches. The cleared history reclaims storage and prevents the
/// dual-store split that the audit flagged.
@MainActor
enum WorkoutLogMigrationService {

    /// Performs the migration if it hasn't run for this profile yet.
    /// Returns the migrated entry count (0 when already migrated or
    /// there was nothing to migrate).
    @discardableResult
    static func migrateIfNeeded(
        profile: inout UserProfile,
        repository: SwiftDataRepository = .shared
    ) -> Int {
        // Already migrated — idempotent return.
        guard !profile.workoutLegacyMigrationCompleted else { return 0 }

        let history = profile.workoutHistory
        guard !history.isEmpty else {
            // Nothing to migrate, but still flip the marker so this
            // service doesn't run again every launch for users who
            // never used the legacy log.
            profile.workoutLegacyMigrationCompleted = true
            return 0
        }

        var migrated = 0
        for entry in history {
            let finishedAt = entry.date.addingTimeInterval(
                TimeInterval(max(0, entry.durationMinutes) * 60)
            )
            let note = "Legacy quick-log · \(entry.sets) sets × \(entry.reps) reps"
            let session = WorkoutSession(
                id: entry.id,
                name: entry.name,
                routineID: nil,
                programID: nil,
                startedAt: entry.date,
                finishedAt: finishedAt,
                exercises: [],
                note: note,
                perceivedEffort: nil
            )
            repository.upsertWorkoutSession(session)
            migrated += 1
        }

        // Migration succeeded for every entry — clear the source so a
        // second pass doesn't double-import and the deprecated field
        // stops occupying space in the profile blob. Flip the marker
        // so the migration is permanently a no-op.
        profile.workoutHistory = []
        profile.workoutLegacyMigrationCompleted = true

        AppLog.persistence.error(
            "WorkoutLogMigrationService: migrated \(migrated, privacy: .public) legacy entries to StoredWorkoutSession"
        )
        return migrated
    }
}
