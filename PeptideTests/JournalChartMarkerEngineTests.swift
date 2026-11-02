import XCTest
@testable import Peptide

final class JournalChartMarkerEngineTests: XCTestCase {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2025-10-10 00:00 UTC.
    private let dayZero = Date(timeIntervalSince1970: 1_760_054_400)

    private func day(_ offset: Int, hour: Double = 0) -> Date {
        dayZero.addingTimeInterval(Double(offset) * 86_400 + hour * 3600)
    }

    /// Days 0 through 6, with day 7's midnight as the exclusive end.
    private var week: ClosedRange<Date> { day(0)...day(7) }

    func test_markers_keepOnlyDaysInsideRange_oldestFirst() {
        let entries = [
            HealthJournalEntry(day: day(5), mood: .good, note: "Rest day"),
            HealthJournalEntry(day: day(-1), mood: .low),
            HealthJournalEntry(day: day(7), mood: .great),
            HealthJournalEntry(day: day(1), mood: .awful, note: "Alcohol, late meal"),
        ]

        let markers = JournalChartMarkerEngine.markers(from: entries, in: week, calendar: utc)

        XCTAssertEqual(markers.map(\.day), [day(1), day(5)])
        XCTAssertEqual(markers.map(\.mood), [.awful, .good])
        XCTAssertEqual(markers.first?.excerpt, "Alcohol, late meal")
    }

    func test_markers_entryOffMidnight_snapsToItsDay() {
        let entries = [HealthJournalEntry(day: day(2, hour: 14), mood: .okay)]

        let markers = JournalChartMarkerEngine.markers(from: entries, in: week, calendar: utc)

        XCTAssertEqual(markers.map(\.day), [day(2)])
    }

    func test_markers_twoEntriesOnOneDay_yieldOneMarker() {
        let entries = [
            HealthJournalEntry(day: day(3), mood: .low),
            HealthJournalEntry(day: day(3, hour: 9), mood: .good),
        ]

        XCTAssertEqual(JournalChartMarkerEngine.markers(from: entries, in: week, calendar: utc).count, 1)
    }

    func test_marker_onScrubbedDate_findsSameDayOnly() {
        let markers = JournalChartMarkerEngine.markers(
            from: [HealthJournalEntry(day: day(4), mood: .low, note: "Stress")],
            in: week,
            calendar: utc
        )

        XCTAssertEqual(JournalChartMarkerEngine.marker(on: day(4, hour: 18), in: markers, calendar: utc)?.excerpt, "Stress")
        XCTAssertNil(JournalChartMarkerEngine.marker(on: day(5), in: markers, calendar: utc))
    }

    func test_excerpt_emptyOrBlankNote_isNil() {
        XCTAssertNil(JournalChartMarkerEngine.excerpt(""))
        XCTAssertNil(JournalChartMarkerEngine.excerpt("  \n  "))
    }

    func test_excerpt_multiline_keepsFirstLine() {
        XCTAssertEqual(JournalChartMarkerEngine.excerpt("Late meal\nSlept badly"), "Late meal")
    }

    func test_excerpt_longNote_cutsAtWordWithEllipsis() throws {
        let note = String(repeating: "stress ", count: 20)

        let excerpt = try XCTUnwrap(JournalChartMarkerEngine.excerpt(note))

        XCTAssertTrue(excerpt.hasSuffix("stress…"))
        XCTAssertLessThanOrEqual(excerpt.count, JournalChartMarkerEngine.excerptLimit + 1)
    }
}
