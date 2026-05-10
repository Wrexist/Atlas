import XCTest
@testable import Peptide

final class CalendarMonthTests: XCTestCase {

    // MARK: - Grid shape

    func test_grid_alwaysReturns42Cells() {
        let cal = makeCalendar(firstWeekday: 1, timeZone: .gmt)
        // Sample a year so different month-lengths and weekday-of-1st permutations are exercised.
        for month in 1...12 {
            let date = makeDate(year: 2026, month: month, day: 1, calendar: cal)
            let grid = CalendarMonth.grid(for: date, firstWeekday: 1, calendar: cal)
            XCTAssertEqual(grid.count, 42, "Month \(month) returned \(grid.count) cells")
        }
    }

    func test_grid_isContiguousAtStartOfDay() {
        let cal = makeCalendar(firstWeekday: 1, timeZone: .gmt)
        let date = makeDate(year: 2026, month: 5, day: 15, calendar: cal)
        let grid = CalendarMonth.grid(for: date, firstWeekday: 1, calendar: cal)
        XCTAssertEqual(grid.count, 42)
        for index in 1..<grid.count {
            let expected = cal.date(byAdding: .day, value: 1, to: grid[index - 1])
            XCTAssertEqual(grid[index], expected, "Grid is not day-contiguous at index \(index)")
            XCTAssertEqual(grid[index], cal.startOfDay(for: grid[index]),
                           "Grid entry is not at start-of-day at index \(index)")
        }
    }

    // MARK: - First weekday

    /// May 2026 starts on a Friday. Sun-start should fill the leading row
    /// with five days from April; Mon-start fills the leading row with
    /// four (Mon–Thu of the previous week).
    func test_grid_sundayStart_includesFiveLeadingDays() {
        let cal = makeCalendar(firstWeekday: 1, timeZone: .gmt)
        let date = makeDate(year: 2026, month: 5, day: 1, calendar: cal)
        let grid = CalendarMonth.grid(for: date, firstWeekday: 1, calendar: cal)
        let firstOfMonth = makeDate(year: 2026, month: 5, day: 1, calendar: cal)
        XCTAssertEqual(grid.firstIndex(of: firstOfMonth), 5)
    }

    func test_grid_mondayStart_includesFourLeadingDays() {
        let cal = makeCalendar(firstWeekday: 2, timeZone: .gmt)
        let date = makeDate(year: 2026, month: 5, day: 1, calendar: cal)
        let grid = CalendarMonth.grid(for: date, firstWeekday: 2, calendar: cal)
        let firstOfMonth = makeDate(year: 2026, month: 5, day: 1, calendar: cal)
        XCTAssertEqual(grid.firstIndex(of: firstOfMonth), 4)
    }

    // MARK: - Weekday symbols

    func test_weekdaySymbols_sundayStart_putsSunFirst() {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US")
        let symbols = CalendarMonth.weekdaySymbols(firstWeekday: 1, calendar: cal)
        XCTAssertEqual(symbols.count, 7)
        XCTAssertEqual(symbols.first, cal.shortWeekdaySymbols.first)
    }

    func test_weekdaySymbols_mondayStart_rotatesSundayToEnd() {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US")
        let symbols = CalendarMonth.weekdaySymbols(firstWeekday: 2, calendar: cal)
        XCTAssertEqual(symbols.count, 7)
        // Sunday (index 0 in shortWeekdaySymbols) should now be at the end.
        XCTAssertEqual(symbols.last, cal.shortWeekdaySymbols.first)
        // Monday (index 1) should be first.
        XCTAssertEqual(symbols.first, cal.shortWeekdaySymbols[1])
    }

    // MARK: - Helpers

    private func makeCalendar(firstWeekday: Int, timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.firstWeekday = firstWeekday
        return cal
    }

    private func makeDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
        calendar.startOfDay(for: calendar.date(from: DateComponents(
            year: year, month: month, day: day
        ))!)
    }
}
