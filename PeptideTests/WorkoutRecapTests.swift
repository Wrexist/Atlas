import XCTest
import SwiftUI
@testable import Peptide

@MainActor
final class WorkoutRecapTests: XCTestCase {
    private func catalog() async -> [String: Exercise] {
        await ExerciseLibrary.shared.load()
        return Dictionary(uniqueKeysWithValues: WorkoutRecapFixture.push().exercises.compactMap { entry in
            ExerciseLibrary.shared.lookup(id: entry.exerciseID).map { (entry.exerciseID, $0) }
        })
    }

    func test_fixtureSharedTotalsAndVerifiedRoles() async throws {
        let catalog = await catalog()
        XCTAssertEqual(catalog.count, 5)
        let session = WorkoutRecapFixture.push()
        let summary = WorkoutRecapEngine.derive(session, catalog: catalog)
        XCTAssertEqual(summary.entries.count, 5)
        XCTAssertEqual(summary.workingSetCount, 15)
        XCTAssertEqual(summary.duration, .tracked(2520))
        let kg = try XCTUnwrap(summary.volumeKg)
        XCTAssertEqual(MeasurementUnit.imperial.weightForDisplay(kg), 6720, accuracy: 0.001)
        XCTAssertEqual(summary.entries.compactMap(\.volumeKg).reduce(0, +), kg, accuracy: 0.00001)
        XCTAssertEqual(summary.excludedVolumeSets, 0)
        XCTAssertEqual(summary.missingMappings, 0)
        XCTAssertFalse(summary.hasLegacyLoad)
        XCTAssertFalse(summary.muscles.contains { $0.name == "biceps" })
        let triceps = try XCTUnwrap(summary.muscles.first { $0.name == "triceps" })
        XCTAssertEqual(triceps.role, .primary)
        XCTAssertEqual(triceps.setCount, 12)
        XCTAssertEqual(triceps.contributions.filter { $0.role == .primary }.map(\.name), ["Triceps Pushdown"])
        XCTAssertEqual(summary.muscles.first { $0.name == "shoulders" }?.role, .primary)
        let week = WorkoutRecapEngine.week(sessions: [session, session], catalog: catalog,
                                           now: session.finishedAt!.addingTimeInterval(1))
        XCTAssertEqual(week.count, 1)
        XCTAssertEqual(try XCTUnwrap(week.volumeKg), kg, accuracy: 0.00001)
    }

    func test_durationBranchesAndPauses() {
        var s = WorkoutRecapFixture.push()
        s.finishedAt = s.startedAt.addingTimeInterval(59)
        XCTAssertEqual(WorkoutRecapEngine.duration(of: s).label, "<1 min")
        s.focus?.timing = .notTracked
        XCTAssertEqual(WorkoutRecapEngine.duration(of: s), .notTracked)
        s.focus?.timing = .tracked
        s.finishedAt = nil
        XCTAssertEqual(WorkoutRecapEngine.duration(of: s), .unavailable)
        s.finishedAt = s.startedAt.addingTimeInterval(-1)
        XCTAssertEqual(WorkoutRecapEngine.duration(of: s), .unavailable)
        s.finishedAt = s.startedAt.addingTimeInterval(120)
        s.focus?.pausedSeconds = 60
        XCTAssertEqual(WorkoutRecapEngine.duration(of: s), .tracked(60))
        s.focus?.pausedSeconds = 121
        XCTAssertEqual(WorkoutRecapEngine.duration(of: s), .unavailable)
    }

    func test_loadConventionsAndUnsupportedMeasurements() {
        var set = SetEntry(index: 1, weightKg: 20, reps: 10, completed: true)
        XCTAssertEqual(set.externalVolumeKg, 200)
        set.measurement = .init(kind: .repetitions, load: .eachPair)
        XCTAssertEqual(set.externalVolumeKg, 400)
        set.measurement?.load = .perSide
        XCTAssertEqual(set.externalVolumeKg, 200)
        set.measurement?.kind = .bodyweight
        XCTAssertEqual(set.externalVolumeKg, 200, "Only actual added load is counted")
        set.weightKg = 0
        XCTAssertNil(set.externalVolumeKg)
        set.weightKg = 20
        for kind in [SetEntry.Measurement.Kind.timed, .distance, .assisted] {
            set.measurement?.kind = kind
            XCTAssertNil(set.externalVolumeKg)
        }
        set.measurement = nil
        set.isWarmup = true
        XCTAssertNil(set.externalVolumeKg)
        set.isWarmup = false
        set.completed = false
        XCTAssertNil(set.externalVolumeKg)
        set.completed = true
        set.weightKg = .infinity
        XCTAssertNil(set.externalVolumeKg)
    }

