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

    /// Written in Tokyo, read back the same calendar day in New York: the
    /// stored midnight is a different instant there, but the same day.
    func test_save_afterTimeZoneChange_findsAndReplacesThatDay() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let store = HealthJournalStore(fileURL: fileURL)
        // 2025-10-09 09:00 in Tokyo.
        let inTokyo = tokyo.date(from: DateComponents(year: 2025, month: 10, day: 9, hour: 9))!
        store.save(mood: .low, note: "Jet lag", on: inTokyo, calendar: tokyo)
        // 2025-10-09 20:00 in New York.
        let inNewYork = newYork.date(from: DateComponents(year: 2025, month: 10, day: 9, hour: 20))!

        XCTAssertEqual(store.entry(on: inNewYork, calendar: newYork)?.note, "Jet lag")

        store.save(mood: .good, note: "Settled", on: inNewYork, calendar: newYork)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.mood, .good)
    }

    func test_load_entryWithoutDayKey_derivesItFromDay() throws {
        let day = utc.startOfDay(for: morning)
        let legacy = #"[{"id":"\#(UUID().uuidString)","day":\#(day.timeIntervalSinceReferenceDate),"mood":4,"note":"Old"}]"#
        try Data(legacy.utf8).write(to: fileURL)

        let entry = try XCTUnwrap(HealthJournalStore(fileURL: fileURL).entries.first)

        XCTAssertEqual(entry.dayKey, HealthJournalEntry.dayKey(for: day, calendar: .current))
        XCTAssertEqual(entry.note, "Old")
    }

    func test_deleteAll_removesEntriesAndFile() {
        let store = HealthJournalStore(fileURL: fileURL)
        store.save(mood: .okay, note: "", on: morning, calendar: utc)
        store.deleteAll()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(HealthJournalStore(fileURL: fileURL).entries.isEmpty)
    }
}
