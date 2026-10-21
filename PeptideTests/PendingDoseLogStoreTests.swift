import XCTest
@testable import Peptide

final class PendingDoseLogStoreTests: XCTestCase {

    private let suiteName = "tests.peptidesai.pendingDoseLogs"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // Brand-new suite per test so leftover values don't bleed
        // between scenarios. removePersistentDomain ensures any
        // previous run's data is gone.
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_enqueue_andDrain_roundTripsOneEntry() {
        let log = PendingDoseLogStore.PendingLog(entryId: UUID(), loggedAt: Date())
        PendingDoseLogStore.enqueue(log, defaults: defaults)
        let drained = PendingDoseLogStore.drain(defaults: defaults)
        XCTAssertEqual(drained, [log])
    }

    func test_drain_empties_inbox() {
        PendingDoseLogStore.enqueue(
            PendingDoseLogStore.PendingLog(entryId: UUID(), loggedAt: Date()),
            defaults: defaults
        )
        _ = PendingDoseLogStore.drain(defaults: defaults)
        XCTAssertTrue(PendingDoseLogStore.drain(defaults: defaults).isEmpty)
    }

    func test_enqueue_preservesArrivalOrder() {
        let a = PendingDoseLogStore.PendingLog(entryId: UUID(), loggedAt: Date(timeIntervalSince1970: 1000))
        let b = PendingDoseLogStore.PendingLog(entryId: UUID(), loggedAt: Date(timeIntervalSince1970: 2000))
        PendingDoseLogStore.enqueue(a, defaults: defaults)
        PendingDoseLogStore.enqueue(b, defaults: defaults)
        let drained = PendingDoseLogStore.drain(defaults: defaults)
        XCTAssertEqual(drained, [a, b])
    }

    func test_enqueue_idempotentForIdenticalLog() {
        let log = PendingDoseLogStore.PendingLog(entryId: UUID(), loggedAt: Date(timeIntervalSince1970: 1000))
        PendingDoseLogStore.enqueue(log, defaults: defaults)
        PendingDoseLogStore.enqueue(log, defaults: defaults)
        XCTAssertEqual(PendingDoseLogStore.drain(defaults: defaults).count, 1)
    }

    func test_peek_doesNotDrain() {
        let log = PendingDoseLogStore.PendingLog(entryId: UUID(), loggedAt: Date())
        PendingDoseLogStore.enqueue(log, defaults: defaults)
        _ = PendingDoseLogStore.peek(defaults: defaults)
        XCTAssertEqual(PendingDoseLogStore.peek(defaults: defaults).count, 1)
    }

    func test_drain_legacyArrayInbox_stillDeliversQueuedTaps() throws {
        let legacy = PendingDoseLogStore.PendingLog(entryId: UUID(), loggedAt: Date(timeIntervalSince1970: 1000))
        let current = PendingDoseLogStore.PendingLog(entryId: UUID(), loggedAt: Date(timeIntervalSince1970: 2000))
        defaults.set(try JSONEncoder().encode([legacy]), forKey: "com.peptidesai.app.pendingDoseLogs")
        PendingDoseLogStore.enqueue(current, defaults: defaults)

        XCTAssertEqual(PendingDoseLogStore.drain(defaults: defaults), [legacy, current])
        XCTAssertTrue(PendingDoseLogStore.drain(defaults: defaults).isEmpty)
    }
}

@MainActor
final class PendingDoseLogProcessorTests: XCTestCase {

    private let suiteName = "tests.peptidesai.pendingDoseLogs.processor"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_drain_emptyInbox_isNoOp() {
        let store = DataStore(seedSampleData: false)
        let applied = PendingDoseLogProcessor.drain(into: store, defaults: defaults)
        XCTAssertEqual(applied, 0)
    }

    func test_drain_matchingPendingEntry_completesAtTapTime() {
        let store = DataStore(seedSampleData: false)
        let entry = ProtocolEntry(
            id: UUID(),
            protocolId: UUID(),
            peptide: MockPeptides.bpc157,
            date: Date(),
            dose: "250mcg",
            notes: "",
            completed: false
        )
        store.entries.append(entry)
        let tappedAt = Date(timeIntervalSince1970: 1_800_000_000)

        PendingDoseLogStore.enqueue(
            PendingDoseLogStore.PendingLog(entryId: entry.id, loggedAt: tappedAt),
            defaults: defaults
        )
        let applied = PendingDoseLogProcessor.drain(into: store, defaults: defaults)
        XCTAssertEqual(applied, 1)
        let logged = store.entries.first(where: { $0.id == entry.id })
        XCTAssertTrue(logged?.completed ?? false)
        XCTAssertEqual(logged?.actualTime, tappedAt)
    }

    func test_drain_skipsAlreadyCompletedEntries() {
        let store = DataStore(seedSampleData: false)
        let entry = ProtocolEntry(
            id: UUID(),
            protocolId: UUID(),
            peptide: MockPeptides.bpc157,
            date: Date(),
            dose: "250mcg",
            notes: "",
            completed: true
        )
        store.entries.append(entry)
        PendingDoseLogStore.enqueue(
            PendingDoseLogStore.PendingLog(entryId: entry.id, loggedAt: Date()),
            defaults: defaults
        )
        let applied = PendingDoseLogProcessor.drain(into: store, defaults: defaults)
        XCTAssertEqual(applied, 0)
    }

    func test_drain_skipsUnknownEntryIds() {
        let store = DataStore(seedSampleData: false)
        PendingDoseLogStore.enqueue(
            PendingDoseLogStore.PendingLog(entryId: UUID(), loggedAt: Date()),
            defaults: defaults
        )
        let applied = PendingDoseLogProcessor.drain(into: store, defaults: defaults)
        XCTAssertEqual(applied, 0)
    }
}
