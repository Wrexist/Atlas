import XCTest
@testable import Peptide

final class WatchDataTests: XCTestCase {

    /// Whole seconds: the pipeline's `.iso8601` strategy drops fractions.
    private let now = Date(timeIntervalSince1970: 1_760_166_000)

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private var vitals: WatchVitalsSnapshot {
        WatchVitalsSnapshot(
            recoveryScore: 82,
            restingHeartRate: 56,
            restingHeartRateBaseline: 58,
            hrv: 64,
            hrvBaseline: 59,
            sleep: WatchSleepSnapshot(
                score: 84,
                start: now.addingTimeInterval(-8 * 3600),
                end: now,
                deepMinutes: 72,
                coreMinutes: 236,
                remMinutes: 104,
                unspecifiedMinutes: 0,
                awakeMinutes: 18
            ),
            measuredAt: now
        )
    }

    private func entry(completed: Bool) -> WatchEntry {
        WatchEntry(id: UUID(), protocolId: UUID(), peptideName: "BPC-157", abbreviation: "BPC",
                   dose: "250 mcg", scheduledTime: now, completed: completed)
    }

    // MARK: - Wire format

    func test_roundTrip_withVitals_preservesVitals() throws {
        let data = WatchData(todayEntries: [], completedToday: 0, totalToday: 0,
                             lastUpdated: now, vitals: vitals)
        let decoded = try decoder.decode(WatchData.self, from: encoder.encode(data))
        XCTAssertEqual(decoded.vitals, vitals)
    }

    /// A phone on an older build never writes `vitals`. The Watch must
    /// still decode the rest rather than drop the whole push.
    func test_decode_payloadWithoutVitals_decodesWithNilVitals() throws {
        let json = #"{"todayEntries":[],"completedToday":0,"totalToday":0,"lastUpdated":"2025-10-11T07:00:00Z","atlasScore":142}"#
        let decoded = try decoder.decode(WatchData.self, from: Data(json.utf8))
        XCTAssertNil(decoded.vitals)
        XCTAssertEqual(decoded.atlasScore, 142)
    }

    func test_roundTrip_healthConnectedWithoutVitals_keepsConnectedFlag() throws {
        let data = WatchData(todayEntries: [], completedToday: 0, totalToday: 0,
                             lastUpdated: now, healthConnected: true)
        let decoded = try decoder.decode(WatchData.self, from: encoder.encode(data))
        XCTAssertEqual(decoded.healthConnected, true)
        XCTAssertNil(decoded.vitals)
    }

    // MARK: - Optimistic dose toggle

    func test_replacingEntries_recountsAndKeepsEveryOtherField() {
        let original = WatchData(
            todayEntries: [entry(completed: false), entry(completed: false)],
            completedToday: 0, totalToday: 2, lastUpdated: now,
            currentStreak: 5, nutrition: nil, atlasScore: 142, atlasTier: "gold",
            healthHabitsDone: 1, healthHabitsTotal: 3, measurementUnit: "metric",
            vitals: vitals
        )
        var toggled = original.todayEntries
        toggled[0].completed = true

        let updated = original.replacingEntries(toggled)

        XCTAssertEqual(updated.completedToday, 1)
        XCTAssertEqual(updated.totalToday, 2)
        XCTAssertEqual(updated.currentStreak, 5)
        XCTAssertEqual(updated.atlasScore, 142)
        XCTAssertEqual(updated.atlasTier, "gold")
        XCTAssertEqual(updated.healthHabitsTotal, 3)
        XCTAssertEqual(updated.measurementUnit, "metric")
        XCTAssertEqual(updated.vitals, vitals)
    }

    // MARK: - Day rollover and staleness

    private var nutrition: WatchNutritionSnapshot {
        WatchNutritionSnapshot(caloriesToday: 1800, calorieTarget: 2400, proteinToday: 120,
                               proteinTarget: 160, mealLoggingStreak: 4, mealEntriesToday: 3)
    }

    private var workout: WatchWorkoutSnapshot {
        WatchWorkoutSnapshot(sessionId: UUID(), name: "Push", timerStartedAt: now, pausedElapsedSeconds: nil,
                             exercises: [], selectedExerciseID: nil, rest: nil)
    }

    private func fullDay(workout: WatchWorkoutSnapshot? = nil) -> WatchData {
        WatchData(
            todayEntries: [entry(completed: true), entry(completed: false)],
            completedToday: 1, totalToday: 2, lastUpdated: now,
            currentStreak: 5, nutrition: nutrition, atlasScore: 142, atlasTodayEarned: 6,
            healthHabitsDone: 2, healthHabitsTotal: 3, trainingHabitsDone: 1, trainingHabitsTotal: 2,
            vitals: vitals, workout: workout
        )
    }

    func test_forDisplay_sameDay_keepsTheDaysProgress() {
        let shown = fullDay().forDisplay(at: now.addingTimeInterval(60))
        XCTAssertEqual(shown.totalToday, 2)
        XCTAssertEqual(shown.completedToday, 1)
        XCTAssertEqual(shown.atlasTodayEarned, 6)
        XCTAssertEqual(shown.healthHabitsDone, 2)
        XCTAssertEqual(shown.nutrition, nutrition)
    }

