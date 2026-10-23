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

    func test_restUndoPreservesEditedLoadAndIdentityAndPersists() throws {
        let entry = start()
        let sessionID = service.activeSession?.id
        var set = entry.sets[0]
        set.completed = true
        service.updateSet(set, inExerciseEntryID: entry.id)
        set.weightKg = 31.5
        set.reps = 7
        service.updateSet(set, inExerciseEntryID: entry.id)
        service.undoRestSourceSet()
        // A second tap has no rest source and cannot undo a different set.
        service.undoRestSourceSet()
        let restored = try XCTUnwrap(repo.loadActiveWorkoutSession())
        XCTAssertEqual(restored.id, sessionID)
        XCTAssertNil(restored.focus?.rest)
        XCTAssertEqual(restored.selectedExercise?.id, entry.id)
        let undone = try XCTUnwrap(restored.exercises.first?.sets.first)
        XCTAssertEqual(undone.id, set.id)
        XCTAssertEqual(undone.weightKg, 31.5)
        XCTAssertEqual(undone.reps, 7)
        XCTAssertFalse(undone.completed)
        XCTAssertNil(undone.completedAt)
        XCTAssertEqual(restored.completedSetCount, 0)
    }

    func test_restUndoDoesNotChangePausedWorkout() {
        let entry = start()
        var set = entry.sets[0]
        set.completed = true
        service.updateSet(set, inExerciseEntryID: entry.id)
        service.togglePause()
        service.undoRestSourceSet()
        XCTAssertEqual(service.activeSession?.completedSetCount, 1)
        XCTAssertNotNil(service.activeSession?.focus?.rest)
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

    func test_completeNextSet_ticksFirstOpenSetAndStartsRest() throws {
        let entry = start()
        service.completeNextSet()
        let session = try XCTUnwrap(service.activeSession)
        XCTAssertTrue(session.exercises[0].sets[0].completed)
        XCTAssertEqual(session.completedSetCount, 1)
        XCTAssertEqual(session.focus?.rest?.targetSetID, entry.sets[1].id)
    }

    func test_completeNextSet_duringRest_ticksTheSetTheRestLeadsTo() throws {
        start()
        service.completeNextSet()
        service.completeNextSet()
        let sets = try XCTUnwrap(service.activeSession?.exercises[0].sets)
        XCTAssertEqual(sets.map(\.completed), [true, true, false, false])
    }

    func test_completeNextSet_whilePaused_changesNothing() {
        start()
        service.togglePause()
        service.completeNextSet()
        XCTAssertEqual(service.activeSession?.completedSetCount, 0)
    }

    func test_liveActivityTapForAnotherWorkout_isDropped() throws {
        start()
        PendingWorkoutActionStore.enqueue(.init(sessionId: UUID(), action: .completeSet, tappedAt: Date()))
        WorkoutActivityActionProcessor.drain()
        XCTAssertEqual(service.activeSession?.completedSetCount, 0)

        let id = try XCTUnwrap(service.activeSession?.id)
        PendingWorkoutActionStore.enqueue(.init(sessionId: id, action: .completeSet, tappedAt: Date()))
        WorkoutActivityActionProcessor.drain()
        XCTAssertEqual(service.activeSession?.completedSetCount, 1)
    }

    func test_liveActivitySkipTappedBeforeThisRest_leavesTheRestRunning() throws {
        start()
        service.completeNextSet()
        let id = try XCTUnwrap(service.activeSession?.id)

        PendingWorkoutActionStore.enqueue(.init(sessionId: id, action: .skipRest, tappedAt: Date().addingTimeInterval(-60)))
        WorkoutActivityActionProcessor.drain()
        XCTAssertNotNil(service.activeSession?.focus?.rest)

        PendingWorkoutActionStore.enqueue(.init(sessionId: id, action: .skipRest, tappedAt: Date()))
        WorkoutActivityActionProcessor.drain()
        XCTAssertNil(service.activeSession?.focus?.rest)
    }

    func test_adjustRest_movesTheRingWithTheTimeLeft() throws {
        start()
        let started = Date()
        service.completeNextSet(now: started)
        let total = try XCTUnwrap(service.activeSession?.focus?.rest?.totalSeconds)
        let midway = started.addingTimeInterval(total / 2)
        let before = try XCTUnwrap(service.activeSession?.focus?.rest?.remainingFraction(at: midway))

        service.adjustRest(by: -15, now: midway)
        let shortened = try XCTUnwrap(service.activeSession?.focus?.rest?.remainingFraction(at: midway))
        service.adjustRest(by: 15, now: midway)
        let restored = try XCTUnwrap(service.activeSession?.focus?.rest?.remainingFraction(at: midway))

        XCTAssertLessThan(shortened, before)
        XCTAssertGreaterThan(restored, shortened)
        XCTAssertLessThanOrEqual(restored, 1)
    }

    func test_liveActivityTapInAppProcess_isAppliedBeforeIntentReturns() async throws {
        start()
        let id = try XCTUnwrap(service.activeSession?.id)
        PendingWorkoutActionStore.applyInProcess = { WorkoutActivityActionProcessor.drain() }
        _ = try await WorkoutActivityActionIntent(sessionId: id, action: .completeSet).perform()
        XCTAssertEqual(service.activeSession?.completedSetCount, 1)
    }
}

