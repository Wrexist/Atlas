import XCTest
@testable import Peptide

@MainActor
final class DataStoreTests: XCTestCase {

    private var store: DataStore!

    override func setUp() {
        super.setUp()
        SwiftDataRepository.shared.configureForTesting()
        store = DataStore(seedSampleData: true)
    }

    override func tearDown() {
        SwiftDataRepository.shared.deleteAll()
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

    func test_toggleHealthConnection_disconnectsWithoutNeedingHealthKit() async {
        // Only the disconnect direction is deterministic. Connecting awaits a
        // real HealthKit authorization that a unit test cannot obtain, so the
        // service returns false and deliberately leaves the flag alone — the
        // old version of this test called an `async` method synchronously and
        // asserted a flip that would not happen in either direction.
        store.profile.healthConnected = true

        let didToggle = await store.toggleHealthConnection()

        XCTAssertTrue(didToggle)
        XCTAssertFalse(store.profile.healthConnected)
    }

    // MARK: - Profile customization

    func test_updateProfileIdentity_trimsWhitespaceAndPersists() {
        store.updateProfileIdentity(name: "  Casey  ", bio: "\n Optimizing recovery.\n ")
        XCTAssertEqual(store.profile.name, "Casey")
        XCTAssertEqual(store.profile.bio, "Optimizing recovery.")
    }

    func test_updateAvatarImageData_setsAndClears() {
        let payload = Data([0x01, 0x02, 0x03, 0x04])
        store.updateAvatarImageData(payload)
        XCTAssertEqual(store.profile.avatarImageData, payload)

        store.updateAvatarImageData(nil)
        XCTAssertNil(store.profile.avatarImageData)
    }

    func test_setPrimaryGoal_acceptsExistingGoal() {
        store.updateGoals(["Better Sleep", "Muscle Recovery"])
        store.setPrimaryGoal("Better Sleep")
        XCTAssertEqual(store.profile.primaryGoal, "Better Sleep")
    }

    func test_setPrimaryGoal_ignoresUnknownGoal() {
        store.updateGoals(["Better Sleep"])
        store.setPrimaryGoal("Better Sleep")
        // Unknown goals are silently ignored — the existing pin must stay.
        store.setPrimaryGoal("Cognitive Edge")
        XCTAssertEqual(store.profile.primaryGoal, "Better Sleep")
    }

    func test_setPrimaryGoal_nilClearsPin() {
        store.updateGoals(["Better Sleep"])
        store.setPrimaryGoal("Better Sleep")
        store.setPrimaryGoal(nil)
        XCTAssertNil(store.profile.primaryGoal)
    }

    func test_updateGoals_dropsStalePrimaryGoalWhenRemoved() {
        store.updateGoals(["Better Sleep", "Muscle Recovery"])
        store.setPrimaryGoal("Better Sleep")

        // The user un-checks the pinned goal — the pin must be dropped so we
        // don't surface a recommendation for a goal they no longer track.
        store.updateGoals(["Muscle Recovery"])
        XCTAssertNil(store.profile.primaryGoal)
    }

    func test_updateGoals_keepsPrimaryGoalWhenStillSelected() {
        store.updateGoals(["Better Sleep", "Muscle Recovery"])
        store.setPrimaryGoal("Better Sleep")

        store.updateGoals(["Better Sleep", "Fat Loss"])
        XCTAssertEqual(store.profile.primaryGoal, "Better Sleep")
    }

    // MARK: - Cache invalidation via didSet

    /// Mutating `entries` directly (e.g. via toggleEntry) must invalidate the
    /// cached todayEntries so subsequent reads reflect the change. The previous
    /// implementation relied on manual `invalidateCache()` calls; the regression
    /// would be a stale cached value persisting after a mutation.
    func test_mutation_invalidatesCachedTodayEntries() {
        guard let entry = store.todayEntries.first else {
            XCTFail("Expected at least one of today's entries from sample data")
            return
        }
        let wasCompleted = entry.completed
        let priorCompletedCount = store.todayEntries.filter(\.completed).count
        store.toggleEntry(entry.id)
        let newCompletedCount = store.todayEntries.filter(\.completed).count
        let expectedDelta = wasCompleted ? -1 : 1
        XCTAssertEqual(newCompletedCount, priorCompletedCount + expectedDelta)
    }

    /// Invariant: every supported cached stat reads from the same view of
    /// in-memory state, so totalDoses must equal totalDoses-of-completed across
    /// repeated reads with no mutations between them.
    func test_cachedStats_areStableAcrossReads() {
        let a = store.totalDoses
        let b = store.totalDoses
        let c = store.currentStreak
        let d = store.currentStreak
        XCTAssertEqual(a, b)
        XCTAssertEqual(c, d)
    }

    // MARK: - Activation idempotency

    /// regenerateTodayEntries must not duplicate entries when called twice on
    /// the same calendar day. handleAppActivation wraps this — it should be
    /// safe to call repeatedly.
    func test_handleAppActivation_isIdempotent() {
        store.handleAppActivation()
        let countAfterFirst = store.entries.filter { Calendar.current.isDateInToday($0.date) }.count
        store.handleAppActivation()
        let countAfterSecond = store.entries.filter { Calendar.current.isDateInToday($0.date) }.count
        XCTAssertEqual(countAfterFirst, countAfterSecond)
    }

    // MARK: - Per-peptide schedule preservation

    /// Callers must pass the existing `peptideSchedules` dict when they don't
    /// intend to clear overrides. HomeView's stack-adjustment apply path was
    /// silently wiping all per-peptide schedules by relying on the default
    /// empty dict — verify the explicit pass-through preserves them.
    func test_updateProtocol_preservesExistingPeptideSchedulesWhenPassedThrough() {
        let peptide = MockPeptides.bpc157
        let override = ProtocolSchedule(
            daysOfWeek: [1, 3, 5],
            timesPerDay: 1,
            preferredTimes: ["10:00 AM"],
            customDose: "300 mcg"
        )
        let proto = PeptideProtocol(
            id: UUID(),
            name: "Override test",
            peptides: [peptide],
            schedule: ProtocolSchedule(daysOfWeek: [1, 2, 3, 4, 5], timesPerDay: 1, preferredTimes: ["8:00 AM"]),
            peptideSchedules: [peptide.id: override],
            cycleLengthWeeks: 8,
            startDate: Date(),
            status: .active,
            notes: ""
        )
        store.addProtocol(proto)

        // Re-save with the same overrides explicitly forwarded.
        store.updateProtocol(
            id: proto.id,
            name: proto.name,
            peptides: proto.peptides,
            schedule: proto.schedule,
            peptideSchedules: proto.peptideSchedules,
            cycleLengthWeeks: proto.cycleLengthWeeks,
            notes: proto.notes
        )

        let saved = store.protocols.first { $0.id == proto.id }
        XCTAssertEqual(saved?.peptideSchedules[peptide.id], override,
                       "peptideSchedules must survive an updateProtocol round-trip when explicitly passed")
    }

    // MARK: - Watch delivery idempotency

    func test_watchMarkCompleteDuplicateDelivery_doesNotUncomplete() {
        guard let entry = store.entries.first(where: { !$0.completed }) else {
            XCTFail("No incomplete entries in seed data")
            return
        }
        store.markEntryComplete(entry.id)
        XCTAssertEqual(store.entries.first { $0.id == entry.id }?.completed, true)

        // WCSession can deliver the same action twice (sendMessage error
        // fallback re-sends via transferUserInfo). The duplicate must not
        // flip the entry back to incomplete.
        store.markEntryComplete(entry.id)
        XCTAssertEqual(store.entries.first { $0.id == entry.id }?.completed, true)
    }

    func test_watchMarkIncompleteDuplicateDelivery_doesNotComplete() {
        guard let entry = store.entries.first(where: { !$0.completed }) else {
            XCTFail("No incomplete entries in seed data")
            return
        }
        store.markEntryComplete(entry.id)
        store.markEntryIncomplete(entry.id)
        XCTAssertEqual(store.entries.first { $0.id == entry.id }?.completed, false)

        store.markEntryIncomplete(entry.id)
        XCTAssertEqual(store.entries.first { $0.id == entry.id }?.completed, false)
    }

    // MARK: - Persistence failure must not update projections

    func test_performSaveNow_widgetAndWatchNotUpdated_whenCommitFails() {
        let repo = SwiftDataRepository.shared
        guard let entry = store.entries.first else {
            XCTFail("No entries in store")
            return
        }

        repo.forceCommitFailureForTesting = true
        store.toggleEntry(entry.id)
        let widgetBaseline = store.widgetUpdateCountForTesting
        let watchBaseline = store.watchUpdateCountForTesting
        store.flushPendingSave()

        XCTAssertTrue(repo.commitDidFail, "Forced commit failure must be reported")
        XCTAssertEqual(store.widgetUpdateCountForTesting, widgetBaseline,
                       "Widget projection must not update when persistence fails")
        XCTAssertEqual(store.watchUpdateCountForTesting, watchBaseline,
                       "Watch projection must not update when persistence fails")
        XCTAssertEqual(store.lastError, DataStore.saveFailureMessage,
                       "The user-visible save-failure banner must still surface")

        // Recovery: once persistence succeeds again the projections push
        // and the banner clears.
        repo.forceCommitFailureForTesting = false
        store.flushPendingSave()
        XCTAssertGreaterThan(store.widgetUpdateCountForTesting, widgetBaseline)
        XCTAssertGreaterThan(store.watchUpdateCountForTesting, watchBaseline)
        XCTAssertNil(store.lastError)
    }
}