    /// After midnight, yesterday's doses must not be listed or tappable,
    /// and the habit and score counts start the new day at zero.
    func test_forDisplay_snapshotFromEarlierDay_clearsDayProgressButKeepsTotals() {
        let shown = fullDay().forDisplay(at: now.addingTimeInterval(24 * 3600))
        XCTAssertTrue(shown.todayEntries.isEmpty)
        XCTAssertEqual(shown.completedToday, 0)
        XCTAssertEqual(shown.totalToday, 0)
        XCTAssertEqual(shown.atlasTodayEarned, 0)
        XCTAssertEqual(shown.healthHabitsDone, 0)
        XCTAssertEqual(shown.trainingHabitsDone, 0)
        XCTAssertEqual(shown.healthHabitsTotal, 3)
        XCTAssertEqual(shown.nutrition?.caloriesToday, 0)
        XCTAssertEqual(shown.nutrition?.calorieTarget, 2400)
        XCTAssertEqual(shown.currentStreak, 5)
        XCTAssertEqual(shown.atlasScore, 142)
        XCTAssertEqual(shown.vitals, vitals)
    }

    func test_forDisplay_workoutPushedHoursAgo_dropsTheWorkout() {
        let data = fullDay(workout: workout)
        XCTAssertNotNil(data.forDisplay(at: now.addingTimeInterval(3600)).workout)
        XCTAssertNil(data.forDisplay(at: now.addingTimeInterval(WatchData.workoutStaleAfter + 1)).workout)
    }

    /// The phone refreshes vitals only when its app is opened, so a night
    /// days old must not be shown as last night. Recovery stays.
    func test_forDisplay_sleepEndedOverThirtyHoursAgo_dropsOnlyTheSleep() {
        let data = fullDay()
        XCTAssertNotNil(data.forDisplay(at: now.addingTimeInterval(WatchData.sleepStaleAfter - 60)).vitals?.sleep)
        let shown = data.forDisplay(at: now.addingTimeInterval(WatchData.sleepStaleAfter + 60))
        XCTAssertNil(shown.vitals?.sleep)
        XCTAssertEqual(shown.vitals?.recoveryScore, 82)
        XCTAssertEqual(shown.vitals?.measuredAt, now)
    }

    // MARK: - Push change detection

    func test_hasSameContent_differentStampOnly_isTrue() {
        let data = fullDay()
        XCTAssertTrue(data.stamped(now.addingTimeInterval(300)).hasSameContent(as: data))
    }

    func test_hasSameContent_doseToggled_isFalse() {
        let data = fullDay()
        var entries = data.todayEntries
        entries[1].completed = true
        XCTAssertFalse(data.replacingEntries(entries).hasSameContent(as: data))
    }

    func test_changesComplications_doseCountOrWorkoutStartChanges_isTrue() {
        let data = fullDay()
        var entries = data.todayEntries
        entries[1].completed = true
        XCTAssertTrue(data.replacingEntries(entries).changesComplications(from: data))
        XCTAssertTrue(data.replacingWorkout(workout).changesComplications(from: data))
    }

    /// Set edits arrive many times a minute and must not spend the daily
    /// complication-transfer budget.
    func test_changesComplications_sameWorkoutEdited_isFalse() {
        let started = workout
        let running = fullDay(workout: started)
        let edited = WatchWorkoutSnapshot(sessionId: started.sessionId, name: "Push day", timerStartedAt: now,
                                          pausedElapsedSeconds: 30, exercises: [], selectedExerciseID: nil, rest: nil)
        XCTAssertFalse(running.replacingWorkout(edited).changesComplications(from: running))
    }

    /// The phone stamps each workout push so the Watch can tell it from an
    /// older one; the Watch's optimistic copy keeps the push's date.
    func test_replacingWorkout_stampsOnlyWhenGivenADate() {
        let later = now.addingTimeInterval(30)
        XCTAssertEqual(fullDay().replacingWorkout(workout).lastUpdated, now)
        XCTAssertEqual(fullDay().replacingWorkout(workout, updatedAt: later).lastUpdated, later)
    }

    func test_decode_payloadWithoutHapticsSetting_decodesWithNil() throws {
        let json = #"{"todayEntries":[],"completedToday":0,"totalToday":0,"lastUpdated":"2025-10-11T07:00:00Z"}"#
        let decoded = try decoder.decode(WatchData.self, from: Data(json.utf8))
        XCTAssertNil(decoded.hapticsEnabled)
    }

    // MARK: - Sleep snapshot

    func test_sleepBand_matchesScoreCutPoints() {
        let cases: [(Int, SleepBand)] = [
            (40, .veryLow), (41, .low), (60, .low), (61, .ok),
            (80, .ok), (81, .high), (95, .high), (96, .veryHigh),
        ]
        for (score, band) in cases {
            XCTAssertEqual(SleepBand(score: score), band, "score \(score)")
        }
    }

    func test_sleepSnapshot_asleepMinutes_excludesAwake() {
        XCTAssertEqual(vitals.sleep?.asleepMinutes, 412)
        XCTAssertEqual(vitals.sleep?.hasStages, true)
    }
}
