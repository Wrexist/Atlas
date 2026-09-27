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

    func test_availableSnapshots_sortsNewestFirst() throws {
        let store = DataStore(seedSampleData: false)
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = older.addingTimeInterval(60)

        let olderURL = try XCTUnwrap(
            BackupSnapshotService.snapshotCurrentState(dataStore: store, now: older)
        )
        store.profile.name = "Second"
        let newerURL = try XCTUnwrap(
            BackupSnapshotService.snapshotCurrentState(dataStore: store, now: newer)
        )
        // Ordering is by modification date, so pin both rather than rely
        // on the file system's clock resolution.
        try setModificationDate(older, of: olderURL)
        try setModificationDate(newer, of: newerURL)

        let snapshots = BackupSnapshotService.availableSnapshots()
        XCTAssertEqual(
            snapshots.map(\.id),
            [newerURL.lastPathComponent, olderURL.lastPathComponent],
            "availableSnapshots must surface newest first"
        )
    }

    func test_pruneRetainsAtMostMaxSnapshots() throws {
        let store = DataStore(seedSampleData: false)
        // Produce maxSnapshots + 3 snapshots; pruning must trim the
        // oldest three. Each write gets a distinct injected instant (the
        // file name has one-second resolution) and a matching pinned
        // modification date, so the prune order is fixed without sleeping.
        let extra = 3
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var urls: [URL] = []
        for i in 0..<(BackupSnapshotService.maxSnapshots + extra) {
            store.profile.name = "snap-\(i)"
            let instant = base.addingTimeInterval(TimeInterval(i * 60))
            let url = try XCTUnwrap(
                BackupSnapshotService.snapshotCurrentState(dataStore: store, now: instant)
            )
            try setModificationDate(instant, of: url)
            urls.append(url)
        }

        let after = BackupSnapshotService.availableSnapshots()
        XCTAssertEqual(after.count, BackupSnapshotService.maxSnapshots, "Prune must cap at maxSnapshots")
        XCTAssertEqual(
            Set(after.map(\.id)),
            Set(urls.suffix(BackupSnapshotService.maxSnapshots).map(\.lastPathComponent)),
            "Prune must drop the oldest snapshots and keep the newest"
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

    private func setModificationDate(_ date: Date, of url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}
