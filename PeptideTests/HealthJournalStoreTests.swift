import XCTest
@testable import Peptide

@MainActor
final class HealthJournalStoreTests: XCTestCase {

    private var fileURL: URL!
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    /// 2025-10-09 08:00 UTC.
    private let morning = Date(timeIntervalSince1970: 1_759_996_800)

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        super.tearDown()
    }

    func test_save_sameDayTwice_replacesThatDay() {
        let store = HealthJournalStore(fileURL: fileURL)
        store.save(mood: .low, note: "Tired", on: morning, calendar: utc)
        store.save(mood: .good, note: "  Better after lunch ", on: morning.addingTimeInterval(6 * 3600), calendar: utc)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.mood, .good)
        XCTAssertEqual(store.entries.first?.note, "Better after lunch")
    }

    func test_save_differentDays_keepsNewestFirst() {
        let store = HealthJournalStore(fileURL: fileURL)
        store.save(mood: .okay, note: "", on: morning, calendar: utc)
        store.save(mood: .great, note: "", on: morning.addingTimeInterval(-86_400), calendar: utc)

        XCTAssertEqual(store.entries.map(\.mood), [.okay, .great])
    }

    func test_entries_surviveRelaunch() {
        HealthJournalStore(fileURL: fileURL).save(mood: .great, note: "PR day", on: morning, calendar: utc)

        let reopened = HealthJournalStore(fileURL: fileURL)
        XCTAssertEqual(reopened.entry(on: morning, calendar: utc)?.note, "PR day")
    }

    func test_deleteAll_removesEntriesAndFile() {
        let store = HealthJournalStore(fileURL: fileURL)
        store.save(mood: .okay, note: "", on: morning, calendar: utc)
        store.deleteAll()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(HealthJournalStore(fileURL: fileURL).entries.isEmpty)
    }
}
