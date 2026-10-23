import SwiftData
import XCTest
@testable import Peptide

/// A379: dose rows persist a peptide snapshot and resolve the full
/// record by id at load, while rows written before the change (full
/// records in the same column) keep loading unchanged.
@MainActor
final class EntryPeptideSnapshotTests: XCTestCase {

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

    private let full = MockPeptides.bpc157

    private let custom = Peptide(
        name: "My Blend",
        abbreviation: "MB-1",
        category: .recovery,
        description: "A custom peptide the user typed in.",
        benefits: ["Recovery"],
        dosageRange: "100 mcg",
        frequency: "Daily",
        halfLife: "2 hours",
        adminRoute: "Subcutaneous",
        researchLinks: [],
        imageSystemName: "cross.vial"
    )

    private func entry(for peptide: Peptide) -> ProtocolEntry {
        ProtocolEntry(
            id: UUID(),
            protocolId: UUID(),
            peptide: peptide,
            date: Date(),
            dose: "250 mcg",
            notes: "",
            completed: false,
            actualDose: nil,
            actualTime: nil,
            injectionSite: nil
        )
    }

    private func insertLegacyRow(for entry: ProtocolEntry) throws -> StoredEntry {
        let context = try XCTUnwrap(repo.contextForTesting)
        let row = StoredEntry(
            id: entry.id, protocolId: entry.protocolId, date: entry.date,
            dose: entry.dose, notes: entry.notes, completed: entry.completed,
            actualDose: nil, actualTime: nil, injectionSite: nil,
            peptideData: try JSONEncoder().encode(entry.peptide)
        )
        context.insert(row)
        try context.save()
        return row
    }

    // MARK: - New writes

    func test_newEntry_storesSnapshotSmallerThanFullRecord() throws {
        let stored = try StoredEntry.make(from: entry(for: full))
        XCTAssertLessThan(stored.peptideData.count, try JSONEncoder().encode(full).count)
    }

    func test_newEntry_roundTrips_resolvingFullRecordById() throws {
        let original = entry(for: full)
        repo.upsertEntries([original])

        let loaded = try XCTUnwrap(
            repo.loadEntries(resolvingFrom: EntryPeptideSnapshot.index([full])).first
        )
        XCTAssertEqual(loaded.id, original.id)
        XCTAssertEqual(loaded.peptide.id, full.id)
        XCTAssertEqual(loaded.peptide.description, full.description)
        XCTAssertEqual(loaded.peptide.researchLinks.count, full.researchLinks.count)
    }

    func test_unknownPeptideId_fallsBackToSnapshot() throws {
        repo.upsertEntries([entry(for: full)])

        let loaded = try XCTUnwrap(
            repo.loadEntries(resolvingFrom: EntryPeptideSnapshot.index([custom])).first
        )
        XCTAssertEqual(loaded.peptide.id, full.id)
        XCTAssertEqual(loaded.peptide.name, full.name)
        XCTAssertEqual(loaded.peptide.abbreviation, full.abbreviation)
        XCTAssertEqual(loaded.peptide.category, full.category)
        XCTAssertEqual(loaded.peptide.imageSystemName, full.imageSystemName)
        XCTAssertEqual(loaded.peptide.adminRoute, full.adminRoute)
        XCTAssertTrue(loaded.peptide.description.isEmpty)
    }

    func test_customPeptide_resolvesFromCustomRecords() throws {
        repo.upsertEntries([entry(for: custom)])

        let known = EntryPeptideSnapshot.index([full, custom])
        let loaded = try XCTUnwrap(repo.loadEntries(resolvingFrom: known).first)
        XCTAssertEqual(loaded.peptide.description, custom.description)
        XCTAssertEqual(loaded.peptide.benefits, custom.benefits)
    }

    // MARK: - Legacy rows

    func test_legacyFullRecordRow_stillLoadsWithoutResolution() throws {
        let original = entry(for: full)
        _ = try insertLegacyRow(for: original)

        let loaded = try XCTUnwrap(repo.loadEntries().first)
        XCTAssertEqual(loaded.id, original.id)
        XCTAssertEqual(loaded.peptide.description, full.description)
        XCTAssertEqual(loaded.peptide.benefits, full.benefits)
    }

    func test_legacyFullRecordRow_isNotRewrittenOnUpdate() throws {
        var original = entry(for: full)
        let row = try insertLegacyRow(for: original)
        let legacyBlob = row.peptideData

        original.completed = true
        repo.upsertEntries([original])

        XCTAssertEqual(row.completed, true)
        XCTAssertEqual(row.peptideData, legacyBlob)
    }

    // MARK: - Index

    func test_index_keepsFirstRecordForDuplicateIds() {
        let index = EntryPeptideSnapshot.index([full, EntryPeptideSnapshot.snapshot(of: full)])
        XCTAssertEqual(index[full.id]?.description, full.description)
    }
}
