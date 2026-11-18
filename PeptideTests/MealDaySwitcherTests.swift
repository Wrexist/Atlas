import XCTest
@testable import Peptide

/// Pins the meal day-switcher's week maths, which depends on the
/// calendar's first weekday, and its day titles.
@MainActor
final class MealDaySwitcherTests: XCTestCase {

    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func weekday(ofOffset offset: Int, in calendar: Calendar) -> Int {
        let today = calendar.startOfDay(for: Date())
        let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
        return calendar.component(.weekday, from: day)
    }

    func test_weekOffsets_sundayFirstCalendar_startsOnSunday() {
        let sundayFirst = calendar(firstWeekday: 1)
        let week = WeekDayStrip.weekOffsets(containing: 0, calendar: sundayFirst)
        XCTAssertEqual(weekday(ofOffset: week.lowerBound, in: sundayFirst), 1)
    }

    func test_weekOffsets_mondayFirstCalendar_startsOnMonday() {
        let mondayFirst = calendar(firstWeekday: 2)
        let week = WeekDayStrip.weekOffsets(containing: 0, calendar: mondayFirst)
        XCTAssertEqual(weekday(ofOffset: week.lowerBound, in: mondayFirst), 2)
    }

    func test_weekOffsets_alwaysSevenDaysContainingOffset() {
        for firstWeekday in [1, 2] {
            let weekCalendar = calendar(firstWeekday: firstWeekday)
            for offset in -400...0 {
                let week = WeekDayStrip.weekOffsets(containing: offset, calendar: weekCalendar)
                XCTAssertEqual(week.count, 7)
                XCTAssertTrue(week.contains(offset), "offset \(offset), first weekday \(firstWeekday)")
                XCTAssertEqual(weekday(ofOffset: week.lowerBound, in: weekCalendar), firstWeekday)
            }
        }
    }

    func test_inlineTitle_yesterday_isLowercase() {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        XCTAssertEqual(MealDaySwitcher.title(for: yesterday, calendar: calendar), String(localized: "Yesterday"))
        XCTAssertEqual(MealDaySwitcher.inlineTitle(for: yesterday, calendar: calendar), String(localized: "yesterday"))
    }

    func test_inlineTitle_olderDay_matchesTitle() {
        let calendar = Calendar.current
        let older = calendar.date(byAdding: .day, value: -5, to: calendar.startOfDay(for: Date()))!
        XCTAssertEqual(MealDaySwitcher.inlineTitle(for: older, calendar: calendar),
                       MealDaySwitcher.title(for: older, calendar: calendar))
    }

    func test_loggedOffsets_marksEntryDaysAndLegacyTotalsInWeekOnly() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let today = try XCTUnwrap(utc.date(from: DateComponents(year: 2026, month: 3, day: 12, hour: 15)))
        let todayStart = utc.startOfDay(for: today)
        func noon(_ offset: Int) throws -> Date {
            try XCTUnwrap(utc.date(byAdding: .hour, value: offset * 24 + 12, to: todayStart))
        }
        var profile = UserProfile.fresh
        for offset in [-2, -10] {
            let date = try noon(offset)
            profile.mealHistory.append(MealEntry(date: date, category: .lunch, name: "Meal",
                                                 calories: 500, proteinG: 30, carbsG: 50, fatG: 20, source: .manual))
        }
        let legacyDay = try noon(-4)
        profile.dailyConsumption[LifestyleDataLogic.consumptionKey(for: legacyDay, calendar: utc)] = DailyConsumption(
            date: utc.startOfDay(for: legacyDay), caloriesKcal: 300, proteinG: 0, carbsG: 0, fatG: 0, waterOz: 0)

        let logged = WeekDayStrip.loggedOffsets(in: -6..<1, profile: profile, today: today, calendar: utc)
        XCTAssertEqual(logged, [-2, -4])
    }
}
