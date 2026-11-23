import XCTest
@testable import Peptide

/// Every format is persisted, so these pin the exact strings.
final class DayKeyTests: XCTestCase {

    private func calendar(_ identifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: identifier))
        return calendar
    }

    private func date(_ calendar: Calendar, month: Int, day: Int, hour: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)))
    }

    func test_singleDigitMonthAndDay_keepEachFormatsPadding() throws {
        let utc = try calendar("UTC")
        let fifthOfJanuary = try date(utc, month: 1, day: 5, hour: 12)
        XCTAssertEqual(DayKey.dashed(fifthOfJanuary, calendar: utc), "2026-01-05")
        XCTAssertEqual(DayKey.compact(fifthOfJanuary, calendar: utc), "20260105")
        XCTAssertEqual(DayKey.unpadded(fifthOfJanuary, calendar: utc), "2026-1-5")
    }

    func test_justAfterLocalMidnight_namesTheLocalDayNotUTC() throws {
        let tokyo = try calendar("Asia/Tokyo")
        let earlyMorning = try date(tokyo, month: 10, day: 23, hour: 0)
        XCTAssertEqual(DayKey.dashed(earlyMorning, calendar: tokyo), "2026-10-23")
        XCTAssertEqual(DayKey.compact(earlyMorning, calendar: tokyo), "20261023")
        XCTAssertEqual(DayKey.unpadded(earlyMorning, calendar: tokyo), "2026-10-23")
    }

    func test_featureKeys_matchTheirPersistedFormats() throws {
        let utc = try calendar("UTC")
        let day = try date(utc, month: 3, day: 7, hour: 9)
        XCTAssertEqual(SupplementEngine.dayKey(for: day, calendar: utc), "2026-03-07")
        XCTAssertEqual(UpsellScheduler.dayKey(for: day, calendar: utc), "2026-03-07")
        XCTAssertEqual(StreakFreezeService.dayKey(for: day, calendar: utc), "20260307")
        XCTAssertEqual(HealthJournalEntry.dayKey(for: day, calendar: utc), "2026-3-7")
    }
}
