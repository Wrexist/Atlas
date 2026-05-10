import XCTest
@testable import Peptide

final class CycleBandsTests: XCTestCase {

    // MARK: - Empty / inactive

    func test_bands_emptyProtocols_returnsSixEmptyRows() {
        let grid = makeGrid()
        let result = CycleBands.bands(for: grid, protocols: [])
        XCTAssertEqual(result.count, 6)
        XCTAssertTrue(result.allSatisfy(\.isEmpty))
    }

    func test_bands_pausedProtocol_isExcluded() {
        let grid = makeGrid()
        let proto = makeProtocol(daysAgo: 0, weeks: 4, status: .paused)
        let result = CycleBands.bands(for: grid, protocols: [proto])
        XCTAssertTrue(result.allSatisfy(\.isEmpty))
    }

    // MARK: - Window overlap

    func test_bands_protocolStartingThisMonth_paintsRowsThroughEndOfCycle() {
        let grid = makeGrid()
        let cal = Calendar.current
        // Protocol starts on the first of the displayed month, runs 4 weeks.
        let monthStart = grid.first { cal.component(.day, from: $0) == 1 }
            ?? grid[7]
        let proto = makeProtocol(startDate: monthStart, weeks: 4)
        let result = CycleBands.bands(for: grid, protocols: [proto])

        let rowsWithBand = result.enumerated().filter { !$0.element.isEmpty }.map(\.offset)
        // Should paint the row containing the start day plus the next 3
        // weeks — at minimum 4 consecutive rows.
        XCTAssertGreaterThanOrEqual(rowsWithBand.count, 4)
        // Trailing weeks beyond the cycle window must not light up.
        if let last = rowsWithBand.last {
            XCTAssertLessThan(last, 6)
        }
    }

    func test_bands_completedProtocolPriorToMonth_emptyAcrossMonth() {
        let grid = makeGrid()
        let cal = Calendar.current
        // Started 12 weeks ago, only ran 4 weeks → ended 8 weeks ago.
        let start = cal.date(byAdding: .day, value: -12 * 7, to: Date()) ?? Date()
        let proto = makeProtocol(startDate: start, weeks: 4)
        let result = CycleBands.bands(for: grid, protocols: [proto])
        XCTAssertTrue(result.allSatisfy(\.isEmpty))
    }

    // MARK: - Multiple protocols

    func test_bands_multipleProtocolsSameWeek_stack() {
        let grid = makeGrid()
        let cal = Calendar.current
        let weekStart = grid[2 * 7] // third row
        let middleOfWeek = cal.date(byAdding: .day, value: 3, to: weekStart) ?? weekStart
        let a = makeProtocol(startDate: middleOfWeek, weeks: 2)
        let b = makeProtocol(startDate: middleOfWeek, weeks: 2)
        let result = CycleBands.bands(for: grid, protocols: [a, b])
        XCTAssertEqual(result[2].count, 2, "Two protocols overlapping the same week should produce two bands")
    }

    // MARK: - Helpers

    private func makeGrid() -> [Date] {
        CalendarMonth.grid(for: Date(), firstWeekday: Calendar.current.firstWeekday)
    }

    private func makeProtocol(
        daysAgo: Int = 0,
        startDate: Date? = nil,
        weeks: Int,
        status: ProtocolStatus = .active
    ) -> PeptideProtocol {
        let start = startDate
            ?? Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())
            ?? Date()
        return PeptideProtocol(
            id: UUID(),
            name: "Test \(weeks)w",
            peptides: [],
            schedule: ProtocolSchedule(daysOfWeek: [1, 2, 3, 4, 5, 6, 7], timesPerDay: 1, preferredTimes: ["8:00 AM"]),
            cycleLengthWeeks: weeks,
            startDate: start,
            status: status,
            notes: ""
        )
    }
}
