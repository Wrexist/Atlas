import XCTest
@testable import Peptide

/// The Watch's optimistic guess must land where the phone will, or a set
/// logged on the wrist flickers back when the phone's push arrives.
final class WatchWorkoutSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_166_000)

    private func row(_ index: Int, completed: Bool = false, warmup: Bool = false) -> WatchWorkoutSnapshot.SetRow {
        .init(id: UUID(), index: index, weightKg: 60, reps: 8, completed: completed, isWarmup: warmup, logsReps: true)
    }

    private func snapshot(_ exercises: [WatchWorkoutSnapshot.Exercise]) -> WatchWorkoutSnapshot {
        WatchWorkoutSnapshot(
            sessionId: UUID(), name: "Push", timerStartedAt: now.addingTimeInterval(-600),
            pausedElapsedSeconds: nil, exercises: exercises,
            selectedExerciseID: exercises.first?.id, rest: nil
        )
    }

    func test_completeSet_logsValuesAndRestsTowardNextWorkingSet() throws {
        let press = WatchWorkoutSnapshot.Exercise(id: UUID(), name: "Press", restSeconds: 90, sets: [row(1), row(2)])
        let workout = snapshot([press])

        let next = workout.applying(.completeSet(exerciseID: press.id, setID: press.sets[0].id, weightKg: 62.5, reps: 6), at: now)

        let done = try XCTUnwrap(next.exercises.first?.sets.first)
        XCTAssertTrue(done.completed)
        XCTAssertEqual(done.weightKg, 62.5)
        XCTAssertEqual(done.reps, 6)
        XCTAssertEqual(next.rest?.endsAt, now.addingTimeInterval(90))
        XCTAssertEqual(next.rest?.targetSetID, press.sets[1].id)
        XCTAssertEqual(next.upNext?.set.id, press.sets[1].id)
        XCTAssertTrue(next.isResting(at: now))
    }

    func test_completeWarmup_startsNoRest() {
        let press = WatchWorkoutSnapshot.Exercise(id: UUID(), name: "Press", restSeconds: 90, sets: [row(1, warmup: true), row(2)])
        let next = snapshot([press]).applying(
            .completeSet(exerciseID: press.id, setID: press.sets[0].id, weightKg: 40, reps: 10), at: now
        )
        XCTAssertNil(next.rest)
        XCTAssertEqual(next.completedSets, 0)
        XCTAssertEqual(next.upNext?.set.id, press.sets[1].id)
    }

    func test_lastSetOfExercise_restsTowardTheNextExercise_andSkipFollowsIt() throws {
        let press = WatchWorkoutSnapshot.Exercise(id: UUID(), name: "Press", restSeconds: 60, sets: [row(1)])
        let row2 = WatchWorkoutSnapshot.Exercise(id: UUID(), name: "Row", restSeconds: 60, sets: [row(1)])
        let resting = snapshot([press, row2]).applying(
            .completeSet(exerciseID: press.id, setID: press.sets[0].id, weightKg: 60, reps: 8), at: now
        )
        XCTAssertEqual(resting.rest?.targetExerciseID, row2.id)
        XCTAssertEqual(resting.upNext?.exercise.id, row2.id)

        let skipped = resting.applying(.skipRest, at: now)
        XCTAssertNil(skipped.rest)
        XCTAssertEqual(skipped.selectedExercise?.id, row2.id)
    }

    func test_extendRestPastZero_endsTheRest() {
        let press = WatchWorkoutSnapshot.Exercise(id: UUID(), name: "Press", restSeconds: 20, sets: [row(1), row(2)])
        let resting = snapshot([press]).applying(
            .completeSet(exerciseID: press.id, setID: press.sets[0].id, weightKg: 60, reps: 8), at: now
        )
        XCTAssertEqual(resting.applying(.extendRest(seconds: 30), at: now).rest?.endsAt, now.addingTimeInterval(50))
        XCTAssertNil(resting.applying(.extendRest(seconds: -30), at: now).rest)
    }

    func test_pauseFreezesTheClockAndBlocksLogging_resumeExcludesPausedTime() {
        let press = WatchWorkoutSnapshot.Exercise(id: UUID(), name: "Press", restSeconds: 90, sets: [row(1)])
        let paused = snapshot([press]).applying(.setPaused(true), at: now)
        XCTAssertEqual(paused.pausedElapsedSeconds, 600)

        let blocked = paused.applying(.completeSet(exerciseID: press.id, setID: press.sets[0].id, weightKg: 60, reps: 8), at: now)
        XCTAssertEqual(blocked.completedSets, 0)

        let resumed = paused.applying(.setPaused(false), at: now.addingTimeInterval(120))
        XCTAssertNil(resumed.pausedElapsedSeconds)
        XCTAssertEqual(resumed.timerStartedAt, now.addingTimeInterval(120 - 600))
    }

    func test_addSet_copiesTheLastSetUnderTheWatchChosenID() {
        let press = WatchWorkoutSnapshot.Exercise(id: UUID(), name: "Press", restSeconds: 90, sets: [row(1, completed: true)])
        let id = UUID()
        let next = snapshot([press]).applying(.addSet(exerciseID: press.id, setID: id), at: now)
        XCTAssertEqual(next.upNext?.set.id, id)
        XCTAssertEqual(next.upNext?.set.index, 2)
        XCTAssertEqual(next.upNext?.set.weightKg, 60)
    }

    func test_requestRoundTripsThroughTheMessagePayload() throws {
        let request = WatchWorkoutRequest(
            sessionId: UUID(),
            command: .completeSet(exerciseID: UUID(), setID: UUID(), weightKg: 102.5, reps: 5),
            issuedAt: now
        )
        let payload = try XCTUnwrap(request.encoded())
        XCTAssertEqual(WatchWorkoutRequest.decode(payload), request)
        XCTAssertEqual(
            WatchWorkoutRequest.decode(try XCTUnwrap(WatchWorkoutRequest(sessionId: UUID(), command: .setPaused(true), issuedAt: now).encoded()))?.command,
            .setPaused(true)
        )
    }

    func test_olderPhonePayloadWithoutWorkoutStillDecodes() throws {
        let json = #"{"todayEntries":[],"completedToday":0,"totalToday":0,"lastUpdated":"2025-10-11T07:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try decoder.decode(WatchData.self, from: Data(json.utf8))
        XCTAssertNil(data.workout)
        XCTAssertNil(data.training)
    }

    func test_replacingEntries_keepsTheWorkout() {
        let press = WatchWorkoutSnapshot.Exercise(id: UUID(), name: "Press", restSeconds: 90, sets: [row(1)])
        let workout = snapshot([press])
        let data = WatchData.empty.replacingWorkout(workout).replacingEntries([])
        XCTAssertEqual(data.workout, workout)
    }
}

