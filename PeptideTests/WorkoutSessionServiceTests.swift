import XCTest
@testable import Peptide

@MainActor
final class WorkoutSessionServiceTests: XCTestCase {

    private var service: WorkoutSessionService!
    private var repo: SwiftDataRepository!

    override func setUp() {
        super.setUp()
        repo = SwiftDataRepository.shared
        repo.configureForTesting()
        service = WorkoutSessionService.shared
        // Wipe any singleton state from a previous test.
        service.discardWorkout()
    }

    override func tearDown() {
        service.discardWorkout()
        repo.deleteAll()
        super.tearDown()
    }

    // MARK: - Lifecycle

    func test_startWorkout_setsActiveSession_andPersists() {
        let started = service.startWorkout()
        XCTAssertNotNil(service.activeSession)
        XCTAssertEqual(service.activeSession?.id, started.id)
        XCTAssertTrue(service.activeSession?.isActive ?? false)
        XCTAssertEqual(repo.loadWorkoutSessions().count, 1)
    }

    func test_startWorkout_discardsPriorActive() {
        let first = service.startWorkout()
        let second = service.startWorkout()
        XCTAssertNotEqual(first.id, second.id)
        let stored = repo.loadWorkoutSessions()
        XCTAssertEqual(stored.count, 1, "Prior active session should be discarded on a fresh start")
        XCTAssertEqual(stored.first?.id, second.id)
    }

    func test_startWorkout_fromRoutine_seedsExerciseSlots() {
        let routine = Routine(name: "Push", exercises: [
            RoutineExercise(exerciseID: "Barbell_Bench_Press_-_Medium_Grip", index: 0,
                            targetSets: 5, targetReps: 5),
            RoutineExercise(exerciseID: "Standing_Military_Press", index: 1,
                            targetSets: 3, targetReps: 8),
        ])
        let session = service.startWorkout(routine: routine)
        XCTAssertEqual(session.name, "Push")
        XCTAssertEqual(session.routineID, routine.id)
        XCTAssertEqual(session.exercises.count, 2)
        XCTAssertEqual(session.exercises.first?.sets.count, 5)
        XCTAssertEqual(session.exercises.first?.sets.first?.reps, 5)
    }

    func test_finishWorkout_setsFinishedAt_andClearsActive() {
        _ = service.startWorkout()
        let finished = service.finishWorkout(perceivedEffort: 4, note: "Good day")
        // FinishedWorkout is a wrapper — (session, detectedPRs) — so the
        // session's own fields are one level down, not beside it.
        XCTAssertNotNil(finished?.session.finishedAt)
        XCTAssertEqual(finished?.session.perceivedEffort, 4)
        XCTAssertEqual(finished?.session.note, "Good day")
        XCTAssertNil(service.activeSession,
                     "Service should drop activeSession after finish")
    }

    func test_finishWorkout_withoutActiveSession_returnsNil() {
        XCTAssertNil(service.finishWorkout())
    }

    func test_discardWorkout_removesPersistedRow() {
        let session = service.startWorkout()
        XCTAssertEqual(repo.loadWorkoutSessions().count, 1)
        service.discardWorkout()
        XCTAssertNil(service.activeSession)
        XCTAssertEqual(repo.loadWorkoutSessions().filter { $0.id == session.id }.count, 0)
    }

    // MARK: - Mutations

    private func bench() -> Exercise {
        Exercise(
            id: "Barbell_Bench_Press_-_Medium_Grip",
            name: "Barbell Bench Press",
            force: .push, level: .intermediate, mechanic: .compound,
            equipment: "barbell",
            primaryMuscles: ["chest"], secondaryMuscles: ["triceps", "shoulders"],
            instructions: [],
            category: .strength, images: []
        )
    }

