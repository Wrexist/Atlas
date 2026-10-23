import XCTest
@testable import Peptide

@MainActor
final class LabEntryEditorTests: XCTestCase {

    func test_parseDecimal_infinityOrOverflow_isRejected() {
        XCTAssertNil(LabEntryEditor.parseDecimal("inf"))
        XCTAssertNil(LabEntryEditor.parseDecimal("1e999"))
        XCTAssertNil(LabEntryEditor.parseDecimal("nan"))
    }

    func test_parseDecimal_plainNumber_parses() {
        XCTAssertEqual(LabEntryEditor.parseDecimal(" 720 "), 720)
    }

    func test_parseDecimal_empty_isNil() {
        XCTAssertNil(LabEntryEditor.parseDecimal("   "))
    }

    // MARK: - Carry-over defaults

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ day: Int, hour: Int, minute: Int = 0) -> Date {
        utcCalendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    private func entry(drawnOn drawn: Date, savedAt saved: Date, source: String? = "Quest") -> LabValue {
        LabValue(date: drawn, panel: .vitaminD, value: 40, source: source, updatedAt: saved)
    }

    func test_carryOverEntry_savedMinutesAgo_returnsLatestSaved() {
        let older = entry(drawnOn: date(1, hour: 8), savedAt: date(10, hour: 9), source: "Labcorp")
        let newest = entry(drawnOn: date(2, hour: 8), savedAt: date(10, hour: 9, minute: 30))
        let result = LabEntryEditor.carryOverEntry(from: [newest, older], now: date(10, hour: 9, minute: 40))
        XCTAssertEqual(result?.id, newest.id)
        XCTAssertEqual(result?.source, "Quest")
    }

    func test_carryOverEntry_savedOverAnHourAgo_returnsNil() {
        let saved = entry(drawnOn: date(2, hour: 8), savedAt: date(10, hour: 8))
        XCTAssertNil(LabEntryEditor.carryOverEntry(from: [saved], now: date(10, hour: 9, minute: 1)))
    }

    func test_carryOverEntry_noEntries_returnsNil() {
        XCTAssertNil(LabEntryEditor.carryOverEntry(from: [], now: date(10, hour: 9)))
    }

    func test_carryOverEntry_savedInTheFuture_returnsNil() {
        // A clock skewed by sync must not pin every new entry to it.
        let skewed = entry(drawnOn: date(2, hour: 8), savedAt: date(10, hour: 12))
        XCTAssertNil(LabEntryEditor.carryOverEntry(from: [skewed], now: date(10, hour: 9)))
    }
}