@MainActor
final class WatchWorkoutSnapshotBuilderTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func test_mapsSessionInDisplayOrderWithResolvedRest() throws {
        let row = WorkoutExerciseEntry(exerciseID: "row", index: 1, sets: [SetEntry(index: 1, weightKg: 50, reps: 10)], restSeconds: 120)
        let press = WorkoutExerciseEntry(exerciseID: "press", index: 0, sets: [
            SetEntry(index: 2, weightKg: 60, reps: 8),
            SetEntry(index: 1, weightKg: 40, reps: 12, isWarmup: true),
            SetEntry(index: 3, weightKg: 0, reps: 0, measurement: .init(kind: .timed, seconds: 60)),
        ])
        let session = WorkoutSession(name: "Push", startedAt: start, exercises: [row, press])

        let snapshot = try XCTUnwrap(WatchWorkoutSnapshotBuilder.snapshot(of: session, defaultRestSeconds: 90))

        XCTAssertEqual(snapshot.exercises.map(\.id), [press.id, row.id])
        XCTAssertEqual(snapshot.exercises.map(\.restSeconds), [90, 120])
        XCTAssertEqual(snapshot.exercises[0].sets.map(\.index), [1, 2, 3])
        XCTAssertEqual(snapshot.exercises[0].sets.map(\.logsReps), [true, true, false])
        XCTAssertEqual(snapshot.totalSets, 3)
    }

    func test_pausedSessionSendsFrozenClockAndNoRest() throws {
        let press = WorkoutExerciseEntry(exerciseID: "press", index: 0, sets: [
            SetEntry(index: 1, weightKg: 60, reps: 8, completed: true),
            SetEntry(index: 2, weightKg: 60, reps: 8),
        ])
        var session = WorkoutSession(startedAt: start, exercises: [press], focus: WorkoutFocusState(
            selectedEntryID: press.id,
            rest: WorkoutRestContext(
                sourceEntryID: press.id, sourceSetID: press.sets[0].id,
                targetEntryID: press.id, targetSetID: press.sets[1].id,
                endsAt: start.addingTimeInterval(400), totalSeconds: 90
            )
        ))
        session.focus?.pause(at: start.addingTimeInterval(330))

        let snapshot = try XCTUnwrap(WatchWorkoutSnapshotBuilder.snapshot(of: session, defaultRestSeconds: 90))

        XCTAssertTrue(snapshot.isPaused)
        XCTAssertEqual(snapshot.pausedElapsedSeconds, 330)
        XCTAssertNil(snapshot.rest)
    }

    func test_finishedOrMissingSession_sendsNoWorkout() {
        XCTAssertNil(WatchWorkoutSnapshotBuilder.snapshot(of: nil, defaultRestSeconds: 90))
        let finished = WorkoutSession(startedAt: start, finishedAt: start.addingTimeInterval(60))
        XCTAssertNil(WatchWorkoutSnapshotBuilder.snapshot(of: finished, defaultRestSeconds: 90))
    }
}

