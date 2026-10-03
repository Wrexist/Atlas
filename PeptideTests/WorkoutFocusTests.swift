import XCTest
@testable import Peptide

final class WorkoutFocusStateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func test_pauseFreezesBothClocksAndResumeExcludesPausedTime() {
        var session = WorkoutSession(startedAt: start)
        session.focus = WorkoutFocusState(rest: WorkoutRestContext(
            sourceEntryID: UUID(), sourceSetID: UUID(), targetEntryID: UUID(), targetSetID: UUID(),
            endsAt: start.addingTimeInterval(100), totalSeconds: 90
        ))
        session.focus?.pause(at: start.addingTimeInterval(30))
        session.focus?.pause(at: start.addingTimeInterval(40))
        XCTAssertEqual(session.elapsedSeconds(now: start.addingTimeInterval(200)), 30)
        XCTAssertEqual(session.focus?.rest?.remaining(at: start.addingTimeInterval(200)), 70)
        session.focus?.resume(at: start.addingTimeInterval(200))
        session.focus?.resume(at: start.addingTimeInterval(210))
        XCTAssertEqual(session.elapsedSeconds(now: start.addingTimeInterval(210)), 40)
        XCTAssertEqual(session.focus?.rest?.endsAt, start.addingTimeInterval(270))
    }

    func test_oldSessionJSONDecodesWithoutFocus() throws {
        let session = WorkoutSession(startedAt: start)
        let data = try JSONEncoder().encode(session)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["focus"])
        let restored = try JSONDecoder().decode(WorkoutSession.self, from: data)
        XCTAssertNil(restored.focus)
        XCTAssertEqual(restored.elapsedSeconds(now: start.addingTimeInterval(90)), 90)
    }

    func test_duplicateCatalogEntriesRetainIndependentSelection() {
        let first = WorkoutExerciseEntry(exerciseID: "Incline_Dumbbell_Press", index: 0)
        let second = WorkoutExerciseEntry(exerciseID: "Incline_Dumbbell_Press", index: 1)
        let session = WorkoutSession(exercises: [first, second], focus: WorkoutFocusState(selectedEntryID: second.id))
        XCTAssertEqual(session.selectedExercise?.id, second.id)
    }

    func test_removingRestTargetRepairsSelectionAndCancelsRest() {
        let first = WorkoutExerciseEntry(exerciseID: "press", index: 0, sets: [
            SetEntry(index: 1, weightKg: 20, reps: 10, completed: true)
        ])
        let second = WorkoutExerciseEntry(exerciseID: "row", index: 1, sets: [
            SetEntry(index: 1, weightKg: 20, reps: 10)
        ])
        var session = WorkoutSession(exercises: [first, second], focus: WorkoutFocusState(
            selectedEntryID: second.id,
            rest: WorkoutRestContext(
                sourceEntryID: first.id, sourceSetID: first.sets[0].id,
                targetEntryID: second.id, targetSetID: second.sets[0].id,
                endsAt: start.addingTimeInterval(90), totalSeconds: 90
            )
        ))
        session.exercises.removeLast()
        session.repairFocus()
        XCTAssertEqual(session.selectedExercise?.id, first.id)
        XCTAssertNil(session.focus?.rest)
    }

    func test_expiredRestDoesNotReappearWhenPausing() {
        var focus = WorkoutFocusState(rest: WorkoutRestContext(
            sourceEntryID: UUID(), sourceSetID: UUID(), targetEntryID: UUID(), targetSetID: UUID(),
            endsAt: start, totalSeconds: 90
        ))
        focus.pause(at: start.addingTimeInterval(10))
        XCTAssertNil(focus.rest)
    }
}

@MainActor
final class WorkoutFocusServiceTests: XCTestCase {
    private var service: WorkoutSessionService!
    private var repo: SwiftDataRepository!

    override func setUp() {
        super.setUp()
        repo = SwiftDataRepository.shared
        repo.configureForTesting()
        service = WorkoutSessionService.shared
        service.discardWorkout()
    }

    override func tearDown() {
        service.discardWorkout()
        repo.deleteAll()
        super.tearDown()
    }

    @discardableResult
    private func start(sets: Int = 4) -> WorkoutExerciseEntry {
        let routine = Routine(name: "Incline press", exercises: [
            RoutineExercise(exerciseID: "Incline_Dumbbell_Press", index: 0, targetSets: sets, targetReps: 10)
        ])
        return service.startWorkout(routine: routine).exercises[0]
    }

