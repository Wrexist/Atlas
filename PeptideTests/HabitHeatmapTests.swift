import XCTest
@testable import Peptide

/// The month-label row sits above the heatmap grid. If its widths add up
/// to more than the grid, the heatmap measures wider than it was offered,
/// re-sizes its cells from that, and grows again on every layout pass —
/// the hang that froze the Habits tab.
@MainActor
final class HabitHeatmapTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func start() -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 4, day: 27))!
    }

    func test_monthLabels_widthsAddUpToGridWidth() {
        let columns = 27
        let cell: CGFloat = 9.33
        let spacing: CGFloat = 3
        let labels = HabitHeatmap.monthLabels(
            firstColumnStart: start(),
            columnCount: columns,
            cellSize: cell,
            cellSpacing: spacing,
            calendar: calendar
        )
        let gridWidth = CGFloat(columns) * cell + CGFloat(columns - 1) * spacing
        XCTAssertEqual(labels.map(\.width).reduce(0, +), gridWidth, accuracy: 0.001)
    }

    func test_monthLabels_oneLabelPerMonthCrossed() {
        let labels = HabitHeatmap.monthLabels(
            firstColumnStart: start(),
            columnCount: 27,
            cellSize: 9,
            cellSpacing: 3,
            calendar: calendar
        )
        // 27 weeks from 27 April run through late October: Apr … Oct.
        XCTAssertEqual(labels.count, 7)
        XCTAssertEqual(labels.first?.offset, 0)
    }

    func test_monthLabels_empty_withoutStartOrColumns() {
        XCTAssertTrue(HabitHeatmap.monthLabels(
            firstColumnStart: nil, columnCount: 27, cellSize: 9, cellSpacing: 3, calendar: calendar
        ).isEmpty)
        XCTAssertTrue(HabitHeatmap.monthLabels(
            firstColumnStart: start(), columnCount: 0, cellSize: 9, cellSpacing: 3, calendar: calendar
        ).isEmpty)
    }
}
