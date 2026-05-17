import XCTest
@testable import Peptide

@MainActor
final class BackupSnapshotServiceTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        SwiftDataRepository.shared.configureForTesting()
        // Clear any pre-existing snapshots from prior runs so the
        // prune assertions are deterministic.
        for info in BackupSnapshotService.availableSnapshots() {
            try? FileManager.default.removeItem(at: info.url)
        }
    }

    func test_snapshotCurrentState_producesReadableFile() throws {
        let store = DataStore(seedSampleData: false)
        store.profile.name = "Alex"

        guard let url = BackupSnapshotService.snapshotCurrentState(dataStore: store) else {
            return XCTFail("Expected a snapshot URL")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AppBackup.self, from: data)
        XCTAssertEqual(decoded.profile.name, "Alex")
    }

    func test_availableSnapshots_sortsNewestFirst() async throws {
        let store = DataStore(seedSampleData: false)
        _ = BackupSnapshotService.snapshotCurrentState(dataStore: store)
        // Sleep a moment so timestamps differ on file system resolution.
        try await Task.sleep(for: .milliseconds(1100))
        store.profile.name = "Second"
        _ = BackupSnapshotService.snapshotCurrentState(dataStore: store)

        let snapshots = BackupSnapshotService.availableSnapshots()
        XCTAssertGreaterThanOrEqual(snapshots.count, 2)
        guard snapshots.count >= 2 else { return }
        XCTAssertGreaterThan(
            snapshots[0].createdAt,
            snapshots[1].createdAt,
            "availableSnapshots must surface newest first"
        )
    }

    func test_pruneRetainsAtMostMaxSnapshots() async throws {
        let store = DataStore(seedSampleData: false)
        // Produce maxSnapshots + 3 snapshots; pruning must trim the
        // oldest three. Each write needs distinct mtimes so sleep
        // for 1.1s between calls — slow test but the only way to
        // distinguish files on standard filesystem time resolution.
        let extra = 3
        for i in 0..<(BackupSnapshotService.maxSnapshots + extra) {
            store.profile.name = "snap-\(i)"
            _ = BackupSnapshotService.snapshotCurrentState(dataStore: store)
            try await Task.sleep(for: .milliseconds(1100))
        }
        let after = BackupSnapshotService.availableSnapshots()
        XCTAssertLessThanOrEqual(
            after.count,
            BackupSnapshotService.maxSnapshots,
            "Prune must cap at maxSnapshots"
        )
    }

    func test_read_returnsSnapshotBytes() throws {
        let store = DataStore(seedSampleData: false)
        guard let url = BackupSnapshotService.snapshotCurrentState(dataStore: store) else {
            return XCTFail("Expected a snapshot URL")
        }
        let info = BackupSnapshotService.Info(
            id: url.lastPathComponent,
            url: url,
            createdAt: Date(),
            sizeBytes: 0
        )
        let bytes = try BackupSnapshotService.read(info)
        XCTAssertFalse(bytes.isEmpty)
    }
}