    func test_missingMappingOneSetAndDuplicateIDs() {
        let set = SetEntry(index: 1, weightKg: 0, reps: 10, completed: true)
        let entry = WorkoutExerciseEntry(exerciseID: "definitely_not_real", index: 0, sets: [set, set])
        let s = WorkoutSession(finishedAt: Date(), exercises: [entry, entry])
        let summary = WorkoutRecapEngine.derive(s, catalog: [:])
        XCTAssertEqual(summary.workingSetCount, 1)
        XCTAssertEqual(summary.entries.count, 1)
        XCTAssertEqual(summary.missingMappings, 1)
        XCTAssertNil(summary.volumeKg)
        XCTAssertTrue(summary.muscles.isEmpty)
    }

    func test_warmupOnlyUnfinishedAndTimedHaveNoInventedVolume() {
        var session = WorkoutRecapFixture.push()
        for e in session.exercises.indices {
            for s in session.exercises[e].sets.indices { session.exercises[e].sets[s].isWarmup = true }
        }
        var summary = WorkoutRecapEngine.derive(session, catalog: [:])
        XCTAssertEqual(summary.workingSetCount, 0)
        XCTAssertTrue(summary.entries.isEmpty)
        XCTAssertNil(summary.volumeKg)
        let timed = SetEntry(index: 1, weightKg: 100, reps: 99, completed: true,
                             measurement: .init(kind: .timed, seconds: 45))
        session.exercises = [WorkoutExerciseEntry(exerciseID: "definitely_not_real", index: 0, sets: [timed])]
        summary = WorkoutRecapEngine.derive(session, catalog: [:])
        XCTAssertEqual(summary.workingSetCount, 1)
        XCTAssertNil(summary.volumeKg)
        XCTAssertEqual(summary.excludedVolumeSets, 1)
        XCTAssertFalse(RecapFormat.set(timed, unit: .imperial).contains("reps"))
    }

