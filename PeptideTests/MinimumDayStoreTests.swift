import XCTest
@testable import Peptide

/// The minimum day as the store keeps it, and the monthly freeze spent
/// without a prompt.
@MainActor
final class MinimumDayStoreTests: XCTestCase {

    private let calendar = Calendar.current

    override func setUp() async throws {
        try await super.setUp()
        SwiftDataRepository.shared.configureForTesting()
    }

    /// `DataStore.current` keeps the last store alive, so its debounced
    /// save could land in the next test.
    override func tearDown() async throws {
        DataStore.current = nil
        SwiftDataRepository.shared.deleteAll()
        try await super.tearDown()
    }

    private func noon(daysAgo: Int, from now: Date) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return day.addingTimeInterval(12 * 3600)
    }

    private func logLunch(_ store: DataStore, daysAgo: Int, now: Date, proteinG: Int = 40) {
        store.logMealEntry(
            MealEntry(date: noon(daysAgo: daysAgo, from: now), category: .lunch, name: "Lunch",
                      calories: 500, proteinG: proteinG, carbsG: 50, fatG: 15, source: .custom)
        )
    }

    // MARK: - Recording

    func test_recordMinimumDays_metToday_recordsOnce() {
        let store = DataStore(seedSampleData: false)
        let now = Date()
        store.profile.nutritionTargets = NutritionTargets(calories: 2000, proteinG: 30, carbsG: 200, fatG: 60, fiberG: 25)
        logLunch(store, daysAgo: 0, now: now)

        XCTAssertTrue(store.recordMinimumDays(now: now, stepsOn: { _ in nil }))
        XCTAssertFalse(store.recordMinimumDays(now: now, stepsOn: { _ in nil }))
        XCTAssertEqual(store.minimumDay.metDayKeys, [DayKey.compact(now, calendar: calendar)])
    }

    func test_recordMinimumDays_proteinShort_recordsNothing() {
        let store = DataStore(seedSampleData: false)
        let now = Date()
        store.profile.nutritionTargets = NutritionTargets(calories: 2000, proteinG: 150, carbsG: 200, fatG: 60, fiberG: 25)
        logLunch(store, daysAgo: 0, now: now)

        XCTAssertFalse(store.recordMinimumDays(now: now, stepsOn: { _ in nil }))
        XCTAssertEqual(store.minimumDaySummary(todaySteps: nil, now: now).status, .start)
    }

    func test_setMinimumDayParts_stricterChoice_keepsRecordedDays() {
        let store = DataStore(seedSampleData: false)
        let now = Date()
        logLunch(store, daysAgo: 1, now: now)
        store.recordMinimumDays(now: now, stepsOn: { _ in nil })

        store.setMinimumDayParts([.checkIn])
        store.recordMinimumDays(now: now, stepsOn: { _ in nil })

        XCTAssertEqual(store.minimumDay.parts, [.checkIn])
        XCTAssertEqual(store.minimumDay.metDayKeys.count, 1)
    }

    func test_minimumDaySummary_walkBelowSteps_isNotMet() {
        let store = DataStore(seedSampleData: false)
        let now = Date()
        store.setMinimumDayParts([.logFood, .walk])
        logLunch(store, daysAgo: 0, now: now)

        XCTAssertNotEqual(store.minimumDaySummary(todaySteps: 300, now: now).status, .doneToday)
        XCTAssertEqual(store.minimumDaySummary(todaySteps: 1_200, now: now).status, .doneToday)
    }

    // MARK: - Automatic forgiveness

    func test_forgive_mealStreakBrokenByYesterday_spendsFreezeOnYesterday() {
        let store = DataStore(seedSampleData: false)
        let now = Date()
        logLunch(store, daysAgo: 2, now: now)
        logLunch(store, daysAgo: 3, now: now)
        XCTAssertEqual(LifestyleDataLogic.mealLoggingStreak(in: store.profile, asOf: now), 0)

        store.forgiveMissedDayIfNeeded(now: now)

        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        XCTAssertTrue(store.profile.streakFreezeDays.contains(DayKey.compact(yesterday, calendar: calendar)))
        XCTAssertEqual(LifestyleDataLogic.mealLoggingStreak(in: store.profile, asOf: now), 3)
    }

    func test_forgive_yesterdaysMealsArriveLater_handsTheFreezeBack() {
        let store = DataStore(seedSampleData: false)
        let now = Date()
        logLunch(store, daysAgo: 2, now: now)
        logLunch(store, daysAgo: 3, now: now)
        store.forgiveMissedDayIfNeeded(now: now)
        XCTAssertEqual(store.profile.streakFreezeDays.count, 1)

        logLunch(store, daysAgo: 1, now: now)
        store.forgiveMissedDayIfNeeded(now: now)

        XCTAssertTrue(store.profile.streakFreezeDays.isEmpty)
        XCTAssertEqual(LifestyleDataLogic.mealLoggingStreak(in: store.profile, asOf: now), 3)
    }

    func test_forgive_runTwice_spendsOnce() {
        let store = DataStore(seedSampleData: false)
        let now = Date()
        logLunch(store, daysAgo: 2, now: now)
        logLunch(store, daysAgo: 3, now: now)

        store.forgiveMissedDayIfNeeded(now: now)
        store.forgiveMissedDayIfNeeded(now: now)

        XCTAssertEqual(store.profile.streakFreezeDays.count, 1)
    }

    func test_forgive_twoMissedDays_spendsNothing() {
        let store = DataStore(seedSampleData: false)
        let now = Date()
        logLunch(store, daysAgo: 3, now: now)
        logLunch(store, daysAgo: 4, now: now)

        store.forgiveMissedDayIfNeeded(now: now)

        XCTAssertTrue(store.profile.streakFreezeDays.isEmpty)
    }

    func test_forgive_nothingToSave_spendsNothing() {
        let store = DataStore(seedSampleData: false)
        let now = Date()
        logLunch(store, daysAgo: 1, now: now)

        store.forgiveMissedDayIfNeeded(now: now)

        XCTAssertTrue(store.profile.streakFreezeDays.isEmpty)
    }

    // MARK: - Sync

    func test_storedProfile_roundTrip_keepsMinimumDay() throws {
        var profile = UserProfile.fresh
        profile.minimumDay = MinimumDay(parts: [.walk, .checkIn], metDayKeys: ["20261201", "20261202"])

        let roundTripped = try StoredProfile.make(from: profile).toUserProfile()

        XCTAssertEqual(roundTripped.minimumDay, profile.minimumDay)
    }

    func test_rebasing_dayRecordedHere_keepsPartsChosenElsewhere_andBothDays() {
        var baseline = UserProfile.fresh
        baseline.minimumDay = MinimumDay(parts: [.logFood, .protein], metDayKeys: ["20261130"])
        var local = baseline
        local.minimumDay?.metDayKeys.insert("20261201")
        var remote = baseline
        remote.minimumDay = MinimumDay(parts: [.walk], metDayKeys: ["20261130", "20261129"])

        let merged = ProfileMergeEngine.rebasing(local: local, baseline: baseline, remote: remote)

        XCTAssertEqual(merged.minimumDay?.parts, [.walk])
        XCTAssertEqual(merged.minimumDay?.metDayKeys, ["20261129", "20261130", "20261201"])
    }

    func test_rebasing_firstRecordHere_doesNotOverrideRemoteChoice() {
        let baseline = UserProfile.fresh
        var local = baseline
        local.minimumDay = MinimumDay(parts: MinimumDay.default.parts, metDayKeys: ["20261201"])
        var remote = baseline
        remote.minimumDay = MinimumDay(parts: [.checkIn], metDayKeys: [])

        let merged = ProfileMergeEngine.rebasing(local: local, baseline: baseline, remote: remote)

        XCTAssertEqual(merged.minimumDay?.parts, [.checkIn])
        XCTAssertEqual(merged.minimumDay?.metDayKeys, ["20261201"])
    }

    func test_reconcile_unionsMetDays_keepsPrimaryParts() {
        var primary = UserProfile.fresh
        primary.minimumDay = MinimumDay(parts: [.walk], metDayKeys: ["20261201"])
        var other = UserProfile.fresh
        other.minimumDay = MinimumDay(parts: [.logFood], metDayKeys: ["20261130"])

        let merged = ProfileMergeEngine.reconcile(primary, with: other)

        XCTAssertEqual(merged.minimumDay?.parts, [.walk])
        XCTAssertEqual(merged.minimumDay?.metDayKeys, ["20261130", "20261201"])
    }
}
