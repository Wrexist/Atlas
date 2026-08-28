import XCTest
@testable import Peptide

/// Scale behaviour of the entry store (audit Data Integrity 04,
/// Phase 7): the launch path fetches a bounded recent window with the
/// date filter pushed into SQLite, and the long tail hydrates via an
/// async backfill so no surface loses history.
@MainActor
final class EntryLoadingScaleTests: XCTestCase {

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

    private func entry(daysAgo: Int) -> ProtocolEntry {
        ProtocolEntry(
            id: UUID(),
            protocolId: UUID(),
            peptide: MockPeptides.bpc157,
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
            dose: "250mcg",
            notes: "",
            completed: daysAgo % 2 == 0
        )
    }

    func test_loadEntries_at10kRows_completesUnderBudget() {
        // ~10k rows spread over ~9 years — a heavy power-user history.
        let seeded = (0..<10_000).map { entry(daysAgo: $0 % 3_300) }
        repo.saveEntries(seeded)

        let windowStart = DataStore.recentEntryWindowStart()
        let start = Date()
        let recent = repo.loadEntries(onOrAfter: windowStart)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertFalse(recent.isEmpty)
        XCTAssertTrue(recent.allSatisfy { $0.date >= windowStart },
                      "The windowed fetch must push the date filter into the store")
        XCTAssertLessThan(recent.count, seeded.count,
                          "The launch window must not materialize the whole table")
        // Generous CI budget — the point is catching a regression back
        // to full-table-decode territory, not micro-benchmarking.
        XCTAssertLessThan(elapsed, 3.0,
                          "Windowed launch fetch took \(elapsed)s at 10k rows")
    }

    func test_windowedPlusBackfill_coversEveryRow() {
        let seeded = (0..<200).map { entry(daysAgo: $0 * 10) }   // 0…5.5 years
        repo.saveEntries(seeded)

        let windowStart = DataStore.recentEntryWindowStart()
        let recent = repo.loadEntries(onOrAfter: windowStart)
        let tail = repo.loadEntries(before: windowStart)

        XCTAssertEqual(recent.count + tail.count, seeded.count,
                       "Window + tail must partition the table with no row lost or duplicated")
        XCTAssertEqual(Set((recent + tail).map(\.id)), Set(seeded.map(\.id)))
    }

    func test_dataStoreBackfill_hydratesFullHistory() async {
        let recentRows = (0..<30).map { entry(daysAgo: $0) }
        let oldRows = (0..<30).map { entry(daysAgo: 500 + $0) }
        repo.saveEntries(recentRows + oldRows)

        let store = DataStore()
        XCTAssertEqual(Set(store.entries.map(\.id)).intersection(Set(recentRows.map(\.id))).count,
                       recentRows.count,
                       "The synchronous window must contain all recent entries")

        await store.awaitEntryBackfillForTesting()
        XCTAssertEqual(Set(store.entries.map(\.id)),
                       Set((recentRows + oldRows).map(\.id)),
                       "After backfill the store must hold the full history")
    }

    func test_loadEntryIDs_matchesFullLoad() {
        let seeded = (0..<25).map { entry(daysAgo: $0) }
        repo.saveEntries(seeded)
        XCTAssertEqual(Set(repo.loadEntryIDs()), Set(seeded.map(\.id)))
        XCTAssertEqual(repo.entryCount(), seeded.count)
    }
}
