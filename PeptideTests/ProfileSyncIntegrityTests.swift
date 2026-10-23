import SwiftData
import XCTest
@testable import Peptide

/// Multi-device safety of the profile store (audit Data Integrity 04,
/// Phases 3 + 8): high-churn feature areas live in their own
/// `StoredProfile` columns so CloudKit's field-level conflict
/// resolution can merge independent edits, and duplicate profile rows
/// reconcile deterministically instead of "whichever fetch returned
/// first".
///
/// True CloudKit sync cannot run in unit tests; these are the strongest
/// deterministic simulation — they assert the storage-level property
/// CloudKit's merge depends on (disjoint edits dirty disjoint columns)
/// and exercise the reconciliation path directly. The hardware
/// counterpart is docs/CLOUDKIT_HARDWARE_TEST_PLAN.md.
@MainActor
final class ProfileSyncIntegrityTests: XCTestCase {

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

    // MARK: - Fixtures

    private let day = Date(timeIntervalSince1970: 1_760_000_000)

    private func meal(_ name: String) -> MealEntry {
        MealEntry(date: day, category: .lunch, name: name,
                  calories: 550, proteinG: 40, carbsG: 50, fatG: 15,
                  source: .custom)
    }

    private func habit(_ name: String) -> Habit {
        Habit(name: name, iconSymbol: "drop.fill", tintHex: 0x33AAFF,
              createdAt: day)
    }

    private func baseProfile() -> UserProfile {
        var profile = UserProfile.fresh
        profile.name = "Sync Tester"
        profile.mealHistory = [meal("Base meal")]
        profile.habits = [habit("Hydrate")]
        return profile
    }

    // MARK: - Phase 3: field-level conflict surface

    /// Device A logs a meal, device B checks a habit. CloudKit merges
    /// per record field, so both facts survive iff the two edits dirty
    /// different columns while every untouched column stays
    /// byte-identical. This test asserts exactly that, then applies the
    /// merge CloudKit would produce and checks both facts came through.
    func test_multiDeviceConcurrentProfileEdit_bothFactsSurvive() throws {
        let base = baseProfile()

        var deviceA = base
        deviceA.mealHistory.append(meal("Device A salmon"))
        var deviceB = base
        deviceB.habitEntries.append(HabitEntry(habitId: base.habits[0].id, date: day))

        let rowBase = try StoredProfile.make(from: base)
        let rowA = try StoredProfile.make(from: deviceA)
        let rowB = try StoredProfile.make(from: deviceB)

        // A's edit dirties only the meals column…
        XCTAssertNotEqual(rowA.mealsData, rowBase.mealsData)
        XCTAssertEqual(rowA.habitsData, rowBase.habitsData,
                       "Logging a meal must not rewrite the habits column")
        XCTAssertEqual(rowA.extensionData, rowBase.extensionData,
                       "Logging a meal must not rewrite the residual blob")
        // …and B's only the habits column.
        XCTAssertNotEqual(rowB.habitsData, rowBase.habitsData)
        XCTAssertEqual(rowB.mealsData, rowBase.mealsData,
                       "Checking a habit must not rewrite the meals column")

        // CloudKit-style merge: take each device's dirty field.
        let merged = try StoredProfile.make(from: base)
        merged.mealsData = rowA.mealsData
        merged.habitsData = rowB.habitsData
        let reconciled = try merged.toUserProfile()

        XCTAssertTrue(reconciled.mealHistory.contains { $0.name == "Device A salmon" },
                      "Device A's meal must survive the merge")
        XCTAssertEqual(reconciled.habitEntries.count, 1,
                       "Device B's habit check-in must survive the merge")
    }

    /// The save path must not touch columns whose content didn't change —
    /// observable through `updatedAt`, which only advances on a real
    /// content change.
    func test_saveProfile_identicalContent_doesNotAdvanceUpdatedAt() throws {
        let profile = baseProfile()
        repo.saveProfile(profile)
        let firstStamp = try XCTUnwrap(loadStoredRow()).updatedAt

        repo.saveProfile(profile)
        XCTAssertEqual(try XCTUnwrap(loadStoredRow()).updatedAt, firstStamp,
                       "Re-saving unchanged content must not look like an edit")

        var edited = profile
        edited.name = "Renamed"
        repo.saveProfile(edited)
        XCTAssertGreaterThan(try XCTUnwrap(loadStoredRow()).updatedAt, firstStamp)
    }

