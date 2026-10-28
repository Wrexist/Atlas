import XCTest
@testable import Peptide

/// A workout the Watch runs without the phone must log on the wrist the
/// way the phone would, reach the phone exactly once, and land in history
/// as the same workout.
final class WatchOfflineWorkoutTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_166_000)

    private let bench = WatchLift(exerciseID: "bench-press", name: "Bench Press", restSeconds: 90, sets: 3, weightKg: 80, reps: 5)
    private let row = WatchLift(exerciseID: "barbell-row", name: "Barbell Row", restSeconds: 60, sets: 2, weightKg: 70, reps: 8)

    private var routine: WatchRoutine {
        WatchRoutine(id: UUID(), name: "Push", lifts: [bench, row])
    }

    /// Completes the next open set at its seeded values.
    private func completingNext(_ workout: WatchOfflineWorkout, at date: Date) throws -> WatchOfflineWorkout {
        let next = try XCTUnwrap(workout.snapshot.upNext)
        return workout.applying(
            .completeSet(exerciseID: next.exercise.id, setID: next.set.id, weightKg: next.set.weightKg, reps: next.set.reps),
            at: date
        )
    }

    // MARK: - Logging on the wrist

    func test_startFromRoutine_seedsEverySetAtTheLastWeight() {
        let workout = WatchOfflineWorkout(routine: routine, at: now)

        XCTAssertEqual(workout.snapshot.name, "Push")
        XCTAssertEqual(workout.snapshot.exercises.map(\.sets.count), [3, 2])
        XCTAssertEqual(workout.snapshot.exercises.first?.sets.map(\.weightKg), [80, 80, 80])
        XCTAssertEqual(workout.snapshot.exercises.last?.restSeconds, 60)
        XCTAssertEqual(workout.snapshot.upNext?.exercise.name, "Bench Press")
        XCTAssertEqual(Set(workout.exerciseIDs.values), ["bench-press", "barbell-row"])
        XCTAssertFalse(workout.hasLoggedWork)
    }

    func test_completeSet_startsTheRestAndRecordsTheTapOnce() throws {
        let start = WatchOfflineWorkout(routine: routine, at: now)
        let first = try XCTUnwrap(start.snapshot.upNext)
        let tap = now.addingTimeInterval(120)

        let done = start.applying(.completeSet(exerciseID: first.exercise.id, setID: first.set.id, weightKg: 82.5, reps: 4), at: tap)
        let again = done.applying(.completeSet(exerciseID: first.exercise.id, setID: first.set.id, weightKg: 90, reps: 1), at: tap.addingTimeInterval(5))

        XCTAssertEqual(done.completedAt[first.set.id], tap)
        XCTAssertEqual(done.snapshot.rest?.endsAt, tap.addingTimeInterval(90))
        XCTAssertEqual(again, done, "A second tap on a logged set changes nothing")
        XCTAssertEqual(again.snapshot.exercises.first?.sets.first?.weightKg, 82.5)
    }

    func test_quickWorkout_addingALift_makesItTheNextSet() {
        let empty = WatchOfflineWorkout(routine: nil, at: now)
        XCTAssertTrue(empty.snapshot.exercises.isEmpty)
        XCTAssertNil(empty.routineID)

        let added = empty.adding(row)

        XCTAssertEqual(added.snapshot.upNext?.exercise.name, "Barbell Row")
        XCTAssertEqual(added.snapshot.upNext?.set.reps, 8)
        XCTAssertEqual(added.exerciseIDs[added.snapshot.exercises[0].id], "barbell-row")
    }

    func test_finishWhilePaused_countsThePauseAndEndsTheRest() throws {
        var workout = try completingNext(WatchOfflineWorkout(routine: routine, at: now), at: now.addingTimeInterval(60))
        workout = workout.applying(.setPaused(true), at: now.addingTimeInterval(100))

        let finished = workout.finished(at: now.addingTimeInterval(400))

        XCTAssertEqual(finished.finishedAt, now.addingTimeInterval(400))
        XCTAssertEqual(finished.pausedSeconds, 300, accuracy: 0.001)
        XCTAssertNil(finished.snapshot.rest)
        XCTAssertFalse(finished.snapshot.isPaused)
    }

    func test_finishedWorkout_takesNoMoreTaps() throws {
        let finished = try completingNext(WatchOfflineWorkout(routine: routine, at: now), at: now).finished(at: now.addingTimeInterval(60))

        XCTAssertEqual(try completingNext(finished, at: now.addingTimeInterval(90)), finished)
        XCTAssertEqual(finished.adding(bench), finished)
        XCTAssertEqual(finished.finished(at: now.addingTimeInterval(999)).finishedAt, now.addingTimeInterval(60))
    }

    // MARK: - Outbox and receipts

    func test_enqueue_keepsOnlyFinishedWorkoutsWithWork_once() throws {
        let running = try completingNext(WatchOfflineWorkout(routine: routine, at: now), at: now)
        let finished = running.finished(at: now.addingTimeInterval(60))
        let emptyFinished = WatchOfflineWorkout(routine: routine, at: now).finished(at: now)

        var outbox = WatchOfflineSyncEngine.enqueue(running, into: [])
        XCTAssertTrue(outbox.isEmpty, "An unfinished workout is not sent")
        outbox = WatchOfflineSyncEngine.enqueue(emptyFinished, into: outbox)
        XCTAssertTrue(outbox.isEmpty, "A workout without a logged set is not sent")
        outbox = WatchOfflineSyncEngine.enqueue(finished, into: outbox)
        outbox = WatchOfflineSyncEngine.enqueue(finished, into: outbox)
        XCTAssertEqual(outbox.map(\.id), [finished.id])
    }

    func test_outbox_dropsReceiptedWorkouts_andSkipsCopiesInFlight() throws {
        let a = try completingNext(WatchOfflineWorkout(routine: routine, at: now), at: now).finished(at: now)
        let b = try completingNext(WatchOfflineWorkout(routine: routine, at: now), at: now).finished(at: now)
        let outbox = [a, b]

        XCTAssertEqual(WatchOfflineSyncEngine.pruned(outbox, syncedIDs: [a.id, UUID()]).map(\.id), [b.id])
        XCTAssertEqual(WatchOfflineSyncEngine.toSend(outbox, inFlight: [b.id]).map(\.id), [a.id])
    }

    func test_recordingReceipt_isIdempotentAndCapped() {
        let first = UUID()
        var receipts = WatchOfflineSyncEngine.recordingReceipt(first, in: [])
        receipts = WatchOfflineSyncEngine.recordingReceipt(first, in: receipts)
        XCTAssertEqual(receipts, [first])

        for _ in 0..<WatchOfflineSyncEngine.receiptLimit {
            receipts = WatchOfflineSyncEngine.recordingReceipt(UUID(), in: receipts)
        }
        XCTAssertEqual(receipts.count, WatchOfflineSyncEngine.receiptLimit)
        XCTAssertFalse(receipts.contains(first), "The oldest receipt falls off first")
    }

    func test_message_roundTripsTheWorkoutAndNamesItsId() throws {
        let workout = try completingNext(WatchOfflineWorkout(routine: routine, at: now), at: now.addingTimeInterval(30))
            .finished(at: now.addingTimeInterval(600))

        let message = try XCTUnwrap(WatchOfflineSyncEngine.message(for: workout))

        XCTAssertEqual(WatchOfflineSyncEngine.workoutID(in: message), workout.id)
        XCTAssertEqual(WatchOfflineSyncEngine.workout(in: message), workout)
        XCTAssertNil(WatchOfflineSyncEngine.workoutID(in: ["action": WatchMessage.logWater]))
    }

    // MARK: - Filing on the phone

    func test_import_keepsIdsSetsAndTimes() throws {
        let start = WatchOfflineWorkout(routine: routine, at: now)
        let tap = now.addingTimeInterval(45)
        let workout = try completingNext(start, at: tap).finished(at: now.addingTimeInterval(1_800))

        let session = try XCTUnwrap(WatchWorkoutImportEngine.session(from: workout))

        XCTAssertEqual(session.id, workout.id)
        XCTAssertEqual(session.name, "Push")
        XCTAssertEqual(session.routineID, workout.routineID)
        XCTAssertEqual(session.startedAt, now)
        XCTAssertEqual(session.finishedAt, now.addingTimeInterval(1_800))
        XCTAssertEqual(session.exercises.map(\.exerciseID), ["bench-press", "barbell-row"])
        XCTAssertEqual(session.exercises.map(\.index), [0, 1])
        XCTAssertEqual(session.exercises.map(\.id), workout.snapshot.exercises.map(\.id))
        let firstSet = try XCTUnwrap(session.exercises.first?.sets.first)
        XCTAssertTrue(firstSet.completed)
        XCTAssertEqual(firstSet.completedAt, tap)
        XCTAssertNil(session.exercises.first?.sets.last?.completedAt)
        XCTAssertEqual(session.completedSetCount, 1)
        XCTAssertEqual(session.totalVolumeKg, 400)
        XCTAssertEqual(session.elapsedSeconds(), 1_800)
    }

    func test_import_quickWorkoutIsUnnamed_andSubtractsPausedTime() throws {
        var workout = WatchOfflineWorkout(routine: nil, at: now).adding(bench)
        workout = try completingNext(workout, at: now.addingTimeInterval(30))
        workout = workout.applying(.setPaused(true), at: now.addingTimeInterval(100))
        workout = workout.applying(.setPaused(false), at: now.addingTimeInterval(400))

        let session = try XCTUnwrap(WatchWorkoutImportEngine.session(from: workout.finished(at: now.addingTimeInterval(1_000))))

        XCTAssertNil(session.name)
        XCTAssertNil(session.routineID)
        XCTAssertEqual(session.elapsedSeconds(), 700)
    }

    func test_import_withoutAWorkingSetOrFinish_filesNothing() throws {
        let unfinished = try completingNext(WatchOfflineWorkout(routine: routine, at: now), at: now)
        let empty = WatchOfflineWorkout(routine: routine, at: now).finished(at: now.addingTimeInterval(60))

        XCTAssertNil(WatchWorkoutImportEngine.session(from: unfinished))
        XCTAssertNil(WatchWorkoutImportEngine.session(from: empty))
    }

    func test_import_keepsBodyweightAndPerPairMeasurements() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Stockholm"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 10, day: 11, hour: 7)))
        let dips = WatchLift(exerciseID: "dips", name: "Dips", restSeconds: 90, sets: 1, weightKg: 10, reps: 8,
                             measurement: WatchSetMeasurement(kind: "bodyweight", load: "recorded"))
        let curls = WatchLift(exerciseID: "dumbbell-curl", name: "Dumbbell Curl", restSeconds: 60, sets: 1, weightKg: 12, reps: 10,
                              measurement: WatchSetMeasurement(kind: "repetitions", load: "eachPair"))
        var workout = WatchOfflineWorkout(routine: WatchRoutine(id: UUID(), name: "Arms", lifts: [dips, curls]), at: start)
        workout = try completingNext(workout, at: start.addingTimeInterval(60))
        workout = try completingNext(workout, at: start.addingTimeInterval(240))
        let message = try XCTUnwrap(WatchOfflineSyncEngine.message(for: workout.finished(at: start.addingTimeInterval(600))))
        let delivered = try XCTUnwrap(WatchOfflineSyncEngine.workout(in: message))

        let session = try XCTUnwrap(WatchWorkoutImportEngine.session(from: delivered))
        let dipSet = try XCTUnwrap(session.exercises.first?.sets.first)
        let curlSet = try XCTUnwrap(session.exercises.last?.sets.first)

        XCTAssertEqual(dipSet.measurement, SetEntry.Measurement(kind: .bodyweight, load: .recorded))
        XCTAssertNil(dipSet.estimatedOneRepMaxKg, "A bodyweight set is no ordinary-rep 1RM")
        XCTAssertEqual(curlSet.measurement, SetEntry.Measurement(kind: .repetitions, load: .eachPair))
        XCTAssertEqual(curlSet.volumeKg, 240, "A per-pair load counts both hands")
        XCTAssertEqual(session.totalVolumeKg, 320)
    }

    func test_addSet_carriesTheMeasurementOfThePreviousSet() throws {
        let perSide = WatchLift(exerciseID: "lunge", name: "Lunge", restSeconds: 60, sets: 1, weightKg: 20, reps: 10,
                                measurement: WatchSetMeasurement(kind: "repetitions", load: "perSide"))
        let workout = WatchOfflineWorkout(routine: nil, at: now).adding(perSide)
        let exerciseID = try XCTUnwrap(workout.snapshot.exercises.first?.id)

        let added = workout.applying(.addSet(exerciseID: exerciseID, setID: UUID()), at: now)

        XCTAssertEqual(added.snapshot.exercises.first?.sets.map(\.measurement), [perSide.measurement, perSide.measurement])
    }

    // MARK: - Wire format

    func test_liftWithoutMeasurement_decodesFromAnOlderPayload() throws {
        let older = Data(#"{"exerciseID":"squat","name":"Squat","restSeconds":120,"sets":3,"weightKg":100,"reps":5}"#.utf8)

        let lift = try JSONDecoder().decode(WatchLift.self, from: older)

        XCTAssertEqual(lift.weightKg, 100)
        XCTAssertNil(lift.measurement)
    }

    func test_watchData_carriesCatalogAndReceipts_andOlderPayloadsDecodeWithout() throws {
        let catalog = WatchTrainingCatalog(routines: [routine], recentLifts: [row])
        let receipt = UUID()
        let plain = WatchData(todayEntries: [], completedToday: 0, totalToday: 0, lastUpdated: now)
        let data = plain.replacingOfflineSync(catalog: catalog, syncedWorkoutIDs: [receipt])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(WatchData.self, from: encoder.encode(data))
        let older = try decoder.decode(WatchData.self, from: encoder.encode(plain))

        XCTAssertEqual(decoded.trainingCatalog, catalog)
        XCTAssertEqual(decoded.syncedWorkoutIDs, [receipt])
        XCTAssertNil(older.trainingCatalog)
        XCTAssertNil(older.syncedWorkoutIDs)
        XCTAssertNil(plain.replacingOfflineSync(catalog: nil, syncedWorkoutIDs: []).syncedWorkoutIDs)
    }

    func test_catalogAllLifts_listsEachExerciseOnce_recentFirst() {
        let catalog = WatchTrainingCatalog(routines: [routine], recentLifts: [row])
        XCTAssertEqual(catalog.allLifts.map(\.exerciseID), ["barbell-row", "bench-press"])
        XCTAssertFalse(catalog.isEmpty)
        XCTAssertTrue(WatchTrainingCatalog(routines: [], recentLifts: []).isEmpty)
    }
}