    func test_weekLocalMidnightAndExclusiveEndBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Stockholm"))
        calendar.firstWeekday = 2
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 28)))
        let now = monday.addingTimeInterval(6 * 86400 + 3600)
        let previous = WorkoutRecapFixture.push(finishedAt: monday.addingTimeInterval(-1))
        var first = WorkoutRecapFixture.push(finishedAt: monday.addingTimeInterval(3600))
        first.startedAt = monday
        var second = WorkoutRecapFixture.push(finishedAt: monday.addingTimeInterval(7200))
        second.startedAt = monday.addingTimeInterval(3600)
        var next = WorkoutRecapFixture.push(finishedAt: monday.addingTimeInterval(8 * 86400))
        next.startedAt = monday.addingTimeInterval(7 * 86400)
        let week = WorkoutRecapEngine.week(sessions: [previous, first, second, next, first], catalog: [:], now: now, calendar: calendar)
        XCTAssertEqual(week.count, 2)
        XCTAssertEqual(week.days.map(\.count), [2, 0, 0, 0, 0, 0, 0])
    }

    func test_legacyJSONAndRoundTripKeepIdentityAndSemantics() throws {
        let original = SetEntry(index: 1, weightKg: 25, reps: 10, completed: true)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(SetEntry.self, from: data)
        XCTAssertEqual(restored.id, original.id)
        XCTAssertNil(restored.measurement)
        XCTAssertEqual(restored.volumeKg, 250)
        let fixture = WorkoutRecapFixture.push()
        let roundTrip = try JSONDecoder().decode(WorkoutSession.self, from: JSONEncoder().encode(fixture))
        XCTAssertEqual(roundTrip, fixture)
    }

    func test_snapshotProductionStatesAndShare() async throws {
        let summary = WorkoutRecapEngine.derive(WorkoutRecapFixture.push(), catalog: await catalog())
        attach(WorkoutSaveStatusView(saving: true, error: nil, retry: {}, returnToWorkout: {}), name: "04-saving")
        attach(WorkoutSaveStatusView(saving: false, error: "The workout could not be written to device storage. Try again.", retry: {}, returnToWorkout: {}), name: "05-save-error")
        for (name, duration) in [("short", WorkoutFocusState.Timing.tracked), ("manual", .notTracked), ("missing", .unavailable)] {
            var session = summary.session
            session.finishedAt = session.startedAt.addingTimeInterval(30)
            session.focus?.timing = duration
            let alternate = WorkoutRecapEngine.derive(session, catalog: [:])
            attach(VStack { RecapMetrics(summary: alternate, unit: .imperial); RecapCalculationNotes(summary: alternate) }, name: "06-\(name)")
        }
        attach(WorkoutShareCard(summary: summary, unit: .imperial, includeName: true, includeDate: true), name: "08-share")
    }

    private func attach<V: View>(_ view: V, name: String) {
        let renderer = ImageRenderer(content: view.padding(20).frame(width: 375)
            .background(AppColor.recapBackground).environment(\.colorScheme, .dark))
        renderer.scale = 3
        guard let image = renderer.uiImage else { XCTFail("Image rendering failed: \(name)"); return }
        let attachment = XCTAttachment(image: image)
        attachment.name = "completion-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
final class WorkoutCompletionPersistenceTests: XCTestCase {
    func test_diskReopenRecoversDraftThenFinishedIdentity() throws {
        let repo = SwiftDataRepository.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("recap.store")
        defer { repo.configureForTesting(); try? FileManager.default.removeItem(at: directory) }
        try repo.configurePersistentStoreForTesting(at: url)
        let finished = WorkoutRecapFixture.push()
        var draft = finished
        draft.finishedAt = nil
        try repo.saveWorkoutDurably(draft)
        try repo.configurePersistentStoreForTesting(at: url)
        XCTAssertEqual(repo.loadActiveWorkoutSession(), draft)
        repo.forceCommitFailureForTesting = true
        XCTAssertThrowsError(try repo.saveWorkoutDurably(finished))
        try repo.configurePersistentStoreForTesting(at: url)
        XCTAssertEqual(repo.loadActiveWorkoutSession(), draft)
        try repo.saveWorkoutDurably(finished)
        try repo.configurePersistentStoreForTesting(at: url)
        XCTAssertNil(repo.loadActiveWorkoutSession())
        XCTAssertEqual(repo.loadWorkoutSession(id: finished.id), finished)
        try repo.saveWorkoutDurably(finished)
        XCTAssertEqual(repo.loadAllWorkoutSessions().count, 1)
    }

    func test_failureRetainsActiveRetryAndEditAreIdempotent() throws {
        let repo = SwiftDataRepository.shared
        repo.configureForTesting()
        let service = WorkoutSessionService.shared
        service.discardWorkout()
        defer { repo.forceCommitFailureForTesting = false; service.discardWorkout(); repo.deleteAll() }
        let started = service.startWorkout(routine: Routine(name: "Test", exercises: [
            RoutineExercise(exerciseID: "Incline_Dumbbell_Press", index: 0, targetSets: 1, targetReps: 10)
        ]))
        let entry = try XCTUnwrap(service.activeSession?.exercises.first)
        var set = try XCTUnwrap(entry.sets.first)
        set.completed = true
        set.weightKg = 25
        service.updateSet(set, inExerciseEntryID: entry.id)
        repo.forceCommitFailureForTesting = true
        XCTAssertNil(service.finishWorkout())
        XCTAssertNotNil(service.lastFinishError)
        XCTAssertEqual(service.activeSession?.id, started.id)
        XCTAssertNil(repo.loadWorkoutSession(id: started.id)?.finishedAt)
        repo.forceCommitFailureForTesting = false
        let finished = try XCTUnwrap(service.finishWorkout()?.session)
        XCTAssertNil(service.activeSession)
        XCTAssertNil(service.finishWorkout())
        try repo.saveWorkoutDurably(finished)
        XCTAssertEqual(repo.loadAllWorkoutSessions().count, 1)
        var edited = finished
        edited.exercises[0].sets[0].reps = 8
        let store = WorkoutRecapStore(session: finished)
        try store.saveEdits(edited)
        XCTAssertEqual(repo.loadAllWorkoutSessions().count, 1)
        XCTAssertEqual(repo.loadWorkoutSession(id: started.id)?.exercises[0].sets[0].reps, 8)
        repo.forceCommitFailureForTesting = true
        edited.exercises[0].sets[0].reps = 99
        XCTAssertThrowsError(try store.saveEdits(edited))
        XCTAssertEqual(repo.loadWorkoutSession(id: started.id)?.exercises[0].sets[0].reps, 8)
    }
}
