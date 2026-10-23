import XCTest
@testable import Peptide

/// Pins which history each reminder kind checks before it is skipped. A
/// wrong mapping (lunch checked against breakfast) nags a user who already
/// logged, or stays silent when the reminder is due.
@MainActor
final class DailyReminderSchedulerTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        return c
    }()

    /// Monday 2026-10-19 at the given hour.
    private func monday(_ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: hour)) ?? Date()
    }

    private func sunday(_ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: hour)) ?? Date()
    }

    private func meal(_ category: MealCategory, at date: Date) -> MealEntry {
        MealEntry(date: date, category: category, name: "Meal", calories: 400,
                  proteinG: 30, carbsG: 40, fatG: 10, source: .custom)
    }

    private func isDone(
        _ kind: DailyReminderKind,
        profile: UserProfile = .fresh,
        trainedDays: [Date] = []
    ) -> Bool {
        DailyReminderScheduler.isAlreadyDone(
            kind, day: monday(0), profile: profile, trainedDays: trainedDays, calendar: calendar
        )
    }

    func test_isAlreadyDone_weighInLoggedThatDay_isDone() {
        var profile = UserProfile.fresh
        profile.weightHistory = [WeightEntry(date: monday(7), kg: 80)]
        XCTAssertTrue(isDone(.weighIn, profile: profile))
    }

    func test_isAlreadyDone_weighInLoggedYesterday_isNotDone() {
        var profile = UserProfile.fresh
        profile.weightHistory = [WeightEntry(date: sunday(7), kg: 80)]
        XCTAssertFalse(isDone(.weighIn, profile: profile))
    }

    func test_isAlreadyDone_workoutOnATrainedDay_isDone() {
        XCTAssertTrue(isDone(.workout, trainedDays: [monday(18)]))
    }

    func test_isAlreadyDone_workoutTrainedYesterdayOnly_isNotDone() {
        XCTAssertFalse(isDone(.workout, trainedDays: [sunday(18)]))
    }

    func test_isAlreadyDone_eachMealLoggedInItsCategory_isDone() {
        let pairs: [(DailyReminderKind, MealCategory)] = [(.breakfast, .breakfast), (.lunch, .lunch), (.dinner, .dinner)]
        for (kind, category) in pairs {
            var profile = UserProfile.fresh
            profile.mealHistory = [meal(category, at: monday(12))]
            XCTAssertTrue(isDone(kind, profile: profile), "\(kind)")
        }
    }

    func test_isAlreadyDone_mealInAnotherCategorySameDay_isNotDone() {
        var profile = UserProfile.fresh
        profile.mealHistory = [meal(.breakfast, at: monday(8)), meal(.snack, at: monday(15))]
        XCTAssertFalse(isDone(.lunch, profile: profile))
        XCTAssertFalse(isDone(.dinner, profile: profile))
    }

    func test_isAlreadyDone_sameCategoryLoggedYesterday_isNotDone() {
        var profile = UserProfile.fresh
        profile.mealHistory = [meal(.lunch, at: sunday(12))]
        XCTAssertFalse(isDone(.lunch, profile: profile))
    }

    func test_isAlreadyDone_mealDoesNotCountAsWeighInOrWorkout() {
        var profile = UserProfile.fresh
        profile.mealHistory = [meal(.lunch, at: monday(12))]
        XCTAssertFalse(isDone(.weighIn, profile: profile))
        XCTAssertFalse(isDone(.workout, profile: profile))
    }
}
