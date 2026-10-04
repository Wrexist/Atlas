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
        let end = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12)))
        let session = WorkoutRecapFixture.push(finishedAt: end)
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

    func test_repeatPreservesExplicitPairConventionAndRejectsTimedRepSeed() {
        let routine = Routine(name: "Repeat", exercises: [
            RoutineExercise(exerciseID: "Incline_Dumbbell_Press", index: 0, targetSets: 1, targetReps: 10)
        ])
        var prior = SetEntry(index: 1, weightKg: 25, reps: 10, completed: true,
                             measurement: .init(kind: .repetitions, load: .eachPair))
        var repeated = RoutineSeedEngine.sessionExercises(for: routine) { _ in prior }
        XCTAssertEqual(repeated[0].sets[0].measurement?.load, .eachPair)
        XCTAssertEqual(repeated[0].sets[0].weightKg, 25)
        prior.measurement?.kind = .timed
        repeated = RoutineSeedEngine.sessionExercises(for: routine) { _ in prior }
        XCTAssertNil(repeated[0].sets[0].measurement)
        XCTAssertEqual(repeated[0].sets[0].weightKg, 0)
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

    func test_weekAcrossDaylightSavingUsesSevenLocalDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Stockholm"))
        calendar.firstWeekday = 2
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12)))
        let week = WorkoutRecapEngine.week(sessions: [WorkoutRecapFixture.push(finishedAt: end)],
                                           catalog: [:], now: end, calendar: calendar)
        XCTAssertEqual(week.days.map { calendar.component(.day, from: $0.date) }, [19, 20, 21, 22, 23, 24, 25])
        XCTAssertEqual(week.days.map(\.count), [0, 0, 0, 0, 0, 0, 1])
        XCTAssertEqual(calendar.dateInterval(of: .weekOfYear, for: end)?.duration, 169 * 3600)
    }

    func test_editorValidatesChangedMeasurementAndPreservesManualHistory() throws {
        let original = WorkoutRecapFixture.push()
        var draft = original
        draft.exercises[0].sets[0].measurement = .init(kind: .timed)
        XCTAssertNotNil(WorkoutEditValidation.issue(in: draft, original: original))
        XCTAssertThrowsError(try WorkoutEditValidation.validate(draft, original: original))
        draft.exercises[0].sets[0].measurement?.seconds = 30
        XCTAssertNil(WorkoutEditValidation.issue(in: draft, original: original))
        draft.exercises[0].sets[0].measurement = .init(kind: .distance, meters: 0)
        XCTAssertNotNil(WorkoutEditValidation.issue(in: draft, original: original))
        draft.exercises[0].sets[0].measurement?.meters = 100
        XCTAssertNil(WorkoutEditValidation.issue(in: draft, original: original))
        let manual = WorkoutSession(name: "Manual workout", finishedAt: Date())
        var editedManual = manual
        editedManual.name = "Corrected name"
        XCTAssertNil(WorkoutEditValidation.issue(in: editedManual, original: manual))
        for e in draft.exercises.indices {
            for s in draft.exercises[e].sets.indices { draft.exercises[e].sets[s].completed = false }
        }
        XCTAssertNotNil(WorkoutEditValidation.issue(in: draft, original: original))
    }

    func test_editorNumberParsingRejectsBlankPartialAndAmbiguousInput() {
        let english = Locale(identifier: "en_US")
        let swedish = Locale(identifier: "sv_SE")
        XCTAssertEqual(WorkoutEditValidation.number("22.5", locale: english), 22.5)
        XCTAssertEqual(WorkoutEditValidation.number("22,5", locale: swedish), 22.5)
        XCTAssertNil(WorkoutEditValidation.number("1.234", locale: Locale(identifier: "de_DE")))
        XCTAssertEqual(WorkoutEditValidation.number("١٢.٥", locale: english), 12.5)
        for text in ["", " ", "-", ".", "12lb", "1,234.5", "1..2", "nan", "inf"] {
            XCTAssertNil(WorkoutEditValidation.number(text, locale: english), text)
        }
    }

    func test_manualHistoryCountsWorkoutWithoutInventingSetTotals() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12)))
        let manual = WorkoutSession(name: "Manual workout", startedAt: date, finishedAt: date,
                                    focus: WorkoutFocusState(timing: .notTracked))
        let summary = WorkoutRecapEngine.derive(manual, catalog: [:])
        XCTAssertEqual(summary.duration, .notTracked)
        XCTAssertEqual(summary.workingSetLabel, "Not logged")
        XCTAssertNil(summary.volumeKg)
        XCTAssertTrue(summary.qualifiesForWeek)
        XCTAssertEqual(WorkoutRecapEngine.week(sessions: [manual], catalog: [:], now: date, calendar: calendar).count, 1)
        var unfinished = manual
        unfinished.finishedAt = nil
        XCTAssertFalse(WorkoutRecapEngine.derive(unfinished, catalog: [:]).qualifiesForWeek)
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
        for width in [CGFloat(320), 375, 393, 430] {
            attach(RecapMetrics(summary: summary, unit: .imperial), name: "metrics-\(Int(width))", width: width)
            attach(RecapMetrics(summary: summary, unit: .imperial).dynamicTypeSize(.accessibility5),
                   name: "metrics-xxxl-\(Int(width))", width: width)
        }
    }

    private func attach<V: View>(_ view: V, name: String, width: CGFloat = 375) {
        let renderer = ImageRenderer(content: view.padding(20).frame(width: width)
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
    func test_recapRefreshChangesWeekWithoutChangingSavedWorkout() async throws {
        let repo = SwiftDataRepository.shared
        repo.configureForTesting()
        defer { repo.deleteAll() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Stockholm"))
        calendar.firstWeekday = 2
        let sunday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 23, minute: 50)))
        let session = WorkoutRecapFixture.push(finishedAt: sunday)
        try repo.saveWorkoutDurably(session)
        let store = WorkoutRecapStore(session: session)
        await store.load(now: sunday, calendar: calendar)
        XCTAssertEqual(store.week?.count, 1)
        await store.load(now: sunday.addingTimeInterval(20 * 60), calendar: calendar)
        XCTAssertEqual(store.week?.count, 0)
        XCTAssertEqual(store.summary?.workingSetCount, 15)
        XCTAssertEqual(store.session.id, session.id)
        XCTAssertEqual(repo.loadAllWorkoutSessions().count, 1)
    }

    func test_unsupportedMeasurementsCannotAwardRepOrLoadRecords() {
        let repo = SwiftDataRepository.shared
        repo.configureForTesting()
        defer { repo.deleteAll() }
        var session = WorkoutRecapFixture.push()
        for e in session.exercises.indices {
            for s in session.exercises[e].sets.indices {
                session.exercises[e].sets[s].measurement = .init(kind: .assisted)
            }
        }
        XCTAssertTrue(PRDetectionEngine.shared.ingest(session: session).isEmpty)
        XCTAssertTrue(repo.loadPersonalRecords().isEmpty)
    }

    func test_diskReopenRecoversDraftThenFinishedIdentity() throws {
        let repo = SwiftDataRepository.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("recap.store")
        defer { repo.configureForTesting(); try? FileManager.default.removeItem(at: directory) }
        try repo.configurePersistentStoreForTesting(at: url)
        // Stored set timestamps use the established whole-second ISO8601 codec.
        let finished = WorkoutRecapFixture.push(finishedAt: Date(timeIntervalSince1970: 1_790_000_000))
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
        XCTAssertEqual(store.summary?.workingSetCount, 1)
        XCTAssertEqual(store.summary?.volumeKg, 200)
        XCTAssertEqual(store.summary?.entries.first?.volumeKg, 200)
        repo.forceCommitFailureForTesting = true
        edited.exercises[0].sets[0].reps = 99
        XCTAssertThrowsError(try store.saveEdits(edited))
        XCTAssertEqual(repo.loadWorkoutSession(id: started.id)?.exercises[0].sets[0].reps, 8)
    }
}
