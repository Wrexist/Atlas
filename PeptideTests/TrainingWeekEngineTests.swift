import XCTest
@testable import Peptide

/// The one "trained days" count that Today, the widget, Train's goal card
/// and the weekly check-in compare to the days-per-week target.
final class TrainingWeekEngineTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Monday 2026-10-19 08:00 UTC.
    private let mondayMorning = Date(timeIntervalSince1970: 1_792_368_000 + 8 * 3_600)

    private func finished(_ start: Date) -> WorkoutSession {
        WorkoutSession(startedAt: start, finishedAt: start.addingTimeInterval(3_600))
    }

    func test_trainedDaysThisWeek_morningAndEveningSessions_countOneDay() {
        let evening = mondayMorning.addingTimeInterval(10 * 3_600)
        let tuesday = mondayMorning.addingTimeInterval(86_400)

        let days = TrainingWeekEngine.trainedDaysThisWeek(
            [finished(mondayMorning), finished(evening), finished(tuesday)],
            now: tuesday,
            calendar: calendar
        )

        XCTAssertEqual(days, 2)
    }

    func test_trainedDays_inProgressSession_isLeftOut() {
        let day = mondayMorning..<mondayMorning.addingTimeInterval(86_400)

        let days = TrainingWeekEngine.trainedDays(
            [WorkoutSession(startedAt: mondayMorning)],
            in: day,
            calendar: calendar
        )

        XCTAssertEqual(days, 0)
    }

    func test_trainedDays_datesOutsideInterval_areLeftOut() {
        let start = calendar.startOfDay(for: mondayMorning)
        let interval = start..<start.addingTimeInterval(2 * 86_400)
        let dates = [
            mondayMorning,
            mondayMorning.addingTimeInterval(3_600),
            mondayMorning.addingTimeInterval(86_400),
            mondayMorning.addingTimeInterval(-86_400),
            mondayMorning.addingTimeInterval(2 * 86_400),
        ]

        XCTAssertEqual(TrainingWeekEngine.trainedDays(dates: dates, in: interval, calendar: calendar), 2)
    }
}
