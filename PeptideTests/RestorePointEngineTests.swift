import XCTest
@testable import Peptide

final class RestorePointEngineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    /// 2026-12-01 12:00 UTC, a Tuesday.
    private let base = Date(timeIntervalSince1970: 1_796_126_400)

    private func days(_ n: Double) -> TimeInterval { n * 24 * 60 * 60 }

    func test_isDue_noPointYet_isDue() {
        XCTAssertTrue(RestorePointEngine.isDue(latest: nil, now: base))
    }

    func test_isDue_pointFromEarlierToday_isNotDue() {
        XCTAssertFalse(RestorePointEngine.isDue(latest: base.addingTimeInterval(-3600), now: base))
    }

    func test_isDue_pointOneDayOld_isDue() {
        XCTAssertTrue(RestorePointEngine.isDue(latest: base.addingTimeInterval(-days(1)), now: base))
    }

    func test_datesToKeep_fewPoints_keepsAll() {
        let dates = (0..<4).map { base.addingTimeInterval(-days(Double($0))) }
        XCTAssertEqual(RestorePointEngine.datesToKeep(dates, calendar: calendar), Set(dates))
    }

    func test_datesToKeep_twoPointsSameDay_keepsOnlyTheNewer() {
        let newer = base
        let older = base.addingTimeInterval(-3600)
        XCTAssertEqual(RestorePointEngine.datesToKeep([older, newer], calendar: calendar), [newer])
    }

    func test_datesToKeep_ninetyDailyPoints_keepsSevenDaysPlusEightWeeks() throws {
        let dates = (0..<90).map { base.addingTimeInterval(-days(Double($0))) }
        let kept = RestorePointEngine.datesToKeep(dates, calendar: calendar)

        // The 7 newest days are all kept.
        for offset in 0..<7 {
            XCTAssertTrue(kept.contains(base.addingTimeInterval(-days(Double(offset)))))
        }
        // Weekly points overlap this week and last week's daily ones, so
        // the total stays at or under 15.
        XCTAssertLessThanOrEqual(kept.count, RestorePointEngine.dailyPointsKept + RestorePointEngine.weeklyPointsKept)
        // Nothing older than the 8th week back survives.
        let oldestKept = try XCTUnwrap(kept.min())
        XCTAssertGreaterThan(oldestKept, base.addingTimeInterval(-days(8 * 7 + 7)))
        // About two months back is still covered.
        XCTAssertLessThan(oldestKept, base.addingTimeInterval(-days(6 * 7)))
    }

    func test_datesToKeep_eachKeptWeekHasOnePoint() {
        let dates = (0..<90).map { base.addingTimeInterval(-days(Double($0))) }
        let kept = RestorePointEngine.datesToKeep(dates, calendar: calendar)
        let olderThanAWeek = kept.filter { $0 < base.addingTimeInterval(-days(7)) }
        let weeks = olderThanAWeek.map { calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0) }
        XCTAssertEqual(weeks.count, Set(weeks).count)
    }
}
