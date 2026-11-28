import XCTest
@testable import Peptide

@MainActor
final class RestorePointServiceTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        SwiftDataRepository.shared.configureForTesting()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RestorePointServiceTests-\(UUID().uuidString)", isDirectory: true)
        RestorePointService.directoryOverrideForTesting = directory
    }

    override func tearDown() async throws {
        RestorePointService.deleteAll()
        RestorePointService.directoryOverrideForTesting = nil
        try await super.tearDown()
    }

    func test_writeIfDue_noPointYet_writesARestorableBackup() async throws {
        let store = DataStore(seedSampleData: false)
        store.profile.name = "Isac"

        await RestorePointService.writeIfDue(dataStore: store)

        let point = try XCTUnwrap(RestorePointService.restorePoints().first)
        let (backup, _) = try BackupImportService.validate(BackupSnapshotService.read(point))
        XCTAssertEqual(backup.profile.name, "Isac")
    }

    func test_writeIfDue_pointFromAnHourAgo_writesNothing() async {
        let store = DataStore(seedSampleData: false)
        let now = Date()
        await RestorePointService.writeIfDue(dataStore: store, now: now.addingTimeInterval(-3600))

        await RestorePointService.writeIfDue(dataStore: store, now: now)

        XCTAssertEqual(RestorePointService.restorePoints().count, 1)
    }

    func test_writeIfDue_ephemeralStore_writesNothing() async {
        let store = DataStore(seedSampleData: false)
        store.isEphemeral = true

        await RestorePointService.writeIfDue(dataStore: store)

        XCTAssertTrue(RestorePointService.restorePoints().isEmpty)
    }

    func test_writeIfDue_manyDays_prunesToTheRetentionLimit() async {
        let store = DataStore(seedSampleData: false)
        let start = Date()
        for day in (0..<30).reversed() {
            await RestorePointService.writeIfDue(dataStore: store, now: start.addingTimeInterval(-Double(day) * 86_400))
        }

        let points = RestorePointService.restorePoints()
        XCTAssertLessThanOrEqual(points.count, RestorePointEngine.dailyPointsKept + RestorePointEngine.weeklyPointsKept)
        XCTAssertEqual(points.first?.createdAt.timeIntervalSince1970.rounded(.down), start.timeIntervalSince1970.rounded(.down))
    }

    func test_createdAt_readsTheTimeFromTheFileName() {
        XCTAssertEqual(
            RestorePointService.createdAt(fromFileName: "atlas-restore-point-1796126400.json"),
            Date(timeIntervalSince1970: 1_796_126_400)
        )
        XCTAssertNil(RestorePointService.createdAt(fromFileName: "notes.json"))
    }
}
