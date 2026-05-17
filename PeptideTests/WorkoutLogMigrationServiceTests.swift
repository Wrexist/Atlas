import XCTest
@testable import Peptide

@MainActor
final class WorkoutLogMigrationServiceTests: XCTestCase {

    private var repo: SwiftDataRepository!

    override func setUp() async throws {
        try await super.setUp()
        repo = SwiftDataRepository.shared
        repo.configureForTesting()
    }

    // MARK: - Marker behaviour

    func test_migrateIfNeeded_setsMarkerForEmptyHistory() {
        var profile = UserProfile.fresh
        profile.workoutHistory = []
        XCTAssertFalse(profile.workoutLegacyMigrationCompleted)

        let migrated = WorkoutLogMigrationService.migrateIfNeeded(
            profile: &profile, repository: repo
        )

        XCTAssertEqual(migrated, 0,
                       "Empty history migrates nothing")
        XCTAssertTrue(profile.workoutLegacyMigrationCompleted,
                       "Marker must flip even on empty history so the service doesn't keep re-evaluating")
    }

    func test_migrateIfNeeded_isIdempotent() {
        var profile = UserProfile.fresh
        profile.workoutHistory = [
            WorkoutEntry(date: Date(), name: "Push", sets: 4, reps: 8, durationMinutes: 45)
        ]

        let firstPass = WorkoutLogMigrationService.migrateIfNeeded(
            profile: &profile, repository: repo
        )
        XCTAssertEqual(firstPass, 1)
        XCTAssertTrue(profile.workoutLegacyMigrationCompleted)
        XCTAssertEqual(profile.workoutHistory.count, 0,
                       "Source must be cleared after a successful pass")

        let secondPass = WorkoutLogMigrationService.migrateIfNeeded(
            profile: &profile, repository: repo
        )
        XCTAssertEqual(secondPass, 0,
                       "A second invocation must be a no-op even if history were repopulated externally")
    }

    // MARK: - Field mapping

    func test_migrateIfNeeded_mappingPreservesData() {
        var profile = UserProfile.fresh
        let entryDate = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = WorkoutEntry(
            id: UUID(),
            date: entryDate,
            name: "Pull day",
            sets: 5,
            reps: 6,
            durationMinutes: 50
        )
        profile.workoutHistory = [entry]

        _ = WorkoutLogMigrationService.migrateIfNeeded(profile: &profile, repository: repo)

        let sessions = repo.loadWorkoutSessions()
        guard let migrated = sessions.first(where: { $0.id == entry.id }) else {
            return XCTFail("Expected to find a session keyed on the entry's ID")
        }
        XCTAssertEqual(migrated.name, "Pull day")
        XCTAssertEqual(migrated.startedAt, entryDate)
        XCTAssertEqual(
            migrated.finishedAt?.timeIntervalSince(entryDate) ?? 0,
            50 * 60,
            accuracy: 1,
            "finishedAt should be startedAt + durationMinutes"
        )
        XCTAssertTrue(migrated.exercises.isEmpty,
                      "Legacy entries had no per-exercise breakdown")
        XCTAssertEqual(migrated.note, "Legacy quick-log · 5 sets × 6 reps")
    }

    func test_migrateIfNeeded_handlesZeroDuration() {
        var profile = UserProfile.fresh
        profile.workoutHistory = [
            WorkoutEntry(date: Date(), name: "Walk", sets: 0, reps: 0, durationMinutes: 0)
        ]
        _ = WorkoutLogMigrationService.migrateIfNeeded(profile: &profile, repository: repo)
        let sessions = repo.loadWorkoutSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(
            sessions.first?.finishedAt?.timeIntervalSince(sessions.first?.startedAt ?? Date()) ?? -1,
            0,
            accuracy: 1
        )
    }

    func test_migrateIfNeeded_clampsNegativeDuration() {
        var profile = UserProfile.fresh
        profile.workoutHistory = [
            WorkoutEntry(date: Date(), name: "Bad data", sets: 1, reps: 1, durationMinutes: -10)
        ]
        _ = WorkoutLogMigrationService.migrateIfNeeded(profile: &profile, repository: repo)
        let sessions = repo.loadWorkoutSessions()
        XCTAssertEqual(
            sessions.first?.finishedAt?.timeIntervalSince(sessions.first?.startedAt ?? Date()) ?? -1,
            0,
            accuracy: 1,
            "Negative durations must be clamped to 0 — finishedAt before startedAt would break downstream filters"
        )
    }
}
