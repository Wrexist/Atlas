import XCTest
@testable import Peptide

/// Pins the training half of the widget payload: which sessions count
/// toward "this week", which one is "last workout", and that a payload
/// written by an older build still decodes.
///
/// The mapping is the whole contract between the app and the training
/// widget — there's no schema migration between the two, so a drift
/// here renders wrong numbers on a home screen with nothing to catch it.
final class WidgetSnapshotTrainingTests: XCTestCase {

    /// Wednesday 2025-06-11, 12:00 UTC — mid-week, so a test can step
    /// either side of the week boundary without hitting the day edge.
    private let now = Date(timeIntervalSince1970: 1_749_643_200)

    /// Gregorian, Monday-first, UTC. `Calendar.current` would make the
    /// week boundary depend on the runner's locale.
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        cal.firstWeekday = 2
        return cal
    }()

    private func session(
        name: String? = nil,
        startedAt: Date,
        finishedAt: Date?,
        sets: [(weight: Double, reps: Int, completed: Bool, warmup: Bool)] = []
    ) -> WorkoutSession {
        let entries = sets.enumerated().map { idx, s in
            SetEntry(
                index: idx + 1,
                weightKg: s.weight,
                reps: s.reps,
                completed: s.completed,
                isWarmup: s.warmup
            )
        }
        return WorkoutSession(
            name: name,
            startedAt: startedAt,
            finishedAt: finishedAt,
            exercises: [WorkoutExerciseEntry(exerciseID: "bench-press", index: 0, sets: entries)]
        )
    }

    private func snapshot(_ workouts: [WorkoutSession]) -> WidgetSnapshotBuilder.TrainingSnapshot {
        WidgetSnapshotBuilder.training(from: workouts, now: now, calendar: calendar)
    }

    // MARK: - Week window

    func test_weeklyTotals_countOnlySessionsInsideTheCurrentWeek() {
        let lastWeek = now.addingTimeInterval(-8 * 86_400)
        let result = snapshot([
            session(startedAt: now.addingTimeInterval(-3_600), finishedAt: now,
                    sets: [(100, 5, true, false)]),
            session(startedAt: now.addingTimeInterval(-86_400), finishedAt: now.addingTimeInterval(-82_800),
                    sets: [(50, 10, true, false)]),
            session(startedAt: lastWeek, finishedAt: lastWeek.addingTimeInterval(3_600),
                    sets: [(200, 5, true, false)]),
        ])

        XCTAssertEqual(result.workoutsThisWeek, 2)
        XCTAssertEqual(result.weeklySetCount, 2)
        XCTAssertEqual(result.weeklyVolumeKg, 1_000, accuracy: 0.001) // 500 + 500
    }

    func test_weeklyVolume_excludesWarmupAndUncheckedSets() {
        let result = snapshot([
            session(startedAt: now.addingTimeInterval(-3_600), finishedAt: now, sets: [
                (60, 10, true, true),    // warm-up — no volume, not a working set
                (100, 5, true, false),   // counts: 500
                (100, 5, false, false),  // never checked off
            ]),
        ])

        XCTAssertEqual(result.weeklySetCount, 1)
        XCTAssertEqual(result.weeklyVolumeKg, 500, accuracy: 0.001)
    }

    func test_inProgressSession_isExcludedFromHistory() {
        let result = snapshot([
            session(name: "Right now", startedAt: now.addingTimeInterval(-600), finishedAt: nil,
                    sets: [(100, 5, true, false)]),
        ])

        XCTAssertEqual(result.workoutsThisWeek, 0)
        XCTAssertEqual(result.weeklyVolumeKg, 0)
        XCTAssertNil(result.lastWorkout)
    }

    // MARK: - Last workout

    func test_lastWorkout_isTheMostRecentlyFinished_notTheMostRecentlyStarted() {
        // A long session started first but finished last. Ordering by
        // start date would pick the wrong one.
        let longRun = session(name: "Long", startedAt: now.addingTimeInterval(-10_800),
                              finishedAt: now.addingTimeInterval(-600),
                              sets: [(80, 5, true, false)])
        let quick = session(name: "Quick", startedAt: now.addingTimeInterval(-7_200),
                            finishedAt: now.addingTimeInterval(-5_400),
                            sets: [(80, 5, true, false)])

        XCTAssertEqual(snapshot([quick, longRun]).lastWorkout?.name, "Long")
    }

    func test_lastWorkout_carriesDurationSetsAndVolume() {
        let started = now.addingTimeInterval(-5_400) // 90 min
        let last = snapshot([
            session(name: "Push A", startedAt: started, finishedAt: now,
                    sets: [(100, 5, true, false), (60, 12, true, false)]),
        ]).lastWorkout

        XCTAssertEqual(last?.name, "Push A")
        XCTAssertEqual(last?.finishedAt, now)
        XCTAssertEqual(last?.durationMinutes, 90)
        XCTAssertEqual(last?.setCount, 2)
        XCTAssertEqual(last?.volumeKg ?? 0, 1_220, accuracy: 0.001) // 500 + 720
    }

    func test_lastWorkout_survivesAnUnnamedSession() {
        // The widget falls back to a date label, so "" is the contract —
        // not a nil that would make the field optional twice over.
        let last = snapshot([
            session(startedAt: now.addingTimeInterval(-3_600), finishedAt: now),
        ]).lastWorkout

        XCTAssertEqual(last?.name, "")
    }

    func test_lastWorkout_canPredateTheCurrentWeek() {
        // Someone who hasn't trained since last week still sees their
        // last workout — only the weekly counters reset.
        let old = now.addingTimeInterval(-12 * 86_400)
        let result = snapshot([
            session(name: "Old", startedAt: old, finishedAt: old.addingTimeInterval(3_600)),
        ])

        XCTAssertEqual(result.workoutsThisWeek, 0)
        XCTAssertEqual(result.lastWorkout?.name, "Old")
    }

    func test_noWorkouts_yieldsAnEmptySnapshot() {
        let result = snapshot([])

        XCTAssertNil(result.lastWorkout)
        XCTAssertEqual(result.workoutsThisWeek, 0)
        XCTAssertEqual(result.weeklySetCount, 0)
        XCTAssertEqual(result.weeklyVolumeKg, 0)
    }

    // MARK: - build() wiring

    func test_build_reportsTheActiveSessionStartTime() {
        let active = session(startedAt: now.addingTimeInterval(-900), finishedAt: nil)
        let data = WidgetSnapshotBuilder.build(
            today: [], next: nil,
            workouts: [active],
            activeWorkout: active,
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(data.workoutInProgress)
        XCTAssertEqual(data.activeWorkoutStartedAt, active.startedAt)
    }

    func test_build_treatsAFinishedActiveSessionAsNotInProgress() {
        // WorkoutSessionService clears `activeSession` on finish, but the
        // widget must not claim a workout is running off a stale hand-off.
        let stale = session(startedAt: now.addingTimeInterval(-3_600), finishedAt: now)
        let data = WidgetSnapshotBuilder.build(
            today: [], next: nil,
            activeWorkout: stale,
            now: now,
            calendar: calendar
        )

        XCTAssertFalse(data.workoutInProgress)
        XCTAssertNil(data.activeWorkoutStartedAt)
    }

    func test_build_carriesTheMeasurementUnitThroughToDisplay() {
        let imperial = WidgetSnapshotBuilder.build(
            today: [], next: nil, unit: .imperial, now: now, calendar: calendar
        )
        XCTAssertEqual(imperial.weightSuffix, "lb")
        XCTAssertEqual(imperial.volumeInUserUnit(100), 220.462, accuracy: 0.001)

        let metric = WidgetSnapshotBuilder.build(
            today: [], next: nil, unit: .metric, now: now, calendar: calendar
        )
        XCTAssertEqual(metric.weightSuffix, "kg")
        XCTAssertEqual(metric.volumeInUserUnit(100), 100, accuracy: 0.001)
    }

    // MARK: - Payload back-compat

    func test_payloadWithoutTrainingFields_stillDecodes() {
        // Exactly what a build before this change wrote. The widget
        // extension updates on its own schedule, so it will read these
        // for as long as the user hasn't relaunched the app.
        let legacy = """
        {
          "nextPeptideName": "BPC-157",
          "nextDose": "250 mcg",
          "completedToday": 1,
          "totalToday": 3,
          "lastUpdated": "2025-06-11T12:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try? decoder.decode(WidgetData.self, from: Data(legacy.utf8))

        XCTAssertEqual(decoded?.nextPeptideName, "BPC-157")
        XCTAssertNil(decoded?.lastWorkout)
        XCTAssertEqual(decoded?.workoutsThisWeek, 0)
        XCTAssertEqual(decoded?.weeklySetCount, 0)
        XCTAssertEqual(decoded?.weeklyVolumeKg, 0)
        XCTAssertFalse(decoded?.workoutInProgress ?? true)
        XCTAssertEqual(decoded?.weightSuffix, "kg")
    }

    func test_trainingFields_roundTripThroughTheSharedContainerCodec() {
        let source = WidgetSnapshotBuilder.build(
            today: [], next: nil,
            workouts: [session(name: "Pull B",
                               startedAt: now.addingTimeInterval(-3_600),
                               finishedAt: now,
                               sets: [(100, 5, true, false)])],
            unit: .imperial,
            now: now,
            calendar: calendar
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try? decoder.decode(WidgetData.self, from: encoder.encode(source))

        XCTAssertEqual(decoded?.lastWorkout?.name, "Pull B")
        XCTAssertEqual(decoded?.lastWorkout?.setCount, 1)
        XCTAssertEqual(decoded?.lastWorkout?.volumeKg ?? 0, 500, accuracy: 0.001)
        XCTAssertEqual(decoded?.workoutsThisWeek, 1)
        XCTAssertEqual(decoded?.weightSuffix, "lb")
    }
}
