import XCTest
@testable import Peptide

@MainActor
final class MigrationServiceTests: XCTestCase {

    private let persistence = PersistenceService.shared
    private let repo = SwiftDataRepository.shared
    private let migration = MigrationService.shared

    override func setUp() {
        super.setUp()
        repo.configureForTesting()
        persistence.clearAll()
    }

    override func tearDown() {
        repo.deleteAll()
        persistence.clearAll()
        super.tearDown()
    }

    // MARK: - No-op paths

    func test_migration_whenNoJSONFiles_doesNothing() {
        migration.migrateIfNeeded()
        XCTAssertFalse(repo.hasAnyData, "Nothing to migrate → SwiftData should remain empty")
    }

    func test_migration_whenSwiftDataAlreadyHasData_skips() {
        // Pre-seed SwiftData so migration is skipped
        repo.saveProtocols(MockProtocols.all)

        // Also write JSON files that would be imported if migration ran
        persistence.saveProtocols(MockProtocols.all)

        migration.migrateIfNeeded()

        // Count should not have doubled (migration skipped)
        let loaded = repo.loadProtocols()
        XCTAssertEqual(loaded.count, MockProtocols.all.count)
    }

    // MARK: - Import

    func test_migration_importsProtocols() {
        persistence.saveProtocols(MockProtocols.all)

        migration.migrateIfNeeded()

        let imported = repo.loadProtocols()
        XCTAssertEqual(imported.count, MockProtocols.all.count)
        for original in MockProtocols.all {
            XCTAssertTrue(imported.contains(where: { $0.id == original.id }),
                          "Protocol \(original.name) should be imported")
        }
    }

    func test_migration_importsProfile() {
        let original = MockProfile.current
        persistence.saveProfile(original)

        migration.migrateIfNeeded()

        let imported = repo.loadProfile()
        XCTAssertNotNil(imported)
        XCTAssertEqual(imported?.name, original.name)
        XCTAssertEqual(imported?.goals, original.goals)
        XCTAssertEqual(imported?.healthConnected, original.healthConnected)
    }

    func test_migration_importsEntries() {
        let store = DataStore(seedSampleData: true)
        let entries = store.entries
        XCTAssertFalse(entries.isEmpty)

        // Write those entries to JSON (simulating legacy state)
        repo.deleteAll()              // clear SwiftData written by DataStore
        persistence.saveEntries(entries)
        persistence.saveProtocols(store.protocols)

        migration.migrateIfNeeded()

        let imported = repo.loadEntries()
        XCTAssertEqual(imported.count, entries.count)
    }

    // MARK: - Idempotency

    func test_migration_isIdempotent() {
        persistence.saveProtocols(MockProtocols.all)

        migration.migrateIfNeeded()
        migration.migrateIfNeeded()  // second call should be a no-op

        let imported = repo.loadProtocols()
        XCTAssertEqual(imported.count, MockProtocols.all.count,
                       "Running migration twice should not duplicate data")
    }

    func test_migration_archivesJSONFiles() {
        persistence.saveProtocols(MockProtocols.all)
        XCTAssertTrue(persistence.hasPersistedData, "JSON files should exist before migration")

        migration.migrateIfNeeded()

        XCTAssertFalse(persistence.hasPersistedData,
                       "JSON files should be renamed after migration")
    }

    /// If protocols.json is corrupt at migration time, leave all source files
    /// in place so the next launch can retry rather than silently archiving
    /// (which would lose the user's data permanently).
    func test_migration_partialFailure_leavesJSONFilesIntact() throws {
        // Write valid profile + entries, but corrupt the protocols.json
        let store = DataStore(seedSampleData: true)
        let entries = store.entries
        let profile = store.profile
        repo.deleteAll()                         // clear SwiftData written by DataStore
        persistence.saveEntries(entries)
        persistence.saveProfile(profile)

        // Corrupt protocols.json
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let protocolsURL = docs.appendingPathComponent("protocols.json")
        try Data("{ not valid json".utf8).write(to: protocolsURL, options: .atomic)
        XCTAssertTrue(FileManager.default.fileExists(atPath: protocolsURL.path))

        migration.migrateIfNeeded()

        // Source files should still be there for retry — we did NOT archive
        XCTAssertTrue(FileManager.default.fileExists(atPath: protocolsURL.path),
                      "Corrupt protocols.json must not be archived")
        XCTAssertTrue(persistence.hasPersistedData,
                      "Other JSON files must also remain for next-launch retry")
    }

    // MARK: - Verification (audit Data Integrity 04, Phase 4)

