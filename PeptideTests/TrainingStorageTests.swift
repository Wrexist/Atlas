import XCTest
@testable import Peptide

/// Round-trip tests for the training-side SwiftData layer:
/// `StoredWorkoutSession`, `StoredCustomExercise`, `StoredRoutine`, and
/// `StoredPersonalRecord`. These models embed JSON blobs for their
/// nested arrays (sets, exercises, instructions), so the encode →
/// decode → re-encode path is the most fragile surface to regress.
@MainActor
final class TrainingStorageTests: XCTestCase {

    private var repo: SwiftDataRepository!

    override func setUp() {
        super.setUp()
        repo = SwiftDataRepository.shared
        repo.configureForTesting()
    }

    override func tearDown() {
        repo.deleteAll()
        repo = nil
        super.tearDown()
    }

    // MARK: - Workout session round-trip

    private func makeSession() -> WorkoutSession {
        WorkoutSession(
            name: "Push day",
            routineID: UUID(),
            programID: nil,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_700_003_600),
            exercises: [
                WorkoutExerciseEntry(
                    exerciseID: "Barbell_Bench_Press",
                    index: 0,
                    sets: [
                        SetEntry(index: 1, weightKg: 60, reps: 10,
                                 completed: true, isWarmup: true),
                        SetEntry(index: 2, weightKg: 100, reps: 5,
                                 rpe: 8.0, completed: true),
                        SetEntry(index: 3, weightKg: 100, reps: 5,
                                 rpe: 8.5, note: "felt heavy",
                                 completed: true),
                    ],
                    note: "narrow grip variant",
                    restSeconds: 120
                ),
                WorkoutExerciseEntry(
                    exerciseID: "Dumbbell_Shoulder_Press",
                    index: 1,
                    sets: [
                        SetEntry(index: 1, weightKg: 25, reps: 10, completed: true),
                    ]
                ),
            ],
            note: "good day",
            perceivedEffort: 4
        )
    }

    func test_upsertWorkoutSession_roundTrips_allFields() {
        let original = makeSession()
        repo.upsertWorkoutSession(original)
        let loaded = repo.loadWorkoutSessions()
        XCTAssertEqual(loaded.count, 1)
        let restored = try? XCTUnwrap(loaded.first)
        XCTAssertEqual(restored?.id, original.id)
        XCTAssertEqual(restored?.name, original.name)
        XCTAssertEqual(restored?.routineID, original.routineID)
        XCTAssertEqual(restored?.note, original.note)
        XCTAssertEqual(restored?.perceivedEffort, original.perceivedEffort)
        XCTAssertEqual(restored?.exercises.count, 2)
        XCTAssertEqual(restored?.exercises.first?.sets.count, 3)
        XCTAssertEqual(restored?.exercises.first?.sets[2].note, "felt heavy")
        XCTAssertEqual(restored?.exercises.first?.sets[2].rpe, 8.5)
    }

    func test_upsertWorkoutSession_isIdempotent() {
        let session = makeSession()
        repo.upsertWorkoutSession(session)
        repo.upsertWorkoutSession(session)
        XCTAssertEqual(repo.loadWorkoutSessions().count, 1,
                       "Re-saving the same id must not duplicate the row")
    }

    func test_upsertWorkoutSession_updatesExistingRow() {
        var session = makeSession()
        repo.upsertWorkoutSession(session)
        session.note = "edited note"
        repo.upsertWorkoutSession(session)

        let loaded = repo.loadWorkoutSessions()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.note, "edited note")
    }

    func test_deleteWorkoutSession_removesRow() {
        let session = makeSession()
        repo.upsertWorkoutSession(session)
        repo.deleteWorkoutSession(id: session.id)
        XCTAssertTrue(repo.loadWorkoutSessions().isEmpty)
    }

    func test_loadActiveWorkoutSession_returnsOnlyInProgress() {
        let finished = makeSession()  // already has a finishedAt
        let active = WorkoutSession(
            name: "Active",
            startedAt: Date(),
            finishedAt: nil,
            exercises: []
        )
        repo.upsertWorkoutSession(finished)
        repo.upsertWorkoutSession(active)

        let resolved = repo.loadActiveWorkoutSession()
        XCTAssertEqual(resolved?.id, active.id)
        XCTAssertNil(resolved?.finishedAt)
    }

    func test_loadActiveWorkoutSession_isNilWhenNoneActive() {
        repo.upsertWorkoutSession(makeSession())  // has finishedAt
        XCTAssertNil(repo.loadActiveWorkoutSession())
    }

    func test_loadWorkoutSessions_isSortedByStartedAt_desc() {
        let earlier = WorkoutSession(
            startedAt: Date(timeIntervalSince1970: 1),
            finishedAt: Date(timeIntervalSince1970: 100),
            exercises: []
        )
        let later = WorkoutSession(
            startedAt: Date(timeIntervalSince1970: 100_000),
            finishedAt: Date(timeIntervalSince1970: 100_100),
            exercises: []
        )
        repo.upsertWorkoutSession(earlier)
        repo.upsertWorkoutSession(later)

        let loaded = repo.loadWorkoutSessions()
        XCTAssertEqual(loaded.map(\.id), [later.id, earlier.id])
    }

    // MARK: - Custom exercise round-trip

    func test_customExercise_roundTrips() {
        let original = CustomExercise(
            name: "Reverse Pec Deck",
            primaryMuscles: ["shoulders"],
            secondaryMuscles: ["traps"],
            equipment: "machine",
            instructions: ["sit", "squeeze", "return"]
        )
        repo.upsertCustomExercise(original)
        let loaded = repo.loadCustomExercises()
        XCTAssertEqual(loaded.count, 1)
        let restored = loaded.first
        XCTAssertEqual(restored?.id, original.id)
        XCTAssertEqual(restored?.name, original.name)
        XCTAssertEqual(restored?.primaryMuscles, ["shoulders"])
        XCTAssertEqual(restored?.instructions, ["sit", "squeeze", "return"])
    }

    func test_customExercise_upsertIsIdempotent() {
        let exercise = CustomExercise(name: "Test")
        repo.upsertCustomExercise(exercise)
        repo.upsertCustomExercise(exercise)
        XCTAssertEqual(repo.loadCustomExercises().count, 1)
    }

    func test_customExercise_deleteRemovesRow() {
        let exercise = CustomExercise(name: "Test")
        repo.upsertCustomExercise(exercise)
        repo.deleteCustomExercise(id: exercise.id)
        XCTAssertTrue(repo.loadCustomExercises().isEmpty)
    }

    // MARK: - Routine round-trip

    func test_routine_roundTrips() {
        let original = Routine(
            name: "Upper A",
            subtitle: "Strength",
            exercises: [
                RoutineExercise(exerciseID: "Barbell_Bench_Press",
                                index: 0, targetSets: 5, targetReps: 5,
                                targetRPE: 8.0, restSeconds: 180),
                RoutineExercise(exerciseID: "Pullups",
                                index: 1, targetSets: 4, targetReps: 8),
            ],
            defaultRestSeconds: 120
        )
        repo.upsertRoutine(original)
        let loaded = repo.loadRoutines()
        XCTAssertEqual(loaded.count, 1)
        let restored = loaded.first
        XCTAssertEqual(restored?.name, "Upper A")
        XCTAssertEqual(restored?.subtitle, "Strength")
        XCTAssertEqual(restored?.exercises.count, 2)
        XCTAssertEqual(restored?.exercises.first?.targetSets, 5)
        XCTAssertEqual(restored?.exercises.first?.restSeconds, 180)
        XCTAssertEqual(restored?.defaultRestSeconds, 120)
    }

    func test_routines_sortedByUpdatedAt_desc() {
        let earlier = Routine(name: "Old",
                              updatedAt: Date(timeIntervalSince1970: 1))
        let later = Routine(name: "New",
                            updatedAt: Date(timeIntervalSince1970: 100_000))
        repo.upsertRoutine(earlier)
        repo.upsertRoutine(later)
        XCTAssertEqual(repo.loadRoutines().map(\.name), ["New", "Old"])
    }

    // MARK: - Personal record round-trip

    func test_personalRecord_roundTrips() {
        let original = PersonalRecord(
            exerciseID: "Barbell_Bench_Press",
            bestEstimatedOneRepMaxKg: 140,
            bestEstimatedOneRepMaxAt: Date(timeIntervalSince1970: 1_000),
            bestAbsoluteWeightKg: 135,
            bestAbsoluteWeightAt: Date(timeIntervalSince1970: 1_000),
            bestSessionVolumeKg: 5400,
            bestSessionVolumeAt: Date(timeIntervalSince1970: 1_000)
        )
        repo.upsertPersonalRecord(original)
        let loaded = repo.loadPersonalRecords()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.exerciseID, "Barbell_Bench_Press")
        XCTAssertEqual(loaded.first?.bestEstimatedOneRepMaxKg, 140)
        XCTAssertEqual(loaded.first?.bestSessionVolumeKg, 5400)
    }

    func test_personalRecord_upsertReplaces_byExerciseID() {
        let initial = PersonalRecord(
            exerciseID: "Squat",
            bestEstimatedOneRepMaxKg: 100
        )
        let updated = PersonalRecord(
            exerciseID: "Squat",
            bestEstimatedOneRepMaxKg: 150
        )
        repo.upsertPersonalRecord(initial)
        repo.upsertPersonalRecord(updated)
        let loaded = repo.loadPersonalRecords()
        XCTAssertEqual(loaded.count, 1,
                       "PR upsert by exerciseID must not create duplicates")
        XCTAssertEqual(loaded.first?.bestEstimatedOneRepMaxKg, 150)
    }

    // MARK: - Empty state

    func test_loadOnEmptyStore_returnsEmptyArrays() {
        XCTAssertTrue(repo.loadWorkoutSessions().isEmpty)
        XCTAssertTrue(repo.loadCustomExercises().isEmpty)
        XCTAssertTrue(repo.loadRoutines().isEmpty)
        XCTAssertTrue(repo.loadPersonalRecords().isEmpty)
    }
}
