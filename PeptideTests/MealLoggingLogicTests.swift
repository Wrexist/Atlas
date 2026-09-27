import XCTest
@testable import Peptide

/// Pure-logic coverage for the Meals tab's day browsing, "Log again",
/// portion scaling and exact water logging (`LifestyleDataLogic`).
final class MealLoggingLogicTests: XCTestCase {

    private let calendar = Calendar.current

    private func entry(
        name: String,
        at date: Date,
        calories: Int = 400,
        proteinG: Int = 30,
        carbsG: Int = 40,
        fatG: Int = 12,
        category: MealCategory = .lunch
    ) -> MealEntry {
        MealEntry(
            date: date,
            category: category,
            name: name,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            source: .manual
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - Portion scaling

    func test_scaledMacros_halfPortion_roundsEachMacro() {
        let meal = entry(name: "Bowl", at: Date(), calories: 455, proteinG: 31, carbsG: 40, fatG: 13)
        let scaled = LifestyleDataLogic.scaledMacros(of: meal, by: 0.5)
        XCTAssertEqual(scaled, LoggableMeal(calories: 228, proteinG: 16, carbsG: 20, fatG: 7))
    }

    func test_scaledMacros_oneAndAHalfAndDouble_scaleFromOriginal() {
        let meal = entry(name: "Bowl", at: Date(), calories: 400, proteinG: 30, carbsG: 41, fatG: 12)
        XCTAssertEqual(
            LifestyleDataLogic.scaledMacros(of: meal, by: 1.5),
            LoggableMeal(calories: 600, proteinG: 45, carbsG: 62, fatG: 18)
        )
        XCTAssertEqual(
            LifestyleDataLogic.scaledMacros(of: meal, by: 2),
            LoggableMeal(calories: 800, proteinG: 60, carbsG: 82, fatG: 24)
        )
    }

    func test_scaledMacros_factorOne_returnsOriginalValues() {
        let meal = entry(name: "Bowl", at: Date(), calories: 333, proteinG: 1, carbsG: 0, fatG: 7)
        XCTAssertEqual(
            LifestyleDataLogic.scaledMacros(of: meal, by: 1),
            LoggableMeal(calories: 333, proteinG: 1, carbsG: 0, fatG: 7)
        )
    }

    // MARK: - Recent meals

    func test_recentDistinctMeals_duplicateNames_keepsNewestOnly() {
        let base = date(2026, 9, 20, 12)
        let old = entry(name: "Oatmeal", at: base, calories: 300)
        let newer = entry(name: " oatmeal ", at: base.addingTimeInterval(3_600), calories: 350)
        let other = entry(name: "Salad", at: base.addingTimeInterval(1_800))

        let recent = LifestyleDataLogic.recentDistinctMeals(in: [old, other, newer])

        XCTAssertEqual(recent.map(\.id), [newer.id, other.id])
    }

    func test_recentDistinctMeals_moreThanLimit_capsAtEightNewestFirst() {
        let base = date(2026, 9, 1, 8)
        let history = (0..<12).map { i in
            entry(name: "Meal \(i)", at: base.addingTimeInterval(Double(i) * 3_600))
        }

        let recent = LifestyleDataLogic.recentDistinctMeals(in: history)

        XCTAssertEqual(recent.count, 8)
        XCTAssertEqual(recent.first?.name, "Meal 11")
        XCTAssertEqual(recent.last?.name, "Meal 4")
    }

    func test_recentDistinctMeals_blankName_isSkipped() {
        let recent = LifestyleDataLogic.recentDistinctMeals(in: [entry(name: "  ", at: Date())])
        XCTAssertTrue(recent.isEmpty)
    }

    // MARK: - Log again

    func test_relogged_copiesMealWithNewIDAndDate() {
        let original = entry(name: "Chili", at: date(2026, 9, 20, 19), category: .dinner)
        let when = date(2026, 9, 27, 12, 30)

        let copy = LifestyleDataLogic.relogged(original, at: when)

        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.date, when)
        XCTAssertEqual(copy.category, .dinner)
        XCTAssertEqual(copy.name, original.name)
        XCTAssertEqual(copy.calories, original.calories)
        XCTAssertEqual(copy.source, original.source)
    }

    // MARK: - Day browsing

    func test_mealDay_futureOffset_clampsToToday() {
        let now = date(2026, 9, 27, 15)
        XCTAssertEqual(LifestyleDataLogic.mealDay(offset: 3, from: now), date(2026, 9, 27))
        XCTAssertEqual(LifestyleDataLogic.mealDay(offset: -1, from: now), date(2026, 9, 26))
    }

    func test_logTimestamp_today_returnsNow() {
        let now = date(2026, 9, 27, 13, 5)
        XCTAssertEqual(LifestyleDataLogic.logTimestamp(on: date(2026, 9, 27), now: now), now)
    }

    func test_logTimestamp_pastDay_keepsCurrentClockTimeOnThatDay() {
        let now = date(2026, 9, 27, 13, 5)
        let stamped = LifestyleDataLogic.logTimestamp(on: date(2026, 9, 26), now: now)
        XCTAssertEqual(stamped, date(2026, 9, 26, 13, 5))
    }

    // MARK: - Water

    func test_logWater_metricOneLitre_readsBackAsExactlyOneThousandMillilitres() {
        var profile = UserProfile.fresh
        let day = date(2026, 9, 27, 9)

        LifestyleDataLogic.logWater(
            into: &profile,
            fluidOunces: LifestyleDataLogic.fluidOunces(millilitres: 1_000),
            date: day
        )

        let bucket = LifestyleDataLogic.consumption(in: profile, for: day)
        XCTAssertEqual(bucket.waterOz, 34, "whole-ounce total stays for existing readers")
        XCTAssertEqual(LifestyleDataLogic.displayedWater(bucket, unit: .metric), 1_000)
    }

    func test_logWater_fourQuarterLitres_sumToOneThousandMillilitres() {
        var profile = UserProfile.fresh
        let day = date(2026, 9, 27, 9)
        let glass = LifestyleDataLogic.fluidOunces(millilitres: 250)

        for _ in 0..<4 {
            LifestyleDataLogic.logWater(into: &profile, fluidOunces: glass, date: day)
        }

        let bucket = LifestyleDataLogic.consumption(in: profile, for: day)
        XCTAssertEqual(LifestyleDataLogic.displayedWater(bucket, unit: .metric), 1_000)
    }

    func test_logWater_undo_returnsDayToZeroWithNoRemainder() {
        var profile = UserProfile.fresh
        let day = date(2026, 9, 27, 9)
        let litre = LifestyleDataLogic.fluidOunces(millilitres: 1_000)

        LifestyleDataLogic.logWater(into: &profile, fluidOunces: litre, date: day)
        LifestyleDataLogic.logWater(into: &profile, fluidOunces: -litre, date: day)

        let bucket = LifestyleDataLogic.consumption(in: profile, for: day)
        XCTAssertEqual(bucket.waterOz, 0)
        XCTAssertNil(bucket.waterOzRemainder)
    }

    func test_logWater_undoLargerThanTotal_clampsAtZero() {
        var profile = UserProfile.fresh
        let day = date(2026, 9, 27, 9)

        LifestyleDataLogic.logWater(into: &profile, oz: 8, date: day)
        LifestyleDataLogic.logWater(into: &profile, fluidOunces: -32, date: day)

        XCTAssertEqual(LifestyleDataLogic.consumption(in: profile, for: day).waterFluidOunces, 0)
    }

    func test_dailyConsumption_legacyJSONWithoutRemainder_decodes() throws {
        let json = #"{"date":0,"caloriesKcal":0,"proteinG":0,"carbsG":0,"fatG":0,"waterOz":34}"#
        let bucket = try JSONDecoder().decode(DailyConsumption.self, from: Data(json.utf8))
        XCTAssertEqual(bucket.waterOz, 34)
        XCTAssertNil(bucket.waterOzRemainder)
        XCTAssertEqual(bucket.waterFluidOunces, 34)
    }
}
