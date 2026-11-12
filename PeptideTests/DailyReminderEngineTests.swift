import XCTest
@testable import Peptide

final class DailyReminderEngineTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        return c
    }()

    /// Monday 2026-10-19 at the given time.
    private func monday(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: hour, minute: minute)) ?? Date()
    }

    private func settings(_ enabled: DailyReminderKind...) -> DailyReminderSettings {
        var s = DailyReminderSettings.defaults(training: nil)
        for kind in enabled { s.slots[kind]?.isEnabled = true }
        return s
    }

    func test_allOff_plansNothing() {
        let plan = DailyReminderEngine.plan(
            settings: .defaults(training: nil), trainingWeekdays: [], now: monday(6), calendar: calendar
        ) { _, _ in false }
        XCTAssertTrue(plan.isEmpty)
    }

    /// Reminders delivered over `days` days if Atlas stayed closed.
    private func fired(_ plan: [DailyReminderEngine.Planned], after now: Date, days: Int) -> [Date] {
        plan.map(\.trigger).fireDates(after: now, days: days, calendar: calendar)
    }

    func test_enabledMeal_isOneDailyRepeatFromToday() {
        let plan = DailyReminderEngine.plan(
            settings: settings(.lunch), trainingWeekdays: [], now: monday(6), calendar: calendar
        ) { _, _ in false }
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.first?.trigger.repeats, true)
        XCTAssertEqual(plan.first?.fireDate, monday(12, 30))
    }

    func test_appNotOpenedForThreeWeeks_mealAndWeighInKeepFiring() {
        let plan = DailyReminderEngine.plan(
            settings: settings(.lunch, .weighIn), trainingWeekdays: [], now: monday(6), calendar: calendar
        ) { _, _ in false }
        XCTAssertEqual(fired(plan, after: monday(6), days: 21).count, 2 * 21)
    }

    func test_timeAlreadyPassedToday_startsTomorrow() {
        let plan = DailyReminderEngine.plan(
            settings: settings(.lunch), trainingWeekdays: [], now: monday(13), calendar: calendar
        ) { _, _ in false }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: monday(12, 30))
        XCTAssertEqual(plan.first?.fireDate, tomorrow)
    }

    func test_alreadyLoggedToday_skipsOnlyToday() {
        let today = monday(9)
        let plan = DailyReminderEngine.plan(
            settings: settings(.lunch), trainingWeekdays: [], now: today, calendar: calendar
        ) { _, day in calendar.isDate(day, inSameDayAs: today) }
        let dates = fired(plan, after: today, days: 14)
        XCTAssertEqual(dates.count, 13)
        XCTAssertFalse(dates.contains { calendar.isDate($0, inSameDayAs: today) })
    }

    func test_workout_onlyOnTrainingDays() {
        // Tuesday only (Calendar weekday 3).
        let plan = DailyReminderEngine.plan(
            settings: settings(.workout), trainingWeekdays: [Weekday.tuesday.calendarWeekdayValue], now: monday(6), calendar: calendar
        ) { _, _ in false }
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.first?.trigger.repeats, true)
        XCTAssertEqual(plan.first?.trigger.components.weekday, 3)
    }

    func test_identifiers_areUniquePerKindAndSlot_andInDailyNamespace() {
        let plan = DailyReminderEngine.plan(
            settings: settings(.weighIn, .breakfast, .lunch, .dinner, .workout), trainingWeekdays: [], now: monday(0), calendar: calendar
        ) { _, _ in false }
        XCTAssertEqual(plan.count, DailyReminderKind.allCases.count)
        XCTAssertEqual(Set(plan.map(\.id)).count, plan.count)
        XCTAssertTrue(plan.allSatisfy { $0.id.hasPrefix(NotificationService.dailyIDPrefix) })
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted())
    }

    func test_everyKindDoneToday_staysWithinRequestLimit() {
        let today = monday(0)
        let plan = DailyReminderEngine.plan(
            settings: settings(.weighIn, .breakfast, .lunch, .dinner, .workout), trainingWeekdays: [], now: today, calendar: calendar
        ) { _, day in calendar.isDate(day, inSameDayAs: today) }
        XCTAssertEqual(plan.count, DailyReminderEngine.requestLimit)
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted())
    }

    func test_previousDayMeals_matchesCategoryAndYesterdayOnly() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: monday(8)) ?? Date()
        let history = [
            MealEntry(date: yesterday, category: .breakfast, name: "Oats", calories: 400, proteinG: 20, carbsG: 60, fatG: 8, source: .manual),
            MealEntry(date: yesterday, category: .lunch, name: "Salad", calories: 500, proteinG: 30, carbsG: 30, fatG: 20, source: .manual),
            MealEntry(date: monday(8), category: .breakfast, name: "Eggs", calories: 300, proteinG: 25, carbsG: 2, fatG: 20, source: .manual),
        ]
        let repeated = DailyReminderEngine.previousDayMeals(.breakfast, before: monday(8, 30), in: history, calendar: calendar)
        XCTAssertEqual(repeated.map(\.name), ["Oats"])
    }

    func test_parsedWeight_acceptsCommaAndSuffix() {
        XCTAssertEqual(DailyReminderEngine.parsedWeightKilograms("82,4", unit: .metric), 82.4)
        XCTAssertEqual(DailyReminderEngine.parsedWeightKilograms("82.4 kg", unit: .metric), 82.4)
        let pounds = DailyReminderEngine.parsedWeightKilograms("181 lb", unit: .imperial)
        XCTAssertEqual(pounds ?? 0, 82.1, accuracy: 0.1)
    }

    func test_parsedWeight_dictatedTrailingPeriod_isRead() {
        XCTAssertEqual(DailyReminderEngine.parsedWeightKilograms("82.4.", unit: .metric), 82.4)
    }

    func test_parsedWeight_typedUnit_winsOverDisplayUnit() {
        let pounds = DailyReminderEngine.parsedWeightKilograms("181 lb", unit: .metric)
        XCTAssertEqual(pounds ?? 0, 82.1, accuracy: 0.1)
        XCTAssertEqual(DailyReminderEngine.parsedWeightKilograms("82 kg", unit: .imperial), 82)
        XCTAssertEqual(DailyReminderEngine.parsedWeightKilograms("180 Pounds", unit: .metric) ?? 0, 81.6, accuracy: 0.1)
    }

    func test_parsedWeight_noUnit_usesDisplayUnit() {
        XCTAssertEqual(DailyReminderEngine.parsedWeightKilograms("181", unit: .imperial) ?? 0, 82.1, accuracy: 0.1)
        XCTAssertEqual(DailyReminderEngine.parsedWeightKilograms("82", unit: .metric), 82)
    }

    func test_parsedWeight_rejectsImplausibleValues() {
        XCTAssertNil(DailyReminderEngine.parsedWeightKilograms("8.24", unit: .metric))
        XCTAssertNil(DailyReminderEngine.parsedWeightKilograms("", unit: .metric))
        XCTAssertNil(DailyReminderEngine.parsedWeightKilograms("abc", unit: .metric))
    }

    func test_settings_roundTripThroughDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DailyReminderEngineTests"))
        defaults.removePersistentDomain(forName: "DailyReminderEngineTests")
        var s = settings(.dinner)
        s.slots[.dinner]?.hour = 20
        s.save(defaults: defaults)
        XCTAssertEqual(DailyReminderSettings.load(training: nil, defaults: defaults), s)
    }
}
