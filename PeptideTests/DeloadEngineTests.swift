import XCTest
@testable import Peptide

final class DeloadEngineTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }

    /// Wednesday 2026-10-28 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_793_188_800)

    /// A finished workout on the Wednesday `weeksAgo` weeks before `now`,
    /// shifted by `dayOffset` days within that week.
    private func workout(
        weeksAgo: Int, dayOffset: Int = 0, _ lifts: [(id: String, kg: Double, reps: Int)]
    ) -> WorkoutSession {
        let day = calendar.date(byAdding: .day, value: dayOffset - 7 * weeksAgo, to: now)!
        let entries = lifts.enumerated().map { index, lift in
            WorkoutExerciseEntry(exerciseID: lift.id, index: index, sets: [
                SetEntry(index: 1, weightKg: lift.kg, reps: lift.reps, completed: true),
                SetEntry(index: 2, weightKg: lift.kg, reps: lift.reps, completed: true),
            ])
        }
        return WorkoutSession(startedAt: day, finishedAt: day.addingTimeInterval(3600), exercises: entries)
    }

    private func volumeWeeks(_ kgByWeeksAgo: [Int: Double]) -> [WorkoutSession] {
        kgByWeeksAgo.map { weeksAgo, kg in workout(weeksAgo: weeksAgo, [("squat", kg, 10)]) }
    }

    // MARK: - Rising volume

    func test_fourWeeksOfRisingVolume_suggestsDeload() {
        let history = volumeWeeks([4: 60, 3: 65, 2: 70, 1: 75])
        XCTAssertEqual(DeloadEngine.reason(history: history, now: now, calendar: calendar), .risingVolume)
    }

    func test_threeWeeksOfRisingVolume_isNotEnough() {
        let history = volumeWeeks([3: 65, 2: 70, 1: 75])
        XCTAssertNil(DeloadEngine.reason(history: history, now: now, calendar: calendar))
    }

    func test_aLighterWeekInTheRun_resetsIt() {
        let history = volumeWeeks([5: 60, 4: 65, 3: 50, 2: 70, 1: 75])
        XCTAssertEqual(DeloadEngine.risingVolumeWeeks(history, before: weekStart, calendar: calendar), 3)
        XCTAssertNil(DeloadEngine.reason(history: history, now: now, calendar: calendar))
    }

    func test_aWeekOff_breaksTheRun() {
        let history = volumeWeeks([5: 55, 4: 60, 2: 70, 1: 75])
        XCTAssertEqual(DeloadEngine.risingVolumeWeeks(history, before: weekStart, calendar: calendar), 2)
    }

    func test_thisWeeksWorkouts_doNotChangeTheVerdict() {
        var history = volumeWeeks([4: 60, 3: 65, 2: 70, 1: 75])
        history.append(workout(weeksAgo: 0, dayOffset: -1, [("squat", 40, 5)]))
        XCTAssertEqual(DeloadEngine.reason(history: history, now: now, calendar: calendar), .risingVolume)
    }

    func test_unfinishedWorkouts_areIgnored() {
        var history = volumeWeeks([3: 65, 2: 70, 1: 75])
        var unfinished = workout(weeksAgo: 4, [("squat", 60, 10)])
        unfinished.finishedAt = nil
        history.append(unfinished)
        XCTAssertNil(DeloadEngine.reason(history: history, now: now, calendar: calendar))
    }

    func test_noHistory_isNoDeload() {
        XCTAssertNil(DeloadEngine.reason(history: [], now: now, calendar: calendar))
    }

    // MARK: - Stalled lifts

    private func stalledHistory(progressing: Int) -> [WorkoutSession] {
        let stalled = ["bench", "row", "press"]
        let moving = (0..<progressing).map { "lift\($0)" }
        // Three sessions, oldest first; volume falls so the rising rule stays quiet.
        return [3, 2, 1].map { weeksAgo in
            let step = 3 - weeksAgo
            let lifts = stalled.map { (id: $0, kg: 60.0, reps: 8 - step) }
                + moving.map { (id: $0, kg: 40.0 + 2.5 * Double(step), reps: 8) }
            return workout(weeksAgo: weeksAgo, lifts)
        }
    }

    func test_severalStalledLifts_suggestDeload() {
        XCTAssertEqual(
            DeloadEngine.reason(history: stalledHistory(progressing: 1), now: now, calendar: calendar),
            .stalledLifts
        )
    }

    func test_stalledLiftsAsAMinority_doNotSuggestDeload() {
        XCTAssertNil(DeloadEngine.reason(history: stalledHistory(progressing: 4), now: now, calendar: calendar))
    }

    func test_addingWeightWithFewerReps_countsAsProgress() {
        let sessions = [3, 2, 1].map { weeksAgo in
            workout(weeksAgo: weeksAgo, [("bench", weeksAgo == 3 ? 60 : 62.5, weeksAgo == 1 ? 7 : 6)])
        }
        XCTAssertEqual(DeloadEngine.stalledLifts(sessions).stalled, 0)
    }

    func test_liftsWithTooFewSessions_areNotJudged() {
        let sessions = [2, 1].map { workout(weeksAgo: $0, [("bench", 60, 8)]) }
        XCTAssertEqual(DeloadEngine.stalledLifts(sessions).tracked, 0)
    }

    private var weekStart: Date {
        calendar.dateInterval(of: .weekOfYear, for: now)!.start
    }
}
