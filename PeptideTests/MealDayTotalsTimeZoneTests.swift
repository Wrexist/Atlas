import XCTest
@testable import Peptide

/// The day's calorie total and the day's meal list must agree in any time
/// zone. The total used to come from a bucket keyed by the day the meal
/// was logged in, while the list filters `mealHistory` by the current
/// calendar day, so after a flight the two drifted apart. A time-zone
/// change is simulated by reading one profile with two calendars.
final class MealDayTotalsTimeZoneTests: XCTestCase {

    private func calendar(_ identifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: identifier))
        return calendar
    }

    private func date(_ calendar: Calendar, day: Int, hour: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour)))
    }

    private func meal(_ name: String, at date: Date, calories: Int, category: MealCategory) -> MealEntry {
        MealEntry(date: date, category: category, name: name, calories: calories,
                  proteinG: calories / 20, carbsG: calories / 10, fatG: calories / 40, source: .manual)
    }

    /// Adds `entry` to history and to the bucket of its day in `calendar`
    /// — what `logMealEntry` stores when that is the device's time zone.
    private func log(_ entry: MealEntry, into profile: inout UserProfile, calendar: Calendar) {
        profile.mealHistory.append(entry)
        let key = LifestyleDataLogic.consumptionKey(for: entry.date, calendar: calendar)
        var bucket = profile.dailyConsumption[key] ?? DailyConsumption(
            date: calendar.startOfDay(for: entry.date),
            caloriesKcal: 0, proteinG: 0, carbsG: 0, fatG: 0, waterOz: 0
        )
        bucket.caloriesKcal += entry.calories
        bucket.proteinG += entry.proteinG
        bucket.carbsG += entry.carbsG
        bucket.fatG += entry.fatG
        profile.dailyConsumption[key] = bucket
    }

    /// Lunch on Sunday 4 Oct and a snack at 01:00 on Monday 5 Oct, both
    /// logged in Stockholm. In New York the snack falls on Sunday evening.
    private func stockholmProfile() throws -> UserProfile {
        let stockholm = try calendar("Europe/Stockholm")
        var profile = UserProfile.fresh
        log(meal("Lunch", at: try date(stockholm, day: 4, hour: 12), calories: 500, category: .lunch),
            into: &profile, calendar: stockholm)
        log(meal("Snack", at: try date(stockholm, day: 5, hour: 1), calories: 300, category: .snack),
            into: &profile, calendar: stockholm)
        return profile
    }

    private func listedCalories(_ profile: UserProfile, on day: Date, _ calendar: Calendar) -> Int {
        LifestyleDataLogic.mealEntries(in: profile, for: day, calendar: calendar).reduce(0) { $0 + $1.calories }
    }

    func test_dayTotal_inTheTimeZoneMealsWereLoggedIn_matchesTheMealList() throws {
        let profile = try stockholmProfile()
        let stockholm = try calendar("Europe/Stockholm")

        for day in [try date(stockholm, day: 4, hour: 12), try date(stockholm, day: 5, hour: 12)] {
            let total = LifestyleDataLogic.consumption(in: profile, for: day, calendar: stockholm).caloriesKcal
            XCTAssertEqual(total, listedCalories(profile, on: day, stockholm))
        }
        XCTAssertEqual(LifestyleDataLogic.consumption(in: profile, for: try date(stockholm, day: 5, hour: 12),
                                                      calendar: stockholm).caloriesKcal, 300)
    }

    func test_dayTotal_afterFlyingToNewYork_matchesTheMealList() throws {
        let profile = try stockholmProfile()
        let newYork = try calendar("America/New_York")
        let sunday = try date(newYork, day: 4, hour: 12)
        let monday = try date(newYork, day: 5, hour: 12)

        let sundayTotal = LifestyleDataLogic.consumption(in: profile, for: sunday, calendar: newYork)
        let mondayTotal = LifestyleDataLogic.consumption(in: profile, for: monday, calendar: newYork)

        XCTAssertEqual(listedCalories(profile, on: sunday, newYork), 800)
        XCTAssertEqual(sundayTotal.caloriesKcal, 800)
        XCTAssertEqual(sundayTotal.proteinG, 25 + 15)
        XCTAssertEqual(listedCalories(profile, on: monday, newYork), 0)
        XCTAssertEqual(mondayTotal.caloriesKcal, 0)
    }

    func test_categoryBreakdown_afterTimeZoneChange_hasNoPhantomOther() throws {
        let profile = try stockholmProfile()
        let newYork = try calendar("America/New_York")

        let sunday = LifestyleDataLogic.mealsByCategory(in: profile, for: try date(newYork, day: 4, hour: 12),
                                                        calendar: newYork)
        let monday = LifestyleDataLogic.mealsByCategory(in: profile, for: try date(newYork, day: 5, hour: 12),
                                                        calendar: newYork)

        XCTAssertEqual(sunday.snack.calories, 300)
        XCTAssertEqual(sunday.other.calories, 0)
        XCTAssertEqual(sunday.totalCalories, 800)
        XCTAssertEqual(monday.totalCalories, 0)
    }

    func test_legacyAggregateWithoutEntries_stillCountsTowardTheDay() throws {
        let stockholm = try calendar("Europe/Stockholm")
        var profile = try stockholmProfile()
        let key = LifestyleDataLogic.consumptionKey(for: try date(stockholm, day: 4, hour: 12), calendar: stockholm)
        profile.dailyConsumption[key]?.caloriesKcal += 200

        let day = try date(stockholm, day: 4, hour: 12)
        let breakdown = LifestyleDataLogic.mealsByCategory(in: profile, for: day, calendar: stockholm)

        XCTAssertEqual(LifestyleDataLogic.consumption(in: profile, for: day, calendar: stockholm).caloriesKcal, 700)
        XCTAssertEqual(breakdown.other.calories, 200)
    }

    func test_deletingAMealAfterTimeZoneChange_removesItFromTheBucketItWasLoggedIn() throws {
        let stockholm = try calendar("Europe/Stockholm")
        let newYork = try calendar("America/New_York")
        var profile = try stockholmProfile()
        let snack = try XCTUnwrap(profile.mealHistory.first { $0.name == "Snack" })
        let mondayKey = LifestyleDataLogic.consumptionKey(for: snack.date, calendar: stockholm)

        LifestyleDataLogic.unlogMealEntry(from: &profile, id: snack.id)

        XCTAssertEqual(profile.dailyConsumption[mondayKey]?.caloriesKcal, 0)
        for day in [try date(newYork, day: 4, hour: 12), try date(newYork, day: 5, hour: 12)] {
            let total = LifestyleDataLogic.consumption(in: profile, for: day, calendar: newYork).caloriesKcal
            XCTAssertEqual(total, listedCalories(profile, on: day, newYork))
        }
    }
}
