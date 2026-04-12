import XCTest
@testable import Peptide

final class DataStoreTests: XCTestCase {

    private var store: DataStore!

    override func setUp() {
        super.setUp()
        store = DataStore()
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    // MARK: - Protocol Management

    func test_activeProtocols_filtersCorrectly() {
        let activeCount = store.protocols.filter { $0.status == .active }.count
        XCTAssertEqual(store.activeProtocols.count, activeCount)
    }

    func test_pausedProtocols_filtersCorrectly() {
        let pausedCount = store.protocols.filter { $0.status == .paused }.count
        XCTAssertEqual(store.pausedProtocols.count, pausedCount)
    }

    func test_completedProtocols_filtersCorrectly() {
        let completedCount = store.protocols.filter { $0.status == .completed }.count
        XCTAssertEqual(store.completedProtocols.count, completedCount)
    }

    func test_addProtocol_insertsAtBeginning() {
        let initialCount = store.protocols.count
        let newProtocol = PeptideProtocol(
            id: UUID(),
            name: "Test Protocol",
            peptides: [],
            schedule: ProtocolSchedule(daysOfWeek: [1, 3, 5], timesPerDay: 1, preferredTimes: ["8:00 AM"]),
            cycleLengthWeeks: 4,
            startDate: Date(),
            status: .active,
            notes: ""
        )
        store.addProtocol(newProtocol)
        XCTAssertEqual(store.protocols.count, initialCount + 1)
        XCTAssertEqual(store.protocols.first?.id, newProtocol.id)
    }

    func test_deleteProtocol_removesProtocolAndEntries() {
        guard let proto = store.protocols.first else {
            XCTFail("No protocols in store")
            return
        }
        let protocolId = proto.id
        store.deleteProtocol(id: protocolId)
        XCTAssertFalse(store.protocols.contains { $0.id == protocolId })
        XCTAssertFalse(store.entries.contains { $0.protocolId == protocolId })
    }

    func test_updateProtocolStatus_changesStatus() {
        guard let proto = store.protocols.first(where: { $0.status == .active }) else {
            XCTFail("No active protocols")
            return
        }
        store.updateProtocolStatus(id: proto.id, to: .paused)
        let updated = store.protocols.first { $0.id == proto.id }
        XCTAssertEqual(updated?.status, .paused)
    }

    // MARK: - Entry Management

    func test_toggleEntry_flipsCompletionState() {
        guard let entry = store.entries.first else {
            XCTFail("No entries in store")
            return
        }
        let wasCompleted = entry.completed
        store.toggleEntry(entry.id)
        let updated = store.entries.first { $0.id == entry.id }
        XCTAssertEqual(updated?.completed, !wasCompleted)
    }

    func test_todayEntries_onlyContainsTodaysActiveEntries() {
        let calendar = Calendar.current
        let activeIds = Set(store.activeProtocols.map(\.id))
        for entry in store.todayEntries {
            XCTAssertTrue(calendar.isDateInToday(entry.date))
            XCTAssertTrue(activeIds.contains(entry.protocolId))
        }
    }

    func test_todayEntries_areSortedByDate() {
        let today = store.todayEntries
        for i in 1..<today.count {
            XCTAssertLessThanOrEqual(today[i - 1].date, today[i].date)
        }
    }

    func test_entriesFor_respectsDaysCutoff() {
        guard let proto = store.protocols.first else { return }
        let entries7 = store.entriesFor(protocolId: proto.id, days: 7)
        let entries30 = store.entriesFor(protocolId: proto.id, days: 30)
        XCTAssertLessThanOrEqual(entries7.count, entries30.count)
    }

    func test_entriesFor_sortedByDateDescending() {
        guard let proto = store.protocols.first else { return }
        let entries = store.entriesFor(protocolId: proto.id, days: 30)
        for i in 1..<entries.count {
            XCTAssertGreaterThanOrEqual(entries[i - 1].date, entries[i].date)
        }
    }

    // MARK: - Stats

    func test_totalDoses_countsOnlyCompleted() {
        let manualCount = store.entries.filter(\.completed).count
        XCTAssertEqual(store.totalDoses, manualCount)
    }

    func test_totalDaysLogged_countsUniqueDays() {
        let calendar = Calendar.current
        let uniqueDays = Set(store.entries.filter(\.completed).map { calendar.startOfDay(for: $0.date) })
        XCTAssertEqual(store.totalDaysLogged, uniqueDays.count)
    }

    func test_currentStreak_isNonNegative() {
        XCTAssertGreaterThanOrEqual(store.currentStreak, 0)
    }

    func test_bestStreak_isNonNegative() {
        XCTAssertGreaterThanOrEqual(store.bestStreak, 0)
    }

    func test_averageCompliance_isBetweenZeroAndOne() {
        let avg = store.averageCompliance
        XCTAssertGreaterThanOrEqual(avg, 0)
        XCTAssertLessThanOrEqual(avg, 1)
    }

    func test_complianceTrend_returnsValueInRange() {
        let trend = store.complianceTrend(for: 7)
        XCTAssertGreaterThanOrEqual(trend, -1)
        XCTAssertLessThanOrEqual(trend, 1)
    }

    func test_complianceTrend_zeroForSingleDay() {
        let trend = store.complianceTrend(for: 1)
        XCTAssertEqual(trend, 0)
    }

    // MARK: - Profile

    func test_updateGoals_setsGoalsSorted() {
        store.updateGoals(Set(["Muscle Recovery", "Better Sleep", "Fat Loss"]))
        XCTAssertEqual(store.profile.goals, ["Better Sleep", "Fat Loss", "Muscle Recovery"])
    }

    func test_toggleHealthConnection_flipsState() {
        let was = store.profile.healthConnected
        store.toggleHealthConnection()
        XCTAssertEqual(store.profile.healthConnected, !was)
    }
}
