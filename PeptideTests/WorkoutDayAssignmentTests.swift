import XCTest
@testable import Peptide

/// A workout that runs past midnight belongs to the day it started, on
/// every surface that buckets workouts by day or week. History used the
/// finish date while the calendar used the start date, so one late
/// session showed up on two different days.
@MainActor
final class WorkoutDayAssignmentTests: XCTestCase {

    /// Gregorian, Monday-first, Stockholm — an explicit zone so the test
    /// doesn't depend on the UTC runner.
    private func stockholm() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Stockholm"))
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ calendar: Calendar, day: Int, hour: Int, minute: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)))
    }

    /// Sunday 2026-10-04 23:30 to Monday 2026-10-05 00:45 — the last day
    /// of one week into the first day of the next.
    private func lateSundaySession(_ calendar: Calendar) throws -> WorkoutSession {
        var session = WorkoutRecapFixture.push(finishedAt: try date(calendar, day: 5, hour: 0, minute: 45))
        session.startedAt = try date(calendar, day: 4, hour: 23, minute: 30)
        return session
    }

    func test_workoutPastMidnight_belongsToTheDayItStarted() throws {
        let calendar = try stockholm()
        let session = try lateSundaySession(calendar)

        XCTAssertEqual(session.day(in: calendar), try date(calendar, day: 4, hour: 0))
    }

    func test_workoutPastMidnightOnSunday_isLeftOutOfTheNextWeek_onEverySurface() throws {
        let calendar = try stockholm()
        let session = try lateSundaySession(calendar)
        let mondayMorning = try date(calendar, day: 5, hour: 9)

        let widget = WidgetSnapshotBuilder.training(from: [session], now: mondayMorning, calendar: calendar)
        let overview = TrainOverviewView.trainedDaysThisWeek([session], now: mondayMorning, calendar: calendar)
        let recap = WorkoutRecapEngine.week(sessions: [session], catalog: [:], now: mondayMorning, calendar: calendar)

        XCTAssertEqual(widget.workoutsThisWeek, 0)
        XCTAssertEqual(widget.trainingDays, [])
        XCTAssertEqual(overview, 0)
        XCTAssertEqual(recap.count, 0)
    }

    func test_workoutPastMidnightOnSunday_countsOnSundayOfTheWeekItStarted() throws {
        let calendar = try stockholm()
        let session = try lateSundaySession(calendar)
        let sundayNoon = try date(calendar, day: 4, hour: 12)
        let sunday = try date(calendar, day: 4, hour: 0)

        let widget = WidgetSnapshotBuilder.training(from: [session], now: sundayNoon, calendar: calendar)
        let overview = TrainOverviewView.trainedDaysThisWeek([session], now: sundayNoon, calendar: calendar)
        let recap = WorkoutRecapEngine.week(sessions: [session], catalog: [:], anchor: session.startedAt,
                                            now: try date(calendar, day: 5, hour: 9), calendar: calendar)

        XCTAssertEqual(widget.workoutsThisWeek, 1)
        XCTAssertEqual(widget.trainingDays, [sunday.addingTimeInterval(12 * 3600)])
        XCTAssertEqual(overview, 1)
        XCTAssertEqual(recap.count, 1)
        XCTAssertEqual(recap.days.last?.count, 1)
        XCTAssertEqual(recap.days.last.map { calendar.component(.day, from: $0.date) }, 4)
    }

    func test_widgetLastWorkout_isLabelledWithTheDayItStarted() throws {
        let calendar = try stockholm()
        let session = try lateSundaySession(calendar)

        let last = WidgetSnapshotBuilder.training(from: [session], now: try date(calendar, day: 5, hour: 9),
                                                  calendar: calendar).lastWorkout

        XCTAssertEqual(last?.day, session.startedAt)
        XCTAssertEqual(last?.finishedAt, session.finishedAt)
    }

    func test_widgetSummaryWrittenBeforeStartDateExisted_fallsBackToFinishDate() throws {
        let legacy = """
        {"name": "Push", "finishedAt": "2026-10-05T00:45:00Z", "setCount": 3, "volumeKg": 500, "durationMinutes": 75}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let summary = try decoder.decode(WidgetWorkoutSummary.self, from: Data(legacy.utf8))

        XCTAssertNil(summary.startedAt)
        XCTAssertEqual(summary.day, summary.finishedAt)
    }
}