    /// A row written before the split (slice columns nil, everything in
    /// the legacy blob) must surface its data unchanged, and the next
    /// save must move it into the split columns.
    func test_legacyBlobRow_readsThroughFallback_andMigratesOnNextSave() throws {
        struct LegacyExtension: Codable {
            var mealHistory: [MealEntry]
            var habits: [Habit]
            var atlasScore: Int
        }
        let legacy = LegacyExtension(
            mealHistory: [meal("Legacy meal")],
            habits: [habit("Legacy habit")],
            atlasScore: 420
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let row = try StoredProfile.make(from: .fresh)
        row.extensionData = try encoder.encode(legacy)
        row.mealsData = nil
        row.habitsData = nil
        row.momentumData = nil

        let decoded = try row.toUserProfile()
        XCTAssertEqual(decoded.mealHistory.first?.name, "Legacy meal")
        XCTAssertEqual(decoded.habits.first?.name, "Legacy habit")
        XCTAssertEqual(decoded.atlasScore, 420)

        try row.update(from: decoded)
        XCTAssertNotNil(row.mealsData, "A save must promote legacy blob data into the split columns")
        let roundTripped = try row.toUserProfile()
        XCTAssertEqual(roundTripped.mealHistory.first?.name, "Legacy meal")
        XCTAssertEqual(roundTripped.atlasScore, 420)
    }

    // MARK: - Phase 8: singleton identity + reconciliation

    func test_firstSave_createsExactlyOneRow_withSingletonKey() throws {
        repo.saveProfile(baseProfile())
        let rows = try fetchAllRows()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.singletonKey, StoredProfile.canonicalSingletonKey)
    }

    func test_duplicateProfileRows_reconcileToNewest_andAdoptMissingSlices() throws {
        // Simulate two devices that each created a row before CloudKit
        // converged: the older row carries habits the newer lacks.
        var older = baseProfile()
        older.name = "Older device"
        let olderRow = try StoredProfile.make(from: older)
        olderRow.updatedAt = day

        var newer = UserProfile.fresh
        newer.name = "Newer device"
        let newerRow = try StoredProfile.make(from: newer)
        newerRow.habitsData = nil   // newer device never had habits
        newerRow.updatedAt = day.addingTimeInterval(3600)

        try insertRows([olderRow, newerRow])

        let loaded = try XCTUnwrap(repo.loadProfile())
        XCTAssertEqual(loaded.name, "Newer device", "Newest row must win deterministically")
        XCTAssertEqual(loaded.habits.first?.name, "Hydrate",
                       "A slice the winner lacks must be adopted from the losing row")
        XCTAssertEqual(try fetchAllRows().count, 1,
                       "Reconciliation must converge to a single row")
    }

    func test_reload_returnsSameProfile_afterReconciliation() throws {
        repo.saveProfile(baseProfile())
        let first = try XCTUnwrap(repo.loadProfile())
        let second = try XCTUnwrap(repo.loadProfile())
        XCTAssertEqual(first.name, second.name)
        XCTAssertEqual(first.mealHistory, second.mealHistory)
        XCTAssertEqual(try fetchAllRows().count, 1)
    }

    func test_freshOnboardingRowNewerThanTheRealRow_keepsTheAccountHistory() throws {
        // A new iPhone finishes onboarding before CloudKit's first import:
        // its fresh row is newer than the account's real one.
        var real = baseProfile()
        real.weightHistory = [WeightEntry(date: day, kg: 80)]
        let realRow = try StoredProfile.make(from: real)
        realRow.updatedAt = day

        var fresh = UserProfile.fresh
        fresh.name = "Onboarded"
        let freshRow = try StoredProfile.make(from: fresh)
        freshRow.updatedAt = day.addingTimeInterval(3600)

        try insertRows([realRow, freshRow])

        let loaded = try XCTUnwrap(repo.loadProfile())
        XCTAssertEqual(loaded.name, "Onboarded")
        XCTAssertEqual(loaded.mealHistory.map(\.name), ["Base meal"])
        XCTAssertEqual(loaded.habits.map(\.name), ["Hydrate"])
        XCTAssertEqual(loaded.weightHistory.count, 1)
        XCTAssertEqual(try fetchAllRows().count, 1)
    }

