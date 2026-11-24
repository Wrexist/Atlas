import XCTest
import SwiftData
@testable import Peptide

/// Kept apart from BackupImportServiceTests: this file needs SwiftData for
/// FetchDescriptor, and SwiftData's own `DataStore` protocol makes the app's
/// `DataStore` ambiguous in type position there.
@MainActor
final class BackupHealthWeightImportTests: XCTestCase {

    func test_replace_backupWithHealthWeighIns_keepsThemOffTheSyncedColumn() throws {
        SwiftDataRepository.shared.configureForTesting()
        let dataStore = DataStore(seedSampleData: false)
        let repo = SwiftDataRepository.shared
        let scale = WeightEntry(date: Date(timeIntervalSince1970: 1_700_000_000), kg: 81)
        let logged = WeightEntry(date: Date(timeIntervalSince1970: 1_700_086_400), kg: 80.5)
        var backupProfile = UserProfile.fresh
        backupProfile.weightHistory = [scale, logged]
        let backup = AppBackup(
            exportDate: Date(),
            version: "2.0",
            protocols: [],
            entries: [],
            profile: backupProfile,
            healthWeightIDs: [scale.id]
        )

        _ = try BackupImportService.apply(backup, strategy: .replace, into: dataStore)

        XCTAssertTrue(repo.isHealthWeightImport(scale.id))
        XCTAssertFalse(repo.isHealthWeightImport(logged.id))
        XCTAssertEqual(dataStore.profile.weightHistory.map(\.id), [scale.id, logged.id])
        let row = try XCTUnwrap(XCTUnwrap(repo.contextForTesting).fetch(FetchDescriptor<StoredProfile>()).first)
        let synced = String(decoding: try XCTUnwrap(row.weightHistoryData), as: UTF8.self)
        XCTAssertFalse(synced.contains(scale.id.uuidString))
        XCTAssertTrue(synced.contains(logged.id.uuidString))
    }
}