    /// A commit failure during import must neither archive the source
    /// files nor leave a half-imported store behind — the next launch
    /// retries from the intact JSON.
    func test_migration_commitFailure_rollsBackAndLeavesJSONForRetry() {
        persistence.saveProtocols(MockProtocols.all)
        repo.forceCommitFailureForTesting = true

        migration.migrateIfNeeded()

        XCTAssertTrue(persistence.hasPersistedData,
                      "Source JSON must survive a failed import")
        XCTAssertFalse(repo.hasAnyData,
                       "Partial import must be rolled back so the retry gate stays open")

        // Retry succeeds once the store recovers.
        repo.forceCommitFailureForTesting = false
        migration.migrateIfNeeded()
        XCTAssertEqual(repo.loadProtocols().count, MockProtocols.all.count)
        XCTAssertFalse(persistence.hasPersistedData,
                       "Verified retry should archive the source files")
    }

    func test_migrationVerification_detectsMissingProtocols() {
        let all = MockProtocols.all
        repo.saveProtocols([all[0]])
        XCTAssertNotNil(
            migration.verificationFailure(protocols: all, entries: nil, profile: nil),
            "An import that landed fewer protocols than the source must fail verification"
        )
    }

    func test_migrationVerification_detectsIDMismatch() {
        // Same count (one row each side) but different identity.
        let stored = MockProtocols.all[0]
        let expected = MockProtocols.all[1]
        repo.saveProtocols([stored])
        XCTAssertNotNil(
            migration.verificationFailure(protocols: [expected], entries: nil, profile: nil),
            "Same count but different identity must fail verification"
        )
    }

    func test_migrationVerification_passesOnFaithfulImport() {
        repo.saveProtocols(MockProtocols.all)
        XCTAssertNil(
            migration.verificationFailure(protocols: MockProtocols.all, entries: nil, profile: nil)
        )
    }

    // MARK: - Legacy archive retention

    func test_archivedLegacyFiles_expireAfterRetentionWindow() throws {
        persistence.saveProtocols(MockProtocols.all)
        migration.migrateIfNeeded()
        XCTAssertTrue(persistence.hasArchivedLegacyFiles)

        // Inside the window: retained.
        persistence.cleanUpExpiredArchivedLegacyFiles()
        XCTAssertTrue(persistence.hasArchivedLegacyFiles,
                      "A fresh archive must survive cleanup")

        // Past the window: removed.
        let pastCutoff = Date().addingTimeInterval(
            TimeInterval(PersistenceService.archivedLegacyRetentionDays + 1) * 86_400
        )
        persistence.cleanUpExpiredArchivedLegacyFiles(now: pastCutoff)
        XCTAssertFalse(persistence.hasArchivedLegacyFiles,
                       "Archives must not accumulate past the retention window")
    }

    func test_clearAll_removesArchivedLegacyFiles() {
        persistence.saveProtocols(MockProtocols.all)
        migration.migrateIfNeeded()
        XCTAssertTrue(persistence.hasArchivedLegacyFiles)

        persistence.clearAll()

        XCTAssertFalse(persistence.hasArchivedLegacyFiles,
                       "Account deletion / data reset must erase the archived legacy files too")
    }

    // MARK: - SwiftData round-trip

    func test_swiftData_protocolRoundTrip_preservesAllFields() {
        let original = MockProtocols.all.first!
        repo.saveProtocols([original])

        let loaded = repo.loadProtocols()
        let reloaded = loaded.first!

        XCTAssertEqual(reloaded.id,               original.id)
        XCTAssertEqual(reloaded.name,             original.name)
        XCTAssertEqual(reloaded.cycleLengthWeeks, original.cycleLengthWeeks)
        XCTAssertEqual(reloaded.status,           original.status)
        XCTAssertEqual(reloaded.notes,            original.notes)
        XCTAssertEqual(reloaded.peptides.count,   original.peptides.count)
        XCTAssertEqual(reloaded.schedule.daysOfWeek, original.schedule.daysOfWeek)
        XCTAssertEqual(reloaded.schedule.preferredTimes, original.schedule.preferredTimes)
    }

    func test_swiftData_entryRoundTrip_preservesOptionals() {
        let entry = ProtocolEntry(
            id: UUID(),
            protocolId: UUID(),
            peptide: MockPeptides.bpc157,
            date: Date(),
            dose: "500 mcg",
            notes: "Test note",
            completed: true,
            actualDose: "480 mcg",
            actualTime: Date(),
            injectionSite: "Left Deltoid"
        )
        repo.saveEntries([entry])

        let loaded = repo.loadEntries().first!
        XCTAssertEqual(loaded.id,            entry.id)
        XCTAssertEqual(loaded.completed,     entry.completed)
        XCTAssertEqual(loaded.actualDose,    entry.actualDose)
        XCTAssertEqual(loaded.injectionSite, entry.injectionSite)
        XCTAssertNotNil(loaded.actualTime)
    }
}
