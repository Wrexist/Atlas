import SwiftData
import XCTest
@testable import Peptide

/// Guideline 5.1.3(ii): weekly recaps carry HRV, so they must persist
/// only on-device — never in the CloudKit-mirrored SwiftData store.
/// Also pins the one-time reset of `weeklySummaryEnabled` for profiles
/// saved while the recap defaulted to on.
@MainActor
final class WeeklySummaryLocalStoreTests: XCTestCase {

    private var repo: SwiftDataRepository!
    private var fileURL: URL!
    private var defaults: UserDefaults!
    private let suiteName = "WeeklySummaryLocalStoreTests"

    override func setUp() {
        super.setUp()
        repo = SwiftDataRepository.shared
        repo.configureForTesting()
        fileURL = FileManager.default.temporaryDirectory
            .appending(path: "WeeklySummaryLocalStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "summaries.json", directoryHint: .notDirectory)
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        repo.deleteAll()
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        defaults.removePersistentDomain(forName: suiteName)
        WeeklySummaryOptInMigration.markCompleted()
        repo = nil
        super.tearDown()
    }

    // MARK: - Local store

    func test_load_withNoFile_returnsNil() {
        XCTAssertNil(WeeklySummaryLocalStore(fileURL: fileURL).load())
    }

    func test_save_thenLoadFromNewInstance_roundTrips() {
        let summaries = [summary().weekStart: summary()]
        WeeklySummaryLocalStore(fileURL: fileURL).save(summaries)
        XCTAssertEqual(WeeklySummaryLocalStore(fileURL: fileURL).load(), summaries)
    }

    func test_deleteAll_removesCache() {
        let store = WeeklySummaryLocalStore(fileURL: fileURL)
        store.save([summary().weekStart: summary()])
        store.deleteAll()
        XCTAssertNil(WeeklySummaryLocalStore(fileURL: fileURL).load())
    }

    // MARK: - Repository

    func test_saveProfile_neverWritesSummariesToSyncedRow_butLoadsThemBack() throws {
        var profile = UserProfile.fresh
        profile.weeklySummaries = [summary().weekStart: summary()]
        repo.saveProfile(profile)

        XCTAssertNil(try storedRow().summariesData)
        XCTAssertEqual(repo.loadProfile()?.weeklySummaries, profile.weeklySummaries)
    }

    func test_loadProfile_movesLegacySyncedSummariesOnDevice_andClearsSyncedColumn() throws {
        repo.saveProfile(.fresh)
        let legacy = [summary().weekStart: summary()]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let row = try storedRow()
        row.summariesData = try encoder.encode(legacy)
        try XCTUnwrap(repo.contextForTesting).save()

        XCTAssertEqual(repo.loadProfile()?.weeklySummaries, legacy)
        XCTAssertNil(try storedRow().summariesData)
        XCTAssertEqual(repo.loadProfile()?.weeklySummaries, legacy)
    }

    func test_loadProfile_firstLoadAfterUpgrade_persistsOptInReset() throws {
        var profile = UserProfile.fresh
        profile.weeklySummaryEnabled = true
        repo.saveProfile(profile)
        UserDefaults.standard.removeObject(forKey: WeeklySummaryOptInMigration.defaultsKey)

        XCTAssertEqual(repo.loadProfile()?.weeklySummaryEnabled, false)
        XCTAssertEqual(repo.loadProfile()?.weeklySummaryEnabled, false)
    }

    // MARK: - Opt-in migration

    func test_optInMigration_existingProfileEnabled_turnsOffOnce() {
        var profile = UserProfile.fresh
        profile.weeklySummaryEnabled = true

        XCTAssertTrue(WeeklySummaryOptInMigration.apply(to: &profile, defaults: defaults))
        XCTAssertFalse(profile.weeklySummaryEnabled)

        profile.weeklySummaryEnabled = true
        XCTAssertFalse(WeeklySummaryOptInMigration.apply(to: &profile, defaults: defaults))
        XCTAssertTrue(profile.weeklySummaryEnabled)
    }

    func test_optInMigration_alreadyOff_reportsNoChange_andMarksDone() {
        var profile = UserProfile.fresh

        XCTAssertFalse(WeeklySummaryOptInMigration.apply(to: &profile, defaults: defaults))
        XCTAssertTrue(defaults.bool(forKey: WeeklySummaryOptInMigration.defaultsKey))
    }

    func test_optInMigration_afterMarkCompleted_leavesOptInAlone() {
        WeeklySummaryOptInMigration.markCompleted(in: defaults)
        var profile = UserProfile.fresh
        profile.weeklySummaryEnabled = true

        XCTAssertFalse(WeeklySummaryOptInMigration.apply(to: &profile, defaults: defaults))
        XCTAssertTrue(profile.weeklySummaryEnabled)
    }

    // MARK: - Helpers

    private func summary() -> WeeklySummary {
        WeeklySummary(
            weekStart: "2026-01-05",
            text: "HRV up 4 ms on the week.",
            keyStats: WeeklySummary.KeyStats(
                compliancePct: 0.9,
                dosesCompleted: 9,
                dosesTotal: 10,
                currentStreak: 5,
                avgCheckInScore: nil,
                avgCalories: nil,
                hrvDelta: 4
            ),
            kind: .ai,
            generatedAt: Date(timeIntervalSince1970: 1_767_600_000),
            sourceFingerprint: "abc"
        )
    }

    private func storedRow() throws -> StoredProfile {
        try XCTUnwrap(
            try XCTUnwrap(repo.contextForTesting).fetch(FetchDescriptor<StoredProfile>()).first
        )
    }
}
