import XCTest
@testable import Peptide

final class CycleCardModelTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    func test_cycleDay_lateEveningStartNextMorning_isDayTwo() {
        let day = CycleCardModel.cycleDay(from: date(10, hour: 22), now: date(11, hour: 9), calendar: calendar)
        XCTAssertEqual(day, 2)
    }

    func test_cycleDay_startedToday_isDayOne() {
        let day = CycleCardModel.cycleDay(from: date(10, hour: 8), now: date(10, hour: 20), calendar: calendar)
        XCTAssertEqual(day, 1)
    }

    func test_cycleDay_futureStart_isZero() {
        let day = CycleCardModel.cycleDay(from: date(12, hour: 8), now: date(10, hour: 20), calendar: calendar)
        XCTAssertEqual(day, 0)
    }
}
