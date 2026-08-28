import XCTest
@testable import Peptide

/// Personal records are derived data; workout history is the source.
/// These tests pin the invariant that deleting a session can never leave
/// a PR standing that no surviving workout justifies. Runs against the
/// in-memory store (unlike PRDetectionEngineTests, which predates
/// `configureForTesting` and scrubs the live store instead).
@MainActor
final class PRConsistencyTests: XCTestCase {

    private var repo: SwiftDataRepository!
    private var store: DataStore!

    private let benchID = "Barbell_Bench_Press_-_Medium_Grip"

    override func setUp() {
        super.setUp()
        repo = SwiftDataRepository.shared
        repo.configureForTesting()
        store = DataStore()
    }

    override func tearDown() {
        repo.deleteAll()
        store = nil
        repo = nil
        super.tearDown()
    }

    private func finishedSession(
        weightKg: Double,
        reps: Int,
        daysAgo: Int
    ) -> WorkoutSession {
        let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return WorkoutSession(
            startedAt: start,
            finishedAt: start.addingTimeInterval(3600),
            exercises: [
                WorkoutExerciseEntry(
                    exerciseID: benchID,
                    index: 0,
                    sets: [SetEntry(index: 1, weightKg: weightKg, reps: reps,
                                    completed: true)]
                )
            ]
        )
    }

    private func benchRecord() -> PersonalRecord? {
        repo.loadPersonalRecords().first { $0.exerciseID == benchID }
    }

    func test_finishWorkout_sessionDeleted_rollsBackOrFlagsAssociatedPR() {
        let baseline = finishedSession(weightKg: 100, reps: 5, daysAgo: 10)
        let prSession = finishedSession(weightKg: 140, reps: 1, daysAgo: 2)
        repo.upsertWorkoutSession(baseline)
        repo.upsertWorkoutSession(prSession)
        PRDetectionEngine.shared.ingest(session: baseline)
        PRDetectionEngine.shared.ingest(session: prSession)
        XCTAssertEqual(benchRecord()?.bestAbsoluteWeightKg, 140)

        store.deleteWorkout(id: prSession.id)

        let record = benchRecord()
        XCTAssertEqual(record?.bestAbsoluteWeightKg, 100,
                       "Deleting the PR-setting session must roll the record back to the best surviving session")
        XCTAssertEqual(record?.bestEstimatedOneRepMaxKg,
                       SetEntry(index: 1, weightKg: 100, reps: 5, completed: true).estimatedOneRepMaxKg)
    }

    func test_workoutDeletion_lastSessionForExercise_removesPR() {
        let only = finishedSession(weightKg: 120, reps: 3, daysAgo: 1)
        repo.upsertWorkoutSession(only)
        PRDetectionEngine.shared.ingest(session: only)
        XCTAssertNotNil(benchRecord())

        store.deleteWorkout(id: only.id)

        XCTAssertNil(benchRecord(),
                     "With no surviving session for the exercise, the PR must not outlive its source")
    }

    func test_workoutDeletion_unrelatedExercise_leavesOtherPRsUntouched() {
        let bench = finishedSession(weightKg: 100, reps: 5, daysAgo: 5)
        var squat = finishedSession(weightKg: 150, reps: 5, daysAgo: 4)
        squat.exercises[0].exerciseID = "Barbell_Squat"
        repo.upsertWorkoutSession(bench)
        repo.upsertWorkoutSession(squat)
        PRDetectionEngine.shared.ingest(session: bench)
        PRDetectionEngine.shared.ingest(session: squat)

        store.deleteWorkout(id: squat.id)

        XCTAssertEqual(benchRecord()?.bestAbsoluteWeightKg, 100,
                       "Recompute must be scoped to the deleted session's exercises")
        XCTAssertNil(repo.loadPersonalRecords().first { $0.exerciseID == "Barbell_Squat" })
    }

    // MARK: - Input validation (Phase 9)

    func test_setEntryLimits_clampNegativeAndAbsurdValues() {
        XCTAssertEqual(SetEntryLimits.clampWeightKg(-20), 0)
        XCTAssertEqual(SetEntryLimits.clampWeightKg(0), 0, "Weight 0 is the bodyweight track and must stay valid")
        XCTAssertEqual(SetEntryLimits.clampWeightKg(500), 500, "Elite performance must not be rejected")
        XCTAssertEqual(SetEntryLimits.clampWeightKg(99999), SetEntryLimits.weightKg.upperBound)
        XCTAssertEqual(SetEntryLimits.clampWeightKg(.nan), 0)
        XCTAssertEqual(SetEntryLimits.clampWeightKg(.infinity), 0)
        XCTAssertEqual(SetEntryLimits.clampReps(-5), 0)
        XCTAssertEqual(SetEntryLimits.clampReps(100), 100)
        XCTAssertEqual(SetEntryLimits.clampReps(99999), SetEntryLimits.reps.upperBound)
    }

    func test_updateSet_clampsOutOfBoundsValues_atServiceBoundary() {
        let service = WorkoutSessionService.shared
        service.discardWorkout()
        defer { service.discardWorkout() }

        let bench = Exercise(
            id: benchID,
            name: "Barbell Bench Press",
            force: .push, level: .intermediate, mechanic: .compound,
            equipment: "barbell",
            primaryMuscles: ["chest"], secondaryMuscles: ["triceps", "shoulders"],
            instructions: [],
            category: .strength, images: []
        )
        _ = service.startWorkout()
        service.addExercise(bench)
        guard let entry = service.activeSession?.exercises.first,
              var set = entry.sets.first else {
            XCTFail("Seeded session should have one set")
            return
        }

        set.weightKg = -50
        set.reps = -3
        service.updateSet(set, inExerciseEntryID: entry.id)
        var stored = service.activeSession?.exercises.first?.sets.first
        XCTAssertEqual(stored?.weightKg, 0)
        XCTAssertEqual(stored?.reps, 0)

        set.weightKg = 99999
        set.reps = 12345
        service.updateSet(set, inExerciseEntryID: entry.id)
        stored = service.activeSession?.exercises.first?.sets.first
        XCTAssertEqual(stored?.weightKg, SetEntryLimits.weightKg.upperBound)
        XCTAssertEqual(stored?.reps, SetEntryLimits.reps.upperBound)
    }
}