final class PendingWorkoutActionStoreTests: XCTestCase {
    private let tappedAt = Date(timeIntervalSince1970: 1_000)
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PendingWorkoutActionStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func enqueue(_ action: WorkoutActivityAction, session: UUID, after seconds: TimeInterval) {
        PendingWorkoutActionStore.enqueue(
            .init(sessionId: session, action: action, tappedAt: tappedAt.addingTimeInterval(seconds)),
            defaults: defaults
        )
    }

    func test_drain_completeSetDoubleTap_keepsOneTap() {
        let session = UUID()
        enqueue(.completeSet, session: session, after: 0)
        enqueue(.completeSet, session: session, after: 0.4)
        XCTAssertEqual(PendingWorkoutActionStore.drain(defaults: defaults).count, 1)
    }

    func test_drain_completeSetsFurtherApart_keepsBoth() {
        let session = UUID()
        enqueue(.completeSet, session: session, after: 0)
        enqueue(.completeSet, session: session, after: 5)
        XCTAssertEqual(PendingWorkoutActionStore.drain(defaults: defaults).count, 2)
    }

    func test_drain_quickTapsOnDifferentActionsOrWorkouts_keepsAll() {
        let session = UUID()
        enqueue(.completeSet, session: session, after: 0)
        enqueue(.skipRest, session: session, after: 0.2)
        enqueue(.completeSet, session: UUID(), after: 0.3)
        XCTAssertEqual(PendingWorkoutActionStore.drain(defaults: defaults).count, 3)
    }

    func test_isDoubleTap_completeSetRightAfterAQueuedOne_isTrue() {
        let session = UUID()
        enqueue(.completeSet, session: session, after: 0)
        let tap = PendingWorkoutActionStore.Pending(
            sessionId: session, action: .completeSet, tappedAt: tappedAt.addingTimeInterval(0.4)
        )
        XCTAssertTrue(PendingWorkoutActionStore.isDoubleTap(tap, defaults: defaults))
    }

    func test_isDoubleTap_completeSetRightAfterADrainedOne_isTrue() {
        let session = UUID()
        enqueue(.completeSet, session: session, after: 0)
        _ = PendingWorkoutActionStore.drain(defaults: defaults)
        let tap = PendingWorkoutActionStore.Pending(
            sessionId: session, action: .completeSet, tappedAt: tappedAt.addingTimeInterval(0.4)
        )
        XCTAssertTrue(PendingWorkoutActionStore.isDoubleTap(tap, defaults: defaults))
    }

    func test_isDoubleTap_completeSetAfterTheWindowOrOnAnotherWorkout_isFalse() {
        let session = UUID()
        enqueue(.completeSet, session: session, after: 0)
        let later = PendingWorkoutActionStore.Pending(
            sessionId: session, action: .completeSet, tappedAt: tappedAt.addingTimeInterval(5)
        )
        let elsewhere = PendingWorkoutActionStore.Pending(
            sessionId: UUID(), action: .completeSet, tappedAt: tappedAt.addingTimeInterval(0.4)
        )
        XCTAssertFalse(PendingWorkoutActionStore.isDoubleTap(later, defaults: defaults))
        XCTAssertFalse(PendingWorkoutActionStore.isDoubleTap(elsewhere, defaults: defaults))
    }

    func test_drain_clearsTheInbox() {
        enqueue(.skipRest, session: UUID(), after: 0)
        _ = PendingWorkoutActionStore.drain(defaults: defaults)
        XCTAssertTrue(PendingWorkoutActionStore.drain(defaults: defaults).isEmpty)
    }
}