/// The phone's side of the catalog: routines seeded as a phone start
/// would seed them, and recent lifts from finished history.
@MainActor
final class WatchTrainingCatalogBuilderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_166_000)

    private func completed(_ weightKg: Double, _ reps: Int) -> SetEntry {
        SetEntry(index: 1, weightKg: weightKg, reps: reps, completed: true)
    }

    func test_catalog_seedsRoutinesFromLastSets_andListsRecentLiftsOnce() {
        let routine = Routine(name: "Legs", exercises: [
            RoutineExercise(exerciseID: "squat", index: 0, targetSets: 4, targetReps: 6, restSeconds: 180),
            RoutineExercise(exerciseID: "lunge", index: 1, targetSets: 2, targetReps: 10),
        ])
        let newer = WorkoutSession(startedAt: now, finishedAt: now.addingTimeInterval(3_600), exercises: [
            WorkoutExerciseEntry(exerciseID: "squat", index: 0, sets: [completed(100, 5), completed(100, 5)]),
        ])
        let older = WorkoutSession(startedAt: now.addingTimeInterval(-86_400), finishedAt: now.addingTimeInterval(-82_800), exercises: [
            WorkoutExerciseEntry(exerciseID: "deadlift", index: 0, sets: [completed(140, 3)]),
            WorkoutExerciseEntry(exerciseID: "squat", index: 1, sets: [completed(95, 5)]),
        ])
        let running = WorkoutSession(startedAt: now.addingTimeInterval(4_000), exercises: [
            WorkoutExerciseEntry(exerciseID: "curl", index: 0, sets: [completed(15, 12)]),
        ])
        let last: [String: SetEntry] = ["squat": completed(100, 5), "deadlift": completed(140, 3)]

        let catalog = WatchWorkoutSnapshotBuilder.catalog(
            routines: [routine],
            recent: [running, newer, older],
            defaultRestSeconds: 120,
            lastSet: { last[$0] },
            name: { $0.capitalized }
        )

        let lifts = catalog.routines.first?.lifts ?? []
        XCTAssertEqual(lifts.map(\.exerciseID), ["squat", "lunge"])
        XCTAssertEqual(lifts.map(\.sets), [4, 2])
        XCTAssertEqual(lifts.map(\.reps), [6, 10], "Reps come from the routine, as on the phone")
        XCTAssertEqual(lifts.map(\.weightKg), [100, 0], "Load comes from the last set, or zero without history")
        XCTAssertEqual(lifts.map(\.restSeconds), [180, 120])
        XCTAssertEqual(lifts.first?.name, "Squat")

        XCTAssertEqual(catalog.recentLifts.map(\.exerciseID), ["squat", "deadlift"],
                       "Newest first, once each, finished workouts only")
        XCTAssertEqual(catalog.recentLifts.first?.sets, 2)
        XCTAssertEqual(catalog.recentLifts.last?.weightKg, 140)
    }

    func test_catalog_carriesTheLastSetsMeasurement() {
        let bodyweight = SetEntry.Measurement(kind: .bodyweight, load: .recorded)
        let routine = Routine(name: "Upper", exercises: [RoutineExercise(exerciseID: "pull-up", index: 0, targetSets: 3, targetReps: 8)])
        let session = WorkoutSession(startedAt: now, finishedAt: now.addingTimeInterval(3_600), exercises: [
            WorkoutExerciseEntry(exerciseID: "pull-up", index: 0, sets: [
                SetEntry(index: 1, weightKg: 5, reps: 8, completed: true, measurement: bodyweight),
            ]),
        ])
        let last = SetEntry(index: 1, weightKg: 5, reps: 8, completed: true, measurement: bodyweight)

        let catalog = WatchWorkoutSnapshotBuilder.catalog(
            routines: [routine], recent: [session], defaultRestSeconds: 90, lastSet: { _ in last }, name: { $0 }
        )

        let wire = WatchSetMeasurement(kind: "bodyweight", load: "recorded")
        XCTAssertEqual(catalog.routines.first?.lifts.first?.measurement, wire)
        XCTAssertEqual(catalog.recentLifts.first?.measurement, wire)
    }

    func test_catalog_capsRoutinesForTheApplicationContext() {
        let routines = (0..<(WatchWorkoutSnapshotBuilder.catalogRoutineLimit + 3)).map {
            Routine(name: "R\($0)", exercises: [RoutineExercise(exerciseID: "squat", index: 0)])
        }

        let catalog = WatchWorkoutSnapshotBuilder.catalog(
            routines: routines, recent: [], defaultRestSeconds: 90, lastSet: { _ in nil }, name: { $0 }
        )

        XCTAssertEqual(catalog.routines.count, WatchWorkoutSnapshotBuilder.catalogRoutineLimit)
        XCTAssertEqual(catalog.routines.first?.name, "R0")
    }
}
