import XCTest
@testable import Peptide

final class TodayChecklistEngineTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        return c
    }()

    /// Monday 2026-10-19 at the given hour.
    private func monday(_ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: hour)) ?? Date()
    }

    private func meal(_ category: MealCategory, at date: Date) -> MealEntry {
        MealEntry(date: date, category: category, name: "x", calories: 100, proteinG: 1, carbsG: 1, fatG: 1, source: .manual)
    }

    private func state(
        profile: UserProfile = .fresh,
        waterOz: Int = 0,
        trainedToday: Bool = false
    ) -> TodayChecklistEngine.State {
        TodayChecklistEngine.state(
            profile: profile,
            consumption: {
                var day = DailyConsumption.empty(on: monday(12))
                day.waterOz = waterOz
                return day
            }(),
            trainedToday: trainedToday,
            now: monday(12),
            calendar: calendar
        )
    }

    func test_freshProfile_nothingDone_breakfastNext() {
        let s = state()
        XCTAssertEqual(s.completedCount, 0)
        XCTAssertEqual(s.nextMeal, .breakfast)
        XCTAssertTrue(s.isTrainingDay, "No preferred days means every day is a training day")
    }

    func test_meals_doneOnlyWhenAllThreeMainMealsLoggedToday() {
        var profile = UserProfile.fresh
        let yesterday = calendar.date(byAdding: .day, value: -1, to: monday(19)) ?? Date()
        profile.mealHistory = [
            meal(.breakfast, at: monday(8)),
            meal(.lunch, at: monday(12)),
            meal(.dinner, at: yesterday),
            meal(.snack, at: monday(10)),
        ]
        XCTAssertFalse(state(profile: profile).isDone(.meals))
        XCTAssertEqual(state(profile: profile).nextMeal, .dinner)

        profile.mealHistory.append(meal(.dinner, at: monday(11)))
        XCTAssertTrue(state(profile: profile).isDone(.meals))
    }

    func test_restDay_countsAsDone() {
        var profile = UserProfile.fresh
        // 2026-10-19 is a Monday; train Tuesdays only.
        profile.trainingPreferences = TrainingPreferences(preferredDays: [.tuesday])
        let s = state(profile: profile)
        XCTAssertFalse(s.isTrainingDay)
        XCTAssertTrue(s.isDone(.training))
    }

    func test_trainingDay_needsAWorkout() {
        var profile = UserProfile.fresh
        profile.trainingPreferences = TrainingPreferences(preferredDays: [.monday])
        XCTAssertFalse(state(profile: profile).isDone(.training))
        XCTAssertTrue(state(profile: profile, trainedToday: true).isDone(.training))
    }

    func test_water_doneAtTarget() {
        XCTAssertFalse(state(waterOz: TodayChecklistEngine.waterTargetOz - 1).isDone(.water))
        XCTAssertTrue(state(waterOz: TodayChecklistEngine.waterTargetOz).isDone(.water))
    }

    func test_weight_usesTodaysLatestEntry() {
        var profile = UserProfile.fresh
        let yesterday = calendar.date(byAdding: .day, value: -1, to: monday(8)) ?? Date()
        profile.weightHistory = [
            WeightEntry(date: yesterday, kg: 80),
            WeightEntry(date: monday(7), kg: 82),
            WeightEntry(date: monday(9), kg: 81.5),
        ]
        XCTAssertEqual(state(profile: profile).weightTodayKg, 81.5)
    }

    func test_glass_matchesSmallestQuickAdd() {
        XCTAssertEqual(TodayChecklistEngine.glassFluidOunces(for: .imperial), 8)
        XCTAssertEqual(TodayChecklistEngine.glassFluidOunces(for: .metric) * 29.5735, 250, accuracy: 0.01)
    }
}