    func test_completionCreatesDurableRestAndRepeatedSaveDoesNotRestartIt() throws {
        let entry = start()
        let now = Date()
        var set = entry.sets[0]
        set.completed = true
        service.updateSet(set, inExerciseEntryID: entry.id, now: now)
        let end = service.activeSession?.focus?.rest?.endsAt
        service.updateSet(set, inExerciseEntryID: entry.id, now: now.addingTimeInterval(20))
        XCTAssertEqual(service.activeSession?.focus?.rest?.endsAt, end)
        let restored = try XCTUnwrap(repo.loadActiveWorkoutSession())
        XCTAssertEqual(restored.focus?.rest?.endsAt?.timeIntervalSince1970 ?? 0,
                       end?.timeIntervalSince1970 ?? 0, accuracy: 1)
        XCTAssertEqual(restored.focus?.rest?.sourceSetID, set.id)
        XCTAssertEqual(restored.focus?.rest?.targetSetID, entry.sets[1].id)
    }

    func test_undoSourceSetClearsRestAndCompletionTimestamp() {
        let entry = start()
        var set = entry.sets[0]
        set.completed = true
        service.updateSet(set, inExerciseEntryID: entry.id)
        set.completed = false
        service.updateSet(set, inExerciseEntryID: entry.id)
        XCTAssertNil(service.activeSession?.focus?.rest)
        XCTAssertNil(service.activeSession?.exercises[0].sets[0].completedAt)
    }

    func test_finalSetAndWarmupsDoNotStartRest() {
        let entry = start(sets: 1)
        var set = entry.sets[0]
        set.completed = true
        service.updateSet(set, inExerciseEntryID: entry.id)
        XCTAssertNil(service.activeSession?.focus?.rest)
        service.addSet(toExerciseID: entry.id)
        service.addSet(toExerciseID: entry.id)
        var warmup = service.activeSession!.exercises[0].sets[1]
        warmup.isWarmup = true
        warmup.completed = true
        service.updateSet(warmup, inExerciseEntryID: entry.id)
        XCTAssertNil(service.activeSession?.focus?.rest)
        XCTAssertEqual(service.activeSession?.completedSetCount, 1)
    }

    func test_pausePersistsAndBlocksCompletionUntilResume() throws {
        let entry = start()
        service.togglePause()
        var set = entry.sets[0]
        set.completed = true
        service.updateSet(set, inExerciseEntryID: entry.id)
        XCTAssertEqual(service.activeSession?.completedSetCount, 0)
        XCTAssertTrue(try XCTUnwrap(repo.loadActiveWorkoutSession()).isPaused)
        service.togglePause()
        service.updateSet(set, inExerciseEntryID: entry.id)
        XCTAssertEqual(service.activeSession?.completedSetCount, 1)
    }

    func test_skipAndExpiryDoNotLogNextSet() throws {
        let entry = start()
        var set = entry.sets[0]
        set.completed = true
        service.updateSet(set, inExerciseEntryID: entry.id)
        service.skipRest()
        XCTAssertNil(service.activeSession?.focus?.rest)
        XCTAssertEqual(service.activeSession?.completedSetCount, 1)
        set = entry.sets[1]
        set.completed = true
        service.updateSet(set, inExerciseEntryID: entry.id)
        let end = try XCTUnwrap(service.activeSession?.focus?.rest?.endsAt)
        service.reconcileRest(now: end.addingTimeInterval(1))
        XCTAssertNil(service.activeSession?.focus?.rest)
        XCTAssertEqual(service.activeSession?.completedSetCount, 2)
    }

    func test_pausedRestSurvivesStorageRoundTrip() throws {
        let entry = start()
        var set = entry.sets[0]
        set.completed = true
        service.updateSet(set, inExerciseEntryID: entry.id)
        service.togglePause()
        let restored = try XCTUnwrap(repo.loadActiveWorkoutSession())
        XCTAssertNil(restored.focus?.rest?.endsAt)
        XCTAssertGreaterThan(try XCTUnwrap(restored.focus?.rest?.frozenSeconds), 0)
        XCTAssertTrue(restored.isPaused)
    }

    func test_liveActivityProjectsPausedDurationAndAuthoritativeRest() throws {
        let entry = start()
        var set = entry.sets[0]
        set.completed = true
        service.updateSet(set, inExerciseEntryID: entry.id)
        var session = try XCTUnwrap(service.activeSession)
        XCTAssertEqual(WorkoutLiveActivityService.state(for: session).restEndsAt, session.focus?.rest?.endsAt)
        service.togglePause()
        session = try XCTUnwrap(service.activeSession)
        let state = WorkoutLiveActivityService.state(for: session)
        XCTAssertEqual(state.status(), .paused)
        XCTAssertNil(state.restEndsAt)
        XCTAssertEqual(state.pausedElapsedSeconds, session.elapsedSeconds())
    }

    func test_finishWhilePausedPreservesActiveDurationAndClearsRest() throws {
        let entry = start()
        var set = entry.sets[0]
        set.completed = true
        service.updateSet(set, inExerciseEntryID: entry.id)
        service.togglePause()
        let duration = service.activeSession!.elapsedSeconds()
        let result = try XCTUnwrap(service.finishWorkout())
        XCTAssertEqual(result.session.elapsedSeconds(), duration)
        XCTAssertNil(result.session.focus?.rest)
        XCTAssertFalse(result.session.isPaused)
    }
}
