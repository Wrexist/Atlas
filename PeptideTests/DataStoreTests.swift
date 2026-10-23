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

    func test_restartProtocol_completedCycle_resetsStartDateAndActivates() {
        for other in store.protocols {
            store.updateProtocolStatus(id: other.id, to: .paused)
        }
        let finished = PeptideProtocol(
            id: UUID(),
            name: "Finished Protocol",
            peptides: [],
            schedule: ProtocolSchedule(daysOfWeek: [1, 3, 5], timesPerDay: 1, preferredTimes: ["8:00 AM"]),
            cycleLengthWeeks: 4,
            startDate: Calendar.current.date(byAdding: .weekOfYear, value: -12, to: Date())!,
            status: .completed,
            notes: ""
        )
        store.addProtocol(finished)

        XCTAssertTrue(store.restartProtocol(id: finished.id))
        let updated = store.protocols.first { $0.id == finished.id }
        XCTAssertEqual(updated?.status, .active)
        XCTAssertEqual(updated?.startDate, Calendar.current.startOfDay(for: Date()))
    }

    func test_restartProtocol_activeProtocolAtFreeCap_restartsCycle() throws {
        try XCTSkipIf(StoreService.shared.isProUser, "Free-tier cap only applies without Pro")
        let protos = (0..<4).map { index in
            PeptideProtocol(
                id: UUID(),
                name: "Active \(index)",
                peptides: [],
                schedule: ProtocolSchedule(daysOfWeek: [1, 3, 5], timesPerDay: 1, preferredTimes: ["8:00 AM"]),
                cycleLengthWeeks: 4,
                startDate: Calendar.current.date(byAdding: .weekOfYear, value: -5, to: Date())!,
                status: .active,
                notes: ""
            )
        }
        protos.forEach(store.addProtocol)
        let ended = protos[0]

        XCTAssertTrue(store.restartProtocol(id: ended.id),
                      "Restarting an already-active protocol doesn't raise the active count")
        let updated = store.protocols.first { $0.id == ended.id }
        XCTAssertEqual(updated?.startDate, Calendar.current.startOfDay(for: Date()))
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
        for (earlier, later) in zip(today, today.dropFirst()) {
            XCTAssertLessThanOrEqual(earlier.date, later.date)
        }
    }

    func test_entriesFor_respectsDaysCutoff() {
        guard let proto = store.protocols.first else { return XCTFail("Seed data should include a protocol") }
        let entries7 = store.entriesFor(protocolId: proto.id, days: 7)
        let entries30 = store.entriesFor(protocolId: proto.id, days: 30)
        XCTAssertLessThanOrEqual(entries7.count, entries30.count)
    }

    func test_entriesFor_sortedByDateDescending() {
        guard let proto = store.protocols.first else { return XCTFail("Seed data should include a protocol") }
        let entries = store.entriesFor(protocolId: proto.id, days: 30)
        for (newer, older) in zip(entries, entries.dropFirst()) {
            XCTAssertGreaterThanOrEqual(newer.date, older.date)
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
        store.markEntryComplete(entry.id, at: Date())
        XCTAssertEqual(store.entries.first { $0.id == entry.id }?.completed, true)

        // WCSession can deliver the same action twice (sendMessage error
        // fallback re-sends via transferUserInfo). The duplicate must not
        // flip the entry back to incomplete.
        store.markEntryComplete(entry.id, at: Date())
        XCTAssertEqual(store.entries.first { $0.id == entry.id }?.completed, true)
    }

    func test_logDose_clearedNotesAndBlankDose_areStoredAsCleared() {
        guard let entry = store.entries.first else {
            XCTFail("No entries in store")
            return
        }
        store.logDose(entryId: entry.id, actualDose: "250 mcg", actualTime: nil, injectionSite: nil, notes: "Left side")
        store.logDose(entryId: entry.id, actualDose: "  ", actualTime: nil, injectionSite: nil, notes: "")

        let updated = store.entries.first { $0.id == entry.id }
        XCTAssertEqual(updated?.notes, "")
        XCTAssertNil(updated?.actualDose)
    }

    func test_watchMarkIncompleteDuplicateDelivery_doesNotComplete() {
        guard let entry = store.entries.first(where: { !$0.completed }) else {
            XCTFail("No incomplete entries in seed data")
            return
        }
        store.markEntryComplete(entry.id, at: Date())
        store.markEntryIncomplete(entry.id)
        XCTAssertEqual(store.entries.first { $0.id == entry.id }?.completed, false)

        store.markEntryIncomplete(entry.id)
        XCTAssertEqual(store.entries.first { $0.id == entry.id }?.completed, false)
    }

    func test_watchMarkComplete_recordsTapTimeAndUndoClearsIt() {
        guard let entry = store.entries.first(where: { !$0.completed }) else {
            XCTFail("No incomplete entries in seed data")
            return
        }
        let tappedAt = Date().addingTimeInterval(-3 * 3600)
        store.markEntryComplete(entry.id, at: tappedAt)
        XCTAssertEqual(store.entries.first { $0.id == entry.id }?.actualTime, tappedAt)

        // A duplicate delivery must not overwrite the original tap time.
        store.markEntryComplete(entry.id, at: Date())
        XCTAssertEqual(store.entries.first { $0.id == entry.id }?.actualTime, tappedAt)

        store.markEntryIncomplete(entry.id)
        XCTAssertNil(store.entries.first { $0.id == entry.id }?.actualTime)
    }

    func test_phoneUndoOfWatchTappedDose_clearsTapTime() {
        guard let entry = store.entries.first(where: { !$0.completed }) else {
            XCTFail("No incomplete entries in seed data")
            return
        }
        store.markEntryComplete(entry.id, at: Date().addingTimeInterval(-3600))

        // Undo from Home / Protocol detail / intents goes through the plain
        // toggle; a stale tap time would show as the untaken dose's time.
        store.toggleEntry(entry.id)

        let undone = store.entries.first { $0.id == entry.id }
        XCTAssertEqual(undone?.completed, false)
        XCTAssertNil(undone?.actualTime)
    }

    // MARK: - Dirty tracking

    func test_flushPendingSave_withNothingChanged_isANoOp() {
        // Backgrounding an untouched app used to upsert every protocol,
        // every entry and the whole profile, then reload every widget
        // timeline. Nothing dirty must mean nothing written.
        store.flushPendingSave()
        let widgetBaseline = store.widgetUpdateCountForTesting
        let watchBaseline = store.watchUpdateCountForTesting

        store.flushPendingSave()

        XCTAssertEqual(store.widgetUpdateCountForTesting, widgetBaseline,
                       "A save with nothing dirty must not rebuild the widget snapshot")
        XCTAssertEqual(store.watchUpdateCountForTesting, watchBaseline,
                       "A save with nothing dirty must not rebuild the Watch payload")
    }

    func test_flushPendingSave_afterAMutation_writesAndPushesProjections() {
        store.flushPendingSave()
        let widgetBaseline = store.widgetUpdateCountForTesting
        guard let entry = store.entries.first else {
            XCTFail("No entries in store")
            return
        }

        store.toggleEntry(entry.id)
        store.flushPendingSave()

        XCTAssertGreaterThan(store.widgetUpdateCountForTesting, widgetBaseline)
    }

    func test_mutationSurvives_aReloadFromDisk() {
        // The dirty flags gate what reaches disk, so the round trip is
        // the check that matters: a toggle must still be persisted.
        guard let entry = store.entries.first(where: { !$0.completed }) else {
            XCTFail("No incomplete entry in store")
            return
        }
        store.toggleEntry(entry.id)
        store.flushPendingSave()

        store.reloadFromDisk()

        XCTAssertEqual(store.entries.first(where: { $0.id == entry.id })?.completed, true)
    }

    func test_profileEdit_isPersisted_evenWhenEntriesAreClean() {
        store.flushPendingSave()

        store.updateProfileIdentity(name: "Dirty Tracking", bio: "")
        store.flushPendingSave()
        store.reloadFromDisk()

        XCTAssertEqual(store.profile.name, "Dirty Tracking")
    }

    // MARK: - Multi-device sync

    func test_cloudImport_afterADebouncedSave_reloadsFromDisk() async throws {
        store.updateProfileIdentity(name: "Local edit", bio: "")
        try await Task.sleep(for: .seconds(1))
        let synced = PeptideProtocol(
            id: UUID(),
            name: "Synced from iPad",
            peptides: [],
            schedule: ProtocolSchedule(daysOfWeek: [1], timesPerDay: 1, preferredTimes: ["8:00 AM"]),
            cycleLengthWeeks: 4,
            startDate: Date(),
            status: .paused,
            notes: ""
        )
        SwiftDataRepository.shared.upsertProtocols([synced])

        NotificationCenter.default.post(name: .peptideXCloudKitImportCompleted, object: nil)
        try await Task.sleep(for: .seconds(4))

        XCTAssertTrue(store.protocols.contains { $0.id == synced.id },
                      "A finished debounced save must not block the import refresh for the rest of the session")
    }

    func test_reloadFromDisk_withProtocolAddedElsewhere_schedulesItsReminders() {
        store.profile.doseRemindersEnabled = true
        store.persistProfile()
        store.flushPendingSave()
        store.reloadFromDisk()
        let before = NotificationService.shared.requestedCount
        let synced = PeptideProtocol(
            id: UUID(),
            name: "Added on iPad",
            peptides: [MockPeptides.bpc157],
            schedule: ProtocolSchedule(daysOfWeek: [1, 2, 3, 4, 5, 6, 7], timesPerDay: 1, preferredTimes: ["6:15 AM"]),
            cycleLengthWeeks: 4,
            startDate: Date(),
            status: .active,
            notes: ""
        )
        SwiftDataRepository.shared.upsertProtocols([synced])

        store.reloadFromDisk()

        XCTAssertEqual(NotificationService.shared.requestedCount, before + 7,
                       "A protocol synced in from another device must get one weekly reminder per scheduled day")
    }

    func test_scheduledID_sameDoseSlot_isIdenticalOnEveryDevice() {
        let protocolId = UUID()
        let peptideId = UUID()
        let slot = Date(timeIntervalSince1970: 1_760_000_000)

        let iPhone = ProtocolEntry.scheduledID(protocolId: protocolId, peptideId: peptideId, date: slot, calendar: .current)
        let iPad = ProtocolEntry.scheduledID(protocolId: protocolId, peptideId: peptideId, date: slot, calendar: .current)
        let laterSlot = ProtocolEntry.scheduledID(
            protocolId: protocolId, peptideId: peptideId, date: slot.addingTimeInterval(3600), calendar: .current
        )

        XCTAssertEqual(iPhone, iPad)
        XCTAssertNotEqual(iPhone, laterSlot)
    }

    func test_collapsingDuplicateIDs_twoDevicesRows_keepsTheLoggedOne() {
        let pending = ProtocolEntry(
            id: UUID(), protocolId: UUID(), peptide: MockPeptides.bpc157,
            date: Date(), dose: "250 mcg", notes: "", completed: false
        )
        var logged = pending
        logged.completed = true

        let collapsed = SwiftDataRepository.collapsingDuplicateIDs([pending, logged])

        XCTAssertEqual(collapsed.count, 1)
        XCTAssertEqual(collapsed.first?.completed, true)
    }

    func test_deleteProtocol_alsoDeletesItsRowsNotLoadedInMemory() throws {
        let proto = try XCTUnwrap(store.protocols.first)
        let syncedIn = ProtocolEntry(
            id: UUID(), protocolId: proto.id, peptide: MockPeptides.bpc157,
            date: Date(), dose: "250 mcg", notes: "", completed: false
        )
        SwiftDataRepository.shared.upsertEntries([syncedIn])

        store.deleteProtocol(id: proto.id)
        store.flushPendingSave()

        XCTAssertFalse(SwiftDataRepository.shared.loadEntries().contains { $0.protocolId == proto.id })
    }

    // MARK: - Travel mode

    func test_applyTravelShift_movesTodaysPendingDoseToTheShiftedTime() {
        let proto = PeptideProtocol(
            id: UUID(),
            name: "Travel test",
            peptides: [MockPeptides.bpc157],
            schedule: ProtocolSchedule(daysOfWeek: Array(1...7), timesPerDay: 1, preferredTimes: ["8:00 AM"]),
            cycleLengthWeeks: 8,
            startDate: Date(),
            status: .active,
            notes: ""
        )
        store.addProtocol(proto)

        store.applyTravelShift(toTimezone: TimeZone.current.identifier, minutesDelta: 120)

        let todays = store.entries.filter { $0.protocolId == proto.id && Calendar.current.isDateInToday($0.date) }
        XCTAssertEqual(todays.map { Calendar.current.component(.hour, from: $0.date) }, [10],
                       "Today's already-generated dose must move with the schedule")
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