@MainActor
final class WatchWorkoutServiceTests: XCTestCase {
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
    private func start() -> WorkoutSession {
        let routine = Routine(name: "Incline press", exercises: [
            RoutineExercise(exerciseID: "Incline_Dumbbell_Press", index: 0, targetSets: 3, targetReps: 10)
        ])
        return service.startWorkout(routine: routine)
    }

    private func request(_ command: WatchWorkoutCommand, session: UUID? = nil, at date: Date = Date()) throws -> WatchWorkoutRequest {
        WatchWorkoutRequest(sessionId: try session ?? XCTUnwrap(service.activeSession?.id), command: command, issuedAt: date)
    }

    func test_watchCompleteSet_logsTheWristValuesAndRestsFromTheTap() throws {
        let entry = start().exercises[0]
        let tap = Date().addingTimeInterval(-30)

        service.apply(try request(.completeSet(exerciseID: entry.id, setID: entry.sets[0].id, weightKg: 32.5, reps: 9), at: tap))

        let session = try XCTUnwrap(service.activeSession)
        let set = session.exercises[0].sets[0]
        XCTAssertTrue(set.completed)
        XCTAssertEqual(set.weightKg, 32.5)
        XCTAssertEqual(set.reps, 9)
        XCTAssertEqual(set.completedAt, tap)
        XCTAssertEqual(session.focus?.rest?.endsAt, tap.addingTimeInterval(90))
    }

    func test_watchRequestForAnotherWorkout_isDropped() throws {
        let entry = start().exercises[0]
        service.apply(try request(.completeSet(exerciseID: entry.id, setID: entry.sets[0].id, weightKg: 30, reps: 10), session: UUID()))
        XCTAssertEqual(service.activeSession?.completedSetCount, 0)
    }

    func test_repeatedCompleteSet_changesNothingTheSecondTime() throws {
        let entry = start().exercises[0]
        let complete = try request(.completeSet(exerciseID: entry.id, setID: entry.sets[0].id, weightKg: 30, reps: 10))
        service.apply(complete)
        let rest = service.activeSession?.focus?.rest
        service.apply(complete)
        XCTAssertEqual(service.activeSession?.completedSetCount, 1)
        XCTAssertEqual(service.activeSession?.focus?.rest, rest)
    }

    func test_watchAddSet_keepsTheIDTheWatchChose_soItCanBeLoggedAtOnce() throws {
        let entry = start().exercises[0]
        let id = UUID()
        service.apply(try request(.addSet(exerciseID: entry.id, setID: id)))
        service.apply(try request(.addSet(exerciseID: entry.id, setID: id)))
        XCTAssertEqual(service.activeSession?.exercises[0].sets.filter { $0.id == id }.count, 1)

        service.apply(try request(.completeSet(exerciseID: entry.id, setID: id, weightKg: 30, reps: 10)))
        XCTAssertEqual(service.activeSession?.exercises[0].sets.last?.completed, true)
    }

    func test_watchPause_isAbsoluteSoADuplicateDoesNotResume() throws {
        start()
        let pause = try request(.setPaused(true))
        service.apply(pause)
        service.apply(pause)
        XCTAssertEqual(service.activeSession?.isPaused, true)
        service.apply(try request(.setPaused(false)))
        XCTAssertEqual(service.activeSession?.isPaused, false)
    }
}
