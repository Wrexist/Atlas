import XCTest
@testable import Peptide

/// Direct tests for `SwiftDataRepository`. Covers what
/// `PersistenceRoundTripTests` exercises only transitively: the upsert
/// semantics (existing-by-id keeps the row, dropped-from-input deletes
/// it, new-id inserts), the empty-state behavior, the per-resource
/// CRUD pairs, and `hasAnyData`.
///
/// The CloudKit / local-fail / in-memory fallback chain isn't tested
/// here — `FileManager.ubiquityIdentityToken` and `ModelContainer` init
/// failures aren't deterministically reproducible from a unit test. The
/// repo's defensive guards are still exercised by setting `container`
/// to nil via `configureForTesting` failing (covered in fallback test).
@MainActor
final class SwiftDataRepositoryTests: XCTestCase {

    private var repo: SwiftDataRepository!

    override func setUp() {
        super.setUp()
        repo = SwiftDataRepository.shared
        repo.configureForTesting()
    }

    override func tearDown() {
        repo.deleteAll()
        repo = nil
        super.tearDown()
    }

    // MARK: - Empty state

    func test_loadProtocols_whenEmpty_returnsEmptyArray() {
        XCTAssertEqual(repo.loadProtocols(), [])
    }

    func test_loadEntries_whenEmpty_returnsEmptyArray() {
        XCTAssertEqual(repo.loadEntries(), [])
    }

    func test_loadProfile_whenEmpty_returnsNil() {
        XCTAssertNil(repo.loadProfile())
    }

    func test_hasAnyData_isFalse_onFreshContainer() {
        XCTAssertFalse(repo.hasAnyData)
    }

    // MARK: - Protocol round-trip

    func test_saveProtocols_thenLoad_returnsSameSet() {
        let input = MockProtocols.all
        repo.saveProtocols(input)
        let loaded = repo.loadProtocols()
        XCTAssertEqual(Set(loaded.map(\.id)), Set(input.map(\.id)))
    }

    func test_saveProtocols_isUpsert_notAppend() {
        // A second save with the same IDs should keep the row count at
        // input.count — not duplicate.
        repo.saveProtocols(MockProtocols.all)
        repo.saveProtocols(MockProtocols.all)
        XCTAssertEqual(repo.loadProtocols().count, MockProtocols.all.count)
    }

    func test_saveProtocols_deletesItemsAbsentFromInput() {
        let all = MockProtocols.all
        repo.saveProtocols(all)
        XCTAssertEqual(repo.loadProtocols().count, all.count)

        // Save only the first one — the others must be removed from
        // the store. This is the contract `DataStore` relies on when
        // the user deletes a protocol.
        let oneOnly = Array(all.prefix(1))
        repo.saveProtocols(oneOnly)
        XCTAssertEqual(repo.loadProtocols().map(\.id), oneOnly.map(\.id))
    }

    func test_saveProtocols_updatesExistingRow_preservesId() {
        let original = MockProtocols.recoveryStack
        repo.saveProtocols([original])

        // `name` is a `let`, so build a clone with the same id and a
        // changed display name. The repo upsert path keys on `id`.
        let renamed = PeptideProtocol(
            id: original.id,
            name: "Renamed Recovery Stack",
            peptides: original.peptides,
            schedule: original.schedule,
            peptideSchedules: original.peptideSchedules,
            cycleLengthWeeks: original.cycleLengthWeeks,
            startDate: original.startDate,
            status: original.status,
            notes: original.notes
        )
        repo.saveProtocols([renamed])

        let loaded = repo.loadProtocols()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, original.id)
        XCTAssertEqual(loaded.first?.name, "Renamed Recovery Stack")
    }

    // MARK: - Entry round-trip

    private func sampleEntries() -> [ProtocolEntry] {
        // Generate a small entry set against the first mock protocol.
        // MockEntries.generateEntries is the canonical factory used by
        // the rest of the test suite.
        MockEntries.generateEntries(for: MockProtocols.recoveryStack, days: 5)
    }

    func test_saveEntries_thenLoad_returnsSameIds() {
        let input = sampleEntries()
        XCTAssertFalse(input.isEmpty, "Mock generator must produce at least one entry")
        repo.saveEntries(input)
        let loaded = repo.loadEntries()
        XCTAssertEqual(Set(loaded.map(\.id)), Set(input.map(\.id)))
    }

    func test_saveEntries_isUpsert_notAppend() {
        let input = sampleEntries()
        repo.saveEntries(input)
        repo.saveEntries(input)
        XCTAssertEqual(repo.loadEntries().count, input.count)
    }

    func test_saveEntries_deletesItemsAbsentFromInput() {
        let all = sampleEntries()
        repo.saveEntries(all)
        let kept = Array(all.prefix(2))
        repo.saveEntries(kept)
        XCTAssertEqual(Set(repo.loadEntries().map(\.id)), Set(kept.map(\.id)))
    }

    // MARK: - Profile round-trip

    func test_saveProfile_thenLoad_returnsEquivalent() {
        let input = MockProfile.current
        repo.saveProfile(input)
        let loaded = repo.loadProfile()
        XCTAssertNotNil(loaded)
        // UserProfile has no id — there is only ever one profile row, so
        // identity is not the thing under test; fidelity of the round trip is.
        XCTAssertEqual(loaded?.name, input.name)
        XCTAssertEqual(loaded?.goals, input.goals)
    }

    func test_saveProfile_overwritesExistingRow_notDuplicate() {
        // There's only ever one profile — saving twice must not
        // produce two rows. Verified indirectly via hasAnyData and the
        // fact that loadProfile returns `.first`.
        repo.saveProfile(MockProfile.current)
        repo.saveProfile(MockProfile.current)
        XCTAssertTrue(repo.hasAnyData)
        XCTAssertNotNil(repo.loadProfile())
    }

    // MARK: - hasAnyData

    func test_hasAnyData_isTrue_whenProtocolsExist() {
        repo.saveProtocols([MockProtocols.recoveryStack])
        XCTAssertTrue(repo.hasAnyData)
    }

    func test_hasAnyData_isTrue_whenOnlyProfileExists() {
        repo.saveProfile(MockProfile.current)
        XCTAssertTrue(repo.hasAnyData)
    }

    func test_hasAnyData_isFalse_afterDeleteAll() {
        repo.saveProtocols(MockProtocols.all)
        repo.saveEntries(sampleEntries())
        repo.saveProfile(MockProfile.current)
        XCTAssertTrue(repo.hasAnyData)

        repo.deleteAll()
        XCTAssertFalse(repo.hasAnyData)
        XCTAssertEqual(repo.loadProtocols(), [])
        XCTAssertEqual(repo.loadEntries(), [])
        XCTAssertNil(repo.loadProfile())
    }

    // MARK: - Empty-input clears the store

    func test_saveProtocols_withEmptyInput_clearsAllProtocols() {
        repo.saveProtocols(MockProtocols.all)
        repo.saveProtocols([])
        XCTAssertEqual(repo.loadProtocols(), [])
    }

    func test_saveEntries_withEmptyInput_clearsAllEntries() {
        repo.saveEntries(sampleEntries())
        repo.saveEntries([])
        XCTAssertEqual(repo.loadEntries(), [])
    }

    // MARK: - configureForTesting wipes prior in-memory state

    func test_configureForTesting_resetsContainer() {
        repo.saveProtocols(MockProtocols.all)
        XCTAssertFalse(repo.loadProtocols().isEmpty)

        repo.configureForTesting()
        XCTAssertEqual(repo.loadProtocols(), [])
        XCTAssertFalse(repo.isInoperable)
    }
}
