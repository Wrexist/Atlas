import XCTest
@testable import Peptide

final class NutritionCoachEngineTests: XCTestCase {

    private let calendar = Calendar.current
    private let now = Date()

    /// Noon `daysAgo` days before today — clear of midnight and DST edges.
    private func noon(daysAgo: Int) -> Date {
        let today = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
        return calendar.date(byAdding: .hour, value: 12, to: day) ?? day
    }

    private func log(_ calories: Int, protein: Int, daysAgo: Int, into profile: inout UserProfile) {
        LifestyleDataLogic.logMealEntry(into: &profile, entry: MealEntry(
            date: noon(daysAgo: daysAgo),
            category: .lunch,
            name: "Meal",
            calories: calories,
            proteinG: protein,
            carbsG: 100,
            fatG: 50,
            source: .manual
        ))
    }

    private var loggedProfile: UserProfile {
        var profile = UserProfile.fresh
        profile.nutritionTargets = NutritionTargets(calories: 2000, proteinG: 150, carbsG: 200, fatG: 70, fiberG: 30)
        log(2000, protein: 160, daysAgo: 1, into: &profile)
        log(1800, protein: 140, daysAgo: 2, into: &profile)
        log(2200, protein: 150, daysAgo: 4, into: &profile)
        log(3000, protein: 90, daysAgo: 10, into: &profile)
        profile.weightHistory = [
            WeightEntry(date: noon(daysAgo: 20), kg: 85),
            WeightEntry(date: noon(daysAgo: 12), kg: 80),
            WeightEntry(date: noon(daysAgo: 2), kg: 79),
        ]
        return profile
    }

    func test_summary_averagesOnlyLoggedDaysInsideTheWeek() {
        let summary = NutritionCoachEngine.summary(of: loggedProfile, now: now, calendar: calendar)
        XCTAssertEqual(summary.days, 7)
        XCTAssertEqual(summary.loggedDays, 3)
        XCTAssertEqual(summary.averageCalories, 2000)
        XCTAssertEqual(summary.averageProteinG, 150)
        XCTAssertEqual(summary.averageCarbsG, 100)
    }

    func test_summary_countsDaysThatReachedProtein() {
        let summary = NutritionCoachEngine.summary(of: loggedProfile, now: now, calendar: calendar)
        XCTAssertEqual(summary.proteinDaysHit, 2)
    }

    func test_summary_weightTrendUsesLastTwoWeeksOnly() {
        let summary = NutritionCoachEngine.summary(of: loggedProfile, now: now, calendar: calendar)
        XCTAssertEqual(summary.weightChangeKg ?? 0, -1, accuracy: 0.001)
        XCTAssertEqual(summary.weightSpanDays, 10)
    }

    func test_brief_statesTargetsAdherenceAndTrend() {
        let summary = NutritionCoachEngine.summary(of: loggedProfile, now: now, calendar: calendar)
        let brief = NutritionCoachEngine.brief(summary, unit: .metric)
        XCTAssertTrue(brief.contains("Daily targets: 2000 kcal, protein 150 g"))
        XCTAssertTrue(brief.contains("Days with food logged: 3 of 7."))
        XCTAssertTrue(brief.contains("Protein target (150 g) reached on 2 of 3 logged days."))
        XCTAssertTrue(brief.contains("Weight trend: -1.0 kg over 10 days."))
        XCTAssertFalse(brief.contains("Meal"), "Meal names never leave the device")
    }

    func test_brief_emptyProfile_saysWhatIsMissing() {
        let summary = NutritionCoachEngine.summary(of: .fresh, now: now, calendar: calendar)
        let brief = NutritionCoachEngine.brief(summary, unit: .metric)
        XCTAssertNil(summary.averageCalories)
        XCTAssertTrue(brief.contains("Daily targets: not set."))
        XCTAssertTrue(brief.contains("no meals logged"))
        XCTAssertTrue(brief.contains("not enough weigh-ins"))
    }

    func test_formattedWeightChange_convertsForImperial() {
        XCTAssertEqual(NutritionCoachEngine.formattedWeightChange(-1, unit: .imperial), "-2.2 lb")
        XCTAssertEqual(NutritionCoachEngine.formattedWeightChange(0.5, unit: .metric), "+0.5 kg")
    }
}
