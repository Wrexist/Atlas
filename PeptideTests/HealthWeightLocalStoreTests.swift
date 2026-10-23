import XCTest
@testable import Peptide

/// Guideline 5.1.3(ii): weigh-ins read from Apple Health only reach the
/// profile once this device-local store has kept them, so a failed
/// write can't leave them in the CloudKit-mirrored weight column.
@MainActor
final class HealthWeightLocalStoreTests: XCTestCase {

    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appending(path: "HealthWeightLocalStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "imported.json", directoryHint: .notDirectory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        super.tearDown()
    }

    func test_record_withWritableFile_persistsAndReturnsTrue() {
        let entry = WeightEntry(date: Date(), kg: 80)

        XCTAssertTrue(HealthWeightLocalStore(fileURL: fileURL).record([entry]))
        XCTAssertEqual(HealthWeightLocalStore(fileURL: fileURL).entries.map(\.id), [entry.id])
    }

    func test_record_withUnreadableFile_returnsFalseAndLeavesFileAlone() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: fileURL)

        XCTAssertFalse(HealthWeightLocalStore(fileURL: fileURL).record([WeightEntry(date: Date(), kg: 80)]))
        XCTAssertEqual(try Data(contentsOf: fileURL), corrupt)
    }

    func test_entries_afterAFailedRead_retryOnceTheFileIsReadable() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: fileURL)
        let store = HealthWeightLocalStore(fileURL: fileURL)
        XCTAssertTrue(store.entries.isEmpty)

        let entry = WeightEntry(date: Date(), kg: 80)
        try FileManager.default.removeItem(at: fileURL)
        XCTAssertTrue(HealthWeightLocalStore(fileURL: fileURL).record([entry]))

        XCTAssertEqual(store.entries.map(\.id), [entry.id])
        XCTAssertTrue(store.record([WeightEntry(date: Date(), kg: 81)]))
    }

    func test_dismissIDs_forUnrecordedSamples_marksThemDismissed() {
        let legacySample = UUID()

        HealthWeightLocalStore(fileURL: fileURL).dismiss(ids: [legacySample])

        XCTAssertEqual(HealthWeightLocalStore(fileURL: fileURL).dismissedIDs, [legacySample])
    }
}
