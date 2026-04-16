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