    func test_freshRowNewerThanTheRealRow_keepsTheAccountSettings() throws {
        // A save after an identity change, before CloudKit's first import,
        // writes the in-memory fresh profile as the newest row.
        var real = baseProfile()
        // Stored dates round-trip at whole seconds, so pin ageRecordedAt.
        real.bodyMetrics = BodyMetrics(weightKg: 82, heightCm: 180, age: 38,
                                       sex: .male, activityLevel: .active, unit: .metric,
                                       ageRecordedAt: day)
        real.biometricLockEnabled = true
        real.lastKnownTimezoneIdentifier = "Europe/Stockholm"
        let realRow = try StoredProfile.make(from: real)
        realRow.updatedAt = day

        let freshRow = try StoredProfile.make(from: .fresh)
        freshRow.updatedAt = day.addingTimeInterval(3600)

        try insertRows([realRow, freshRow])

        let loaded = try XCTUnwrap(repo.loadProfile())
        XCTAssertEqual(loaded.bodyMetrics, real.bodyMetrics)
        XCTAssertTrue(loaded.biometricLockEnabled)
        XCTAssertEqual(loaded.lastKnownTimezoneIdentifier, "Europe/Stockholm")
        XCTAssertEqual(loaded.name, "Sync Tester")
        XCTAssertEqual(try fetchAllRows().count, 1)
    }

