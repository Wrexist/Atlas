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

    func test_carryOverEntry_createdMinutesAgo_returnsIt() {
        let created = entry(drawnOn: date(2, hour: 8), savedAt: date(10, hour: 9, minute: 30))
        let result = LabEntryEditor.carryOverEntry(lastCreated: created, now: date(10, hour: 9, minute: 40))
        XCTAssertEqual(result?.id, created.id)
        XCTAssertEqual(result?.source, "Quest")
    }

    func test_carryOverEntry_savedOverAnHourAgo_returnsNil() {
        let saved = entry(drawnOn: date(2, hour: 8), savedAt: date(10, hour: 8))
        XCTAssertNil(LabEntryEditor.carryOverEntry(lastCreated: saved, now: date(10, hour: 9, minute: 1)))
    }

    func test_carryOverEntry_nothingCreated_returnsNil() {
        XCTAssertNil(LabEntryEditor.carryOverEntry(lastCreated: nil, now: date(10, hour: 9)))
    }

    func test_carryOverEntry_savedInTheFuture_returnsNil() {
        // A clock skewed by sync must not pin every new entry to it.
        let skewed = entry(drawnOn: date(2, hour: 8), savedAt: date(10, hour: 12))
        XCTAssertNil(LabEntryEditor.carryOverEntry(lastCreated: skewed, now: date(10, hour: 9)))
    }

    // MARK: - Which entry carries over

    func test_lastCreatedLabValue_editingAnOldResult_doesNotBecomeCarryOver() {
        let store = DataStore(seedSampleData: false)
        let old = LabValue(date: date(1, hour: 8), panel: .vitaminD, value: 30, source: "Old lab")
        store.saveLabValue(old)
        let today = LabValue(date: date(10, hour: 8), panel: .ldl, value: 100, source: "Quest")
        store.saveLabValue(today)

        var fixed = old
        fixed.value = 31
        store.saveLabValue(fixed)

        XCTAssertEqual(store.lastCreatedLabValue?.id, today.id)
    }

    func test_lastCreatedLabValue_editingTheNewEntry_keepsItsLatestVersion() {
        let store = DataStore(seedSampleData: false)
        let created = LabValue(date: date(10, hour: 8), panel: .vitaminD, value: 30, source: "Quest")
        store.saveLabValue(created)

        var redated = created
        redated.date = date(9, hour: 8)
        store.saveLabValue(redated)

        XCTAssertEqual(store.lastCreatedLabValue?.date, date(9, hour: 8))
    }

    func test_lastCreatedLabValue_deleted_isCleared() {
        let store = DataStore(seedSampleData: false)
        let created = LabValue(date: date(10, hour: 8), panel: .vitaminD, value: 30)
        store.saveLabValue(created)
        store.deleteLabValue(id: created.id)
        XCTAssertNil(store.lastCreatedLabValue)
    }

    func test_lastCreatedLabValue_profileReplaced_isCleared() {
        let store = DataStore(seedSampleData: false)
        store.saveLabValue(LabValue(date: date(10, hour: 8), panel: .vitaminD, value: 30, source: "Quest"))
        store.profile = .fresh
        XCTAssertNil(store.lastCreatedLabValue)
    }
}