    func test_addExercise_appendsToSession_withSeedSet() {
        _ = service.startWorkout()
        service.addExercise(bench())
        let exercises = service.activeSession?.exercises ?? []
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises.first?.sets.count, 1,
                       "Adding an exercise should seed one empty set")
    }

    func test_addExercise_reindexesByPosition() {
        _ = service.startWorkout()
        service.addExercise(bench())
        service.addExercise(bench())
        let indexes = service.activeSession?.exercises.map(\.index) ?? []
        XCTAssertEqual(indexes, [0, 1])
    }

    func test_addSet_prefillsFromPreviousSet() {
        _ = service.startWorkout()
        service.addExercise(bench())
        guard let entryID = service.activeSession?.exercises.first?.id else {
            return XCTFail("Missing entry")
        }
        // Manually update the seed set's values...
        guard var seed = service.activeSession?.exercises.first?.sets.first else {
            return XCTFail("Missing seed set")
        }
        seed.weightKg = 80
        seed.reps = 5
        service.updateSet(seed, inExerciseEntryID: entryID)

        service.addSet(toExerciseID: entryID)
        let sets = service.activeSession?.exercises.first?.sets ?? []
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets.last?.weightKg, 80,
                       "New set should prefill from the previous set's weight")
        XCTAssertEqual(sets.last?.reps, 5)
    }

    func test_addSet_assignsNextIndex() {
        _ = service.startWorkout()
        service.addExercise(bench())
        guard let entryID = service.activeSession?.exercises.first?.id else {
            return XCTFail()
        }
        service.addSet(toExerciseID: entryID)
        service.addSet(toExerciseID: entryID)
        let indexes = service.activeSession?.exercises.first?.sets.map(\.index) ?? []
        XCTAssertEqual(indexes, [1, 2, 3])
    }

    func test_removeSet_reindexesRemaining() {
        _ = service.startWorkout()
        service.addExercise(bench())
        guard let entryID = service.activeSession?.exercises.first?.id else {
            return XCTFail()
        }
        service.addSet(toExerciseID: entryID)
        service.addSet(toExerciseID: entryID)
        // Sets [1, 2, 3]; remove the middle.
        guard let middle = service.activeSession?.exercises.first?.sets[1].id else {
            return XCTFail()
        }
        service.removeSet(setID: middle, fromExerciseEntryID: entryID)
        let indexes = service.activeSession?.exercises.first?.sets.map(\.index) ?? []
        XCTAssertEqual(indexes, [1, 2],
                       "Remaining sets should be 1-indexed contiguously after a delete")
    }

    func test_updateSet_stampsCompletedAt_onCheckOff() {
        _ = service.startWorkout()
        service.addExercise(bench())
        guard let entryID = service.activeSession?.exercises.first?.id,
              var set = service.activeSession?.exercises.first?.sets.first
        else { return XCTFail() }

        set.completed = true
        service.updateSet(set, inExerciseEntryID: entryID)
        XCTAssertNotNil(service.activeSession?.exercises.first?.sets.first?.completedAt)

        // Toggle back off — completedAt should clear.
        set.completed = false
        service.updateSet(set, inExerciseEntryID: entryID)
        XCTAssertNil(service.activeSession?.exercises.first?.sets.first?.completedAt)
    }

    func test_removeExercise_reindexesRemainingPositions() {
        _ = service.startWorkout()
        service.addExercise(bench())
        service.addExercise(bench())
        service.addExercise(bench())
        guard let middleID = service.activeSession?.exercises[1].id else {
            return XCTFail()
        }
        service.removeExercise(id: middleID)
        let indexes = service.activeSession?.exercises.map(\.index) ?? []
        XCTAssertEqual(indexes, [0, 1])
    }

    func test_renameWorkout_emptyStringClearsName() {
        _ = service.startWorkout(routine: Routine(name: "Old", exercises: []))
        service.renameWorkout("  ")
        XCTAssertNil(service.activeSession?.name,
                     "Whitespace-only rename should clear name to nil")
    }
}

// Renamed from `PRDetectionEngineTests` — that name is already taken
// by the dedicated `PRDetectionEngineTests.swift` (bodyweight-rep PR
// coverage). Two classes with the same name failed the test build with
// "invalid redeclaration". These ingest-focused tests keep a distinct
// name so both suites compile and run.
@MainActor
final class PRDetectionEngineIngestTests: XCTestCase {

    private var repo: SwiftDataRepository!

    override func setUp() {
        super.setUp()
        repo = SwiftDataRepository.shared
        repo.configureForTesting()
    }

    override func tearDown() {
        repo.deleteAll()
        super.tearDown()
    }

    private func session(exerciseID: String, sets: [SetEntry]) -> WorkoutSession {
        WorkoutSession(
            startedAt: Date().addingTimeInterval(-3600),
            finishedAt: Date(),
            exercises: [WorkoutExerciseEntry(exerciseID: exerciseID, index: 0, sets: sets)]
        )
    }

    func test_ingest_firstSession_recordsAllThreePRs() {
        let s = session(exerciseID: "Bench", sets: [
            SetEntry(index: 1, weightKg: 100, reps: 5, completed: true),
            SetEntry(index: 2, weightKg: 100, reps: 5, completed: true),
        ])
        let detected = PRDetectionEngine.shared.ingest(session: s)
        XCTAssertEqual(detected.count, 3,
                       "First session for an exercise should set e1RM + abs + volume PRs")
        let stored = repo.loadPersonalRecords()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.exerciseID, "Bench")
        XCTAssertNotNil(stored.first?.bestEstimatedOneRepMaxKg)
    }

    func test_ingest_subsequentLowerSession_doesNotOverwrite() {
        let big = session(exerciseID: "Bench", sets: [
            SetEntry(index: 1, weightKg: 120, reps: 5, completed: true),
        ])
        PRDetectionEngine.shared.ingest(session: big)

        let small = session(exerciseID: "Bench", sets: [
            SetEntry(index: 1, weightKg: 80, reps: 5, completed: true),
        ])
        let detected = PRDetectionEngine.shared.ingest(session: small)
        XCTAssertTrue(detected.isEmpty,
                      "A weaker session should not detect new PRs")
        let stored = repo.loadPersonalRecords().first
        XCTAssertEqual(stored?.bestAbsoluteWeightKg, 120)
    }

    func test_ingest_warmupAndIncompleteSets_excluded() {
        let s = session(exerciseID: "Bench", sets: [
            SetEntry(index: 1, weightKg: 200, reps: 1, completed: true, isWarmup: true),
            SetEntry(index: 2, weightKg: 150, reps: 1, completed: false),
            SetEntry(index: 3, weightKg: 100, reps: 5, completed: true),
        ])
        PRDetectionEngine.shared.ingest(session: s)
        let stored = repo.loadPersonalRecords().first
        XCTAssertEqual(stored?.bestAbsoluteWeightKg, 100,
                       "Warmup + incomplete sets should not contribute to PRs")
    }

    func test_ingest_inProgressSession_isSkipped() {
        let s = WorkoutSession(
            startedAt: Date(),
            finishedAt: nil,
            exercises: [WorkoutExerciseEntry(exerciseID: "Bench", index: 0,
                sets: [SetEntry(index: 1, weightKg: 999, reps: 1, completed: true)])]
        )
        let detected = PRDetectionEngine.shared.ingest(session: s)
        XCTAssertTrue(detected.isEmpty,
                      "Only finished sessions should produce PRs")
        XCTAssertTrue(repo.loadPersonalRecords().isEmpty)
    }
}