    func test_duplicateRowWithUnreadableColumn_movesItToTheWinner() throws {
        let unreadable = Data("written by a newer build".utf8)
        let olderRow = try StoredProfile.make(from: .fresh)
        olderRow.mealsData = unreadable
        olderRow.updatedAt = day
        let newerRow = try StoredProfile.make(from: .fresh)
        newerRow.updatedAt = day.addingTimeInterval(3600)

        try insertRows([olderRow, newerRow])
        _ = repo.loadProfile()

        let rows = try fetchAllRows()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.mealsData, unreadable)
    }

    func test_duplicateRowWithUnreadableColumn_isKeptWhenTheWinnerHasData() throws {
        let olderRow = try StoredProfile.make(from: .fresh)
        olderRow.mealsData = Data("written by a newer build".utf8)
        olderRow.updatedAt = day
        let newerRow = try StoredProfile.make(from: baseProfile())
        newerRow.updatedAt = day.addingTimeInterval(3600)

        try insertRows([olderRow, newerRow])
        let loaded = try XCTUnwrap(repo.loadProfile())

        XCTAssertEqual(loaded.mealHistory.map(\.name), ["Base meal"])
        XCTAssertEqual(try fetchAllRows().count, 2)
    }

    func test_keptDuplicateRow_isNotMergedAgain_soADeletedHabitStaysDeleted() throws {
        let olderRow = try StoredProfile.make(from: baseProfile())
        olderRow.mealsData = Data("written by a newer build".utf8)
        olderRow.updatedAt = day
        let newerRow = try StoredProfile.make(from: baseProfile())
        newerRow.updatedAt = day.addingTimeInterval(3600)
        try insertRows([olderRow, newerRow])

        var loaded = try XCTUnwrap(repo.loadProfile())
        loaded.habits = []
        repo.saveProfile(loaded)

        XCTAssertEqual(try XCTUnwrap(repo.loadProfile()).habits, [])
        XCTAssertEqual(try fetchAllRows().count, 2)
    }

    func test_reconcile_mealOnBothRows_isCountedOnce() {
        var shared = UserProfile.fresh
        LifestyleDataLogic.logMealEntry(into: &shared, entry: meal("Shared"))
        var primary = shared
        LifestyleDataLogic.logMealEntry(into: &primary, entry: meal("Primary"))
        var other = shared
        LifestyleDataLogic.logMealEntry(into: &other, entry: meal("Other"))

        let merged = ProfileMergeEngine.reconcile(primary, with: other)

        XCTAssertEqual(Set(merged.mealHistory.map(\.name)), ["Shared", "Primary", "Other"])
        XCTAssertEqual(LifestyleDataLogic.consumption(in: merged, for: day).caloriesKcal, 3 * 550)
    }

    func test_reconcile_sameHabitCheckedOnBothRowsSameDay_keepsOneEntryWithTheLargerValue() {
        let hydrate = habit("Hydrate")
        var primary = UserProfile.fresh
        primary.habits = [hydrate]
        primary.habitEntries = [HabitEntry(habitId: hydrate.id, date: day, value: 2)]
        var other = primary
        other.habitEntries = [HabitEntry(habitId: hydrate.id, date: day, value: 5)]

        let merged = ProfileMergeEngine.reconcile(primary, with: other)

        XCTAssertEqual(merged.habitEntries.map(\.value), [5])
        XCTAssertEqual(merged.habitEntries.map(\.id), primary.habitEntries.map(\.id))
    }

    func test_reconcile_outcomeCheckInOnBothRowsSameDay_keepsTheNewerOne() {
        var primary = UserProfile.fresh
        primary.outcomeHistory = [OutcomeEntry(date: day, energy: 2, sleepQuality: 2, recovery: 2, mood: 2, focus: 2,
                                               updatedAt: day)]
        var other = UserProfile.fresh
        other.outcomeHistory = [OutcomeEntry(date: day, energy: 4, sleepQuality: 4, recovery: 4, mood: 4, focus: 4,
                                             updatedAt: day.addingTimeInterval(600))]

        let merged = ProfileMergeEngine.reconcile(primary, with: other)

        XCTAssertEqual(merged.outcomeHistory.map(\.energy), [4])
    }

    func test_reconcile_waterOnBothRowsSameDay_addsTheOtherRowsWater() {
        var primary = UserProfile.fresh
        LifestyleDataLogic.logWater(into: &primary, fluidOunces: 8, date: day)
        var other = UserProfile.fresh
        LifestyleDataLogic.logWater(into: &other, fluidOunces: 16, date: day)

        let merged = ProfileMergeEngine.reconcile(primary, with: other)

        XCTAssertEqual(LifestyleDataLogic.consumption(in: merged, for: day).waterFluidOunces, 24)
    }

    func test_reconcile_rowsCopiedFromOneHistory_doNotDoubleTheirWater() {
        var primary = UserProfile.fresh
        LifestyleDataLogic.logMealEntry(into: &primary, entry: meal("Shared lunch"))
        LifestyleDataLogic.logWater(into: &primary, fluidOunces: 8, date: day)
        var other = primary
        LifestyleDataLogic.logWater(into: &other, fluidOunces: 4, date: day)

        let identical = ProfileMergeEngine.reconcile(primary, with: primary)
        let diverged = ProfileMergeEngine.reconcile(primary, with: other)

        XCTAssertEqual(LifestyleDataLogic.consumption(in: identical, for: day).waterFluidOunces, 8)
        XCTAssertEqual(LifestyleDataLogic.consumption(in: diverged, for: day).waterFluidOunces, 12)
    }

    func test_reconcile_legacyWorkoutsOnTheOtherRow_areKept() {
        var other = UserProfile.fresh
        other.workoutHistory = [WorkoutEntry(date: day, name: "Run", sets: 1, reps: 1, durationMinutes: 30)]

        let merged = ProfileMergeEngine.reconcile(UserProfile.fresh, with: other)

        XCTAssertEqual(merged.workoutHistory.map(\.id), other.workoutHistory.map(\.id))
    }

    func test_reconcile_freshWinnerAndCustomizedTodayLayout_adoptsTheCustomLayout() {
        var other = UserProfile.fresh
        other.todayLayout.setHidden(.momentum, true)

        let merged = ProfileMergeEngine.reconcile(UserProfile.fresh, with: other)

        XCTAssertEqual(merged.todayLayout, other.todayLayout)
    }

    func test_reconcile_bothRowsCustomizeTodayLayout_keepsTheWinnersLayout() {
        var primary = UserProfile.fresh
        primary.todayLayout.setHidden(.habits, true)
        var other = UserProfile.fresh
        other.todayLayout.setHidden(.momentum, true)

        let merged = ProfileMergeEngine.reconcile(primary, with: other)

        XCTAssertEqual(merged.todayLayout, primary.todayLayout)
    }

    // MARK: - Stale in-memory state

    func test_saveSinceBaseline_keepsAColumnAnotherDeviceChanged() throws {
        let base = baseProfile()
        repo.saveProfile(base)
        var remote = base
        remote.habitEntries.append(HabitEntry(habitId: base.habits[0].id, date: day))
        repo.saveProfile(remote)

        var local = base
        local.name = "Renamed here"
        repo.saveProfile(local, since: base)

        let loaded = try XCTUnwrap(repo.loadProfile())
        XCTAssertEqual(loaded.name, "Renamed here")
        XCTAssertEqual(loaded.habitEntries.count, 1,
                       "A column this device didn't edit must keep the other device's check-in")
    }

    func test_saveSinceBaseline_replaysThisDevicesMealOntoAnotherDevicesDiary() throws {
        var base = UserProfile.fresh
        LifestyleDataLogic.logMealEntry(into: &base, entry: meal("Breakfast"))
        repo.saveProfile(base)
        var remote = base
        LifestyleDataLogic.logMealEntry(into: &remote, entry: meal("iPad lunch"))
        repo.saveProfile(remote)

        var local = base
        LifestyleDataLogic.logMealEntry(into: &local, entry: meal("iPhone dinner"))
        repo.saveProfile(local, since: base)

        let loaded = try XCTUnwrap(repo.loadProfile())
        XCTAssertEqual(Set(loaded.mealHistory.map(\.name)), ["Breakfast", "iPad lunch", "iPhone dinner"])
        XCTAssertEqual(LifestyleDataLogic.consumption(in: loaded, for: day).caloriesKcal, 3 * 550)
    }

    func test_saveSinceBaseline_keepsAnotherDevicesWeighInAndHabitCheckIn() throws {
        let base = baseProfile()
        repo.saveProfile(base)
        let nextDay = day.addingTimeInterval(86_400)
        var remote = base
        remote.weightHistory.append(WeightEntry(date: day, kg: 80))
        remote.habitEntries.append(HabitEntry(habitId: base.habits[0].id, date: day))
        repo.saveProfile(remote)

        var local = base
        local.weightHistory.append(WeightEntry(date: nextDay, kg: 79))
        local.habitEntries.append(HabitEntry(habitId: base.habits[0].id, date: nextDay))
        repo.saveProfile(local, since: base)

        let loaded = try XCTUnwrap(repo.loadProfile())
        XCTAssertEqual(loaded.weightHistory.map(\.kg), [80, 79])
        XCTAssertEqual(loaded.habitEntries.count, 2)
    }

    func test_saveSinceBaseline_newRecipeHereKeepsTargetsChangedElsewhere() throws {
        let base = baseProfile()
        repo.saveProfile(base)
        var remote = base
        remote.nutritionTargets = NutritionTargets(calories: 2400, proteinG: 180, carbsG: 240, fatG: 80, fiberG: 30)
        repo.saveProfile(remote)

        var local = base
        local.recipes.append(Recipe(name: "Overnight oats", updatedAt: day))
        repo.saveProfile(local, since: base)

        let loaded = try XCTUnwrap(repo.loadProfile())
        XCTAssertEqual(loaded.nutritionTargets, remote.nutritionTargets)
        XCTAssertEqual(loaded.recipes.map(\.name), ["Overnight oats"])
    }

    func test_saveSinceBaseline_deletingALabHereKeepsALabAddedElsewhere() throws {
        var base = baseProfile()
        let old = LabValue(date: day, panel: .tsh, value: 2.1)
        base.labHistory = [old]
        repo.saveProfile(base)
        var remote = base
        let added = LabValue(date: day, panel: .hba1c, value: 5.2)
        remote.labHistory.append(added)
        repo.saveProfile(remote)

        var local = base
        local.labHistory.removeAll()
        repo.saveProfile(local, since: base)

        XCTAssertEqual(try XCTUnwrap(repo.loadProfile()).labHistory.map(\.id), [added.id])
    }

    // MARK: - Unreadable columns

    func test_unreadableSliceColumn_isLeftUntouchedBySave() throws {
        let row = try StoredProfile.make(from: baseProfile())
        let unreadable = Data("written by a newer build".utf8)
        row.mealsData = unreadable

        var decoded = try row.toUserProfile()
        XCTAssertTrue(decoded.mealHistory.isEmpty)
        decoded.habitEntries.append(HabitEntry(habitId: decoded.habits[0].id, date: day))
        try row.update(from: decoded)

        XCTAssertEqual(row.mealsData, unreadable, "An unreadable column must survive a save untouched")
        XCTAssertEqual(try row.toUserProfile().habitEntries.count, 1)
    }

    func test_unreadableGoals_launchSaveKeepsTheRestOfTheProfile() throws {
        var profile = baseProfile()
        profile.weightHistory = [WeightEntry(date: day, kg: 80)]
        let row = try StoredProfile.make(from: profile)
        row.goalsData = Data("not a goal list".utf8)
        try insertRows([row])

        let store = DataStore()
        store.flushPendingSave()

        let loaded = try XCTUnwrap(repo.loadProfile())
        XCTAssertEqual(loaded.name, profile.name)
        XCTAssertEqual(loaded.habits.map(\.id), profile.habits.map(\.id))
        XCTAssertEqual(loaded.weightHistory.map(\.id), profile.weightHistory.map(\.id))
    }

    func test_mealFromANewerBuild_isHiddenAndKept_whileANewMealSaves() throws {
        repo.saveProfile(baseProfile())
        try editStoredMeals { meals in
            var future = meals[0]
            future["id"] = UUID().uuidString
            future["category"] = "brunch"
            meals.append(future)
        }

        let loaded = try XCTUnwrap(repo.loadProfile())
        XCTAssertEqual(loaded.mealHistory.map(\.name), ["Base meal"])
        var edited = loaded
        LifestyleDataLogic.logMealEntry(into: &edited, entry: meal("New lunch"))
        repo.beginSaveBatch()
        repo.saveProfile(edited, since: loaded)

        XCTAssertFalse(repo.commitDidFail)
        XCTAssertEqual(Set(try XCTUnwrap(repo.loadProfile()).mealHistory.map(\.name)), ["Base meal", "New lunch"])
        let stored = String(decoding: try XCTUnwrap(loadStoredRow()?.mealsData), as: UTF8.self)
        XCTAssertTrue(stored.contains("brunch"), "The newer build's meal must survive this build's save")
    }

    func test_fieldFromANewerBuild_survivesSavingAnotherMeal() throws {
        repo.saveProfile(baseProfile())
        try editStoredMeals { meals in meals[0]["addedByNewerBuild"] = "kept" }

        let loaded = try XCTUnwrap(repo.loadProfile())
        var edited = loaded
        LifestyleDataLogic.logMealEntry(into: &edited, entry: meal("New lunch"))
        repo.saveProfile(edited, since: loaded)

        let stored = String(decoding: try XCTUnwrap(loadStoredRow()?.mealsData), as: UTF8.self)
        XCTAssertTrue(stored.contains("addedByNewerBuild"))
        XCTAssertTrue(stored.contains("New lunch"))
    }

    func test_workoutMigrationMarker_survivesARoundTrip() throws {
        var profile = baseProfile()
        profile.workoutLegacyMigrationCompleted = true

        let row = try StoredProfile.make(from: profile)

        XCTAssertTrue(try row.toUserProfile().workoutLegacyMigrationCompleted)
    }

    // MARK: - Apple Health imports

    func test_healthImportedWeight_staysOutOfTheSyncedColumn_butLoads() throws {
        let imported = WeightEntry(date: day, kg: 81)
        XCTAssertTrue(repo.recordHealthWeightImports([imported]))
        var profile = baseProfile()
        profile.weightHistory = [imported]

        repo.saveProfile(profile)

        let synced = try XCTUnwrap(loadStoredRow()?.weightHistoryData)
        XCTAssertFalse(String(decoding: synced, as: UTF8.self).contains(imported.id.uuidString))
        XCTAssertEqual(repo.loadProfile()?.weightHistory.map(\.id), [imported.id])
    }

    func test_deletedHealthImport_isDismissed() {
        let imported = WeightEntry(date: day, kg: 81)
        XCTAssertTrue(repo.recordHealthWeightImports([imported]))

        repo.dismissHealthWeight(id: imported.id)

        XCTAssertTrue(repo.dismissedHealthWeightIDs.contains(imported.id))
        repo.saveProfile(baseProfile())
        XCTAssertEqual(repo.loadProfile()?.weightHistory, [])
    }

    // MARK: - Helpers

    private func loadStoredRow() throws -> StoredProfile? {
        try fetchAllRows().first
    }

    private func fetchAllRows() throws -> [StoredProfile] {
        try XCTUnwrap(repo.contextForTesting)
            .fetch(FetchDescriptor<StoredProfile>())
    }

    /// Rewrites the stored meal column as a newer build would.
    private func editStoredMeals(_ change: (inout [[String: Any]]) -> Void) throws {
        let row = try XCTUnwrap(loadStoredRow())
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(row.mealsData)) as? [String: Any]
        )
        var meals = try XCTUnwrap(root["mealHistory"] as? [[String: Any]])
        change(&meals)
        root["mealHistory"] = meals
        row.mealsData = try JSONSerialization.data(withJSONObject: root)
        try XCTUnwrap(repo.contextForTesting).save()
    }

    private func insertRows(_ rows: [StoredProfile]) throws {
        let context = try XCTUnwrap(repo.contextForTesting)
        for row in rows { context.insert(row) }
        try context.save()
    }
}
