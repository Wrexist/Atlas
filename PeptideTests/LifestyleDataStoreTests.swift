import XCTest
@testable import Peptide

@MainActor
final class LifestyleDataStoreTests: XCTestCase {

    private func makeStore() -> DataStore {
        // The default DataStore initializer attaches a real persistence
        // service; we don't mind because every assertion below operates
        // on the in-memory `profile` snapshot before any save round-trip.
        DataStore(seedSampleData: false)
    }

    // MARK: - Weight history

    func test_logWeight_appendsEntry() {
        let store = makeStore()
        let initialCount = store.profile.weightHistory.count
        store.logWeight(kg: 80.5)
        XCTAssertEqual(store.profile.weightHistory.count, initialCount + 1)
        XCTAssertEqual(store.profile.weightHistory.last?.kg, 80.5)
    }

    /// Logging twice on the same calendar day should leave a single entry —
    /// the sparkline shows one point per day, so duplicates would crowd the
    /// trend without conveying real change.
    func test_logWeight_sameDay_replacesExistingEntry() {
        let store = makeStore()
        let today = Date()
        store.logWeight(kg: 80.0, date: today)
        store.logWeight(kg: 80.5, date: today)
        let sameDayEntries = store.profile.weightHistory.filter {
            Calendar.current.isDate($0.date, inSameDayAs: today)
        }
        XCTAssertEqual(sameDayEntries.count, 1)
        XCTAssertEqual(sameDayEntries.first?.kg, 80.5)
    }

    func test_logWeight_keepsArraySorted() {
        let store = makeStore()
        let now = Date()
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now)!
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!

        store.logWeight(kg: 80.0, date: yesterday)
        store.logWeight(kg: 80.5, date: now)
        store.logWeight(kg: 79.5, date: twoDaysAgo)

        let dates = store.profile.weightHistory.map(\.date)
        XCTAssertEqual(dates, dates.sorted())
    }

    func test_deleteWeight_removesEntryById() {
        let store = makeStore()
        store.logWeight(kg: 80.0)
        guard let entry = store.profile.weightHistory.last else {
            return XCTFail("expected at least one entry after logWeight")
        }
        store.deleteWeight(id: entry.id)
        XCTAssertFalse(store.profile.weightHistory.contains(where: { $0.id == entry.id }))
    }

    // MARK: - Consumption

    func test_consumption_unloggedDay_returnsEmptyBucket() {
        let store = makeStore()
        let bucket = store.consumption(for: Date())
        XCTAssertEqual(bucket.caloriesKcal, 0)
        XCTAssertEqual(bucket.proteinG, 0)
        XCTAssertEqual(bucket.waterOz, 0)
    }

    func test_logMeal_accumulatesIntoTodaysBucket() {
        let store = makeStore()
        store.logMeal(calories: 500, proteinG: 30, carbsG: 50, fatG: 20)
        store.logMeal(calories: 700, proteinG: 50, carbsG: 60, fatG: 25)
        let bucket = store.consumption(for: Date())
        XCTAssertEqual(bucket.caloriesKcal, 1200)
        XCTAssertEqual(bucket.proteinG, 80)
        XCTAssertEqual(bucket.carbsG, 110)
        XCTAssertEqual(bucket.fatG, 45)
    }

    func test_logWater_accumulatesIntoTodaysBucket() {
        let store = makeStore()
        store.logWater(oz: 8)
        store.logWater(oz: 17)
        XCTAssertEqual(store.consumption(for: Date()).waterOz, 25)
    }

    // MARK: - Trend math

    func test_weeklyDelta_noEntries_returnsZero() {
        XCTAssertEqual(WeightTrend.weeklyDelta(in: []), 0, accuracy: 0.001)
    }

    func test_weeklyDelta_onlyOneEntry_returnsZero() {
        let entry = WeightEntry(date: Date(), kg: 80)
        XCTAssertEqual(WeightTrend.weeklyDelta(in: [entry]), 0, accuracy: 0.001)
    }

    func test_weeklyDelta_lastMinusBaseline() {
        let cal = Calendar.current
        let now = Date()
        let eightDaysAgo = cal.date(byAdding: .day, value: -8, to: now)!
        let history = [
            WeightEntry(date: eightDaysAgo, kg: 80.0),
            WeightEntry(date: now,          kg: 79.5),
        ]
        XCTAssertEqual(WeightTrend.weeklyDelta(in: history), -0.5, accuracy: 0.001)
    }
}
