import XCTest
@testable import Peptide

/// The device-only stores an Atlas backup now carries: merge rules, the
/// older-backup shape, and a store taking a restored copy.
@MainActor
final class DeviceLocalBackupTests: XCTestCase {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    /// 2025-10-09 00:00 UTC.
    private let day = Date(timeIntervalSince1970: 1_759_968_000)

    func test_merged_merge_keepsCurrentOnConflictAndAddsBackupOnly() {
        let mine = HealthJournalEntry(day: day, mood: .good, note: "Mine", calendar: utc)
        let theirsSameDay = HealthJournalEntry(day: day, mood: .low, note: "Backup", calendar: utc)
        let backupOnly = HealthJournalEntry(day: day.addingTimeInterval(-86_400), mood: .okay, calendar: utc)

        let merged = DeviceLocalBackup.merged([mine], [theirsSameDay, backupOnly], replacing: false, by: \.dayKey)

        XCTAssertEqual(merged.map(\.note), ["Mine", ""])
    }

    func test_merged_replace_takesTheBackup() {
        XCTAssertEqual(DeviceLocalBackup.merged(Set(["milk"]), Set(["eggs"]), replacing: true), ["eggs"])
        XCTAssertEqual(DeviceLocalBackup.merged(Set(["milk"]), Set(["eggs"]), replacing: false), ["milk", "eggs"])
        XCTAssertEqual(DeviceLocalBackup.merged(["a": "run"], ["a": "walk", "b": "swim"], replacing: false), ["a": "run", "b": "swim"])
    }

    func test_appBackup_withoutDeviceLocalKey_decodesNil() throws {
        let backup = AppBackup(exportDate: day, version: "2.0", protocols: [], entries: [], profile: .fresh)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(AppBackup.self, from: encoder.encode(backup))

        XCTAssertNil(decoded.deviceLocal)
    }

    func test_appBackup_roundTrip_keepsDeviceLocalStores() throws {
        let batch = PrepBoxBatch(id: UUID(), recipeID: "chili", cookedAt: day, frozenAt: nil, count: 3)
        let local = DeviceLocalBackup(
            healthJournal: [HealthJournalEntry(day: day, mood: .great, note: "Slept well", calendar: utc)],
            pantryKeys: ["rice"],
            prepBoxes: [batch],
            prepEatenBoxes: [UUID(): batch],
            trainingLocation: .home,
            workoutTypeOverrides: [UUID().uuidString: "running"]
        )
        let backup = AppBackup(exportDate: day, version: "2.0", protocols: [], entries: [], profile: .fresh, deviceLocal: local)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try XCTUnwrap(decoder.decode(AppBackup.self, from: encoder.encode(backup)).deviceLocal)

        XCTAssertEqual(decoded.healthJournal, local.healthJournal)
        XCTAssertEqual(decoded.pantryKeys, ["rice"])
        XCTAssertEqual(decoded.prepBoxes, [batch])
        XCTAssertEqual(decoded.prepEatenBoxes, local.prepEatenBoxes)
        XCTAssertEqual(decoded.trainingLocation, .home)
        XCTAssertEqual(decoded.workoutTypeOverrides, local.workoutTypeOverrides)
        XCTAssertNil(decoded.fridgeProducts)
    }

    func test_healthJournalRestore_persistsNewestFirst() {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = HealthJournalStore(fileURL: fileURL)
        let older = HealthJournalEntry(day: day.addingTimeInterval(-86_400), mood: .low, calendar: utc)
        let newer = HealthJournalEntry(day: day, mood: .good, calendar: utc)

        store.restore([older, newer])

        XCTAssertEqual(HealthJournalStore(fileURL: fileURL).entries.map(\.id), [newer.id, older.id])
    }
}
