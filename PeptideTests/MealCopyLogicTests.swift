import XCTest
@testable import Peptide

/// Copying a meal or a whole day in the Meals diary
/// (`LifestyleDataLogic.copiedMeals`).
final class MealCopyLogicTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func entry(_ name: String, at date: Date, category: MealCategory) -> MealEntry {
        MealEntry(
            date: date,
            category: category,
            name: name,
            calories: 300,
            proteinG: 20,
            carbsG: 30,
            fatG: 10,
            source: .manual
        )
    }

    /// A "now" after every target day, so no copy is clamped.
    private var later: Date { date(30, 12, month: 11) }

    private var history: [MealEntry] {
        [
            entry("Oats", at: date(27, 7, 30), category: .breakfast),
            entry("Coffee", at: date(27, 7, 45), category: .breakfast),
            entry("Salad", at: date(27, 12, 15), category: .lunch),
            entry("Pasta", at: date(26, 19), category: .dinner),
        ]
    }

    func test_copiedMeals_oneCategory_copiesOnlyThatMealAtSameClockTime() {
        let copies = LifestyleDataLogic.copiedMeals(
            from: date(27, 0), to: date(28, 9), category: .breakfast, in: history, now: later, calendar: calendar
        )

        XCTAssertEqual(copies.map(\.name), ["Oats", "Coffee"])
        XCTAssertEqual(copies.map(\.date), [date(28, 7, 30), date(28, 7, 45)])
        XCTAssertTrue(copies.allSatisfy { $0.category == .breakfast })
    }

    func test_copiedMeals_wholeDay_copiesEveryMealOldestFirst() {
        let copies = LifestyleDataLogic.copiedMeals(
            from: date(27, 0), to: date(28, 0), in: history, now: later, calendar: calendar
        )

        XCTAssertEqual(copies.map(\.name), ["Oats", "Coffee", "Salad"])
        XCTAssertEqual(copies.last?.date, date(28, 12, 15))
    }

    func test_copiedMeals_acrossMonthBoundary_shiftsDateKeepsTime() {
        let copies = LifestyleDataLogic.copiedMeals(
            from: date(26, 0), to: date(1, 0, month: 11), category: .dinner, in: history, now: later, calendar: calendar
        )

        XCTAssertEqual(copies.map(\.date), [date(1, 19, month: 11)])
    }

    func test_copiedMeals_givesNewIDsAndKeepsMacros() {
        let source = history
        let copies = LifestyleDataLogic.copiedMeals(
            from: date(27, 0), to: date(28, 0), in: source, now: later, calendar: calendar
        )

        XCTAssertTrue(Set(copies.map(\.id)).isDisjoint(with: source.map(\.id)))
        XCTAssertEqual(Set(copies.map(\.id)).count, copies.count)
        XCTAssertTrue(copies.allSatisfy { $0.calories == 300 && $0.proteinG == 20 && $0.source == .manual })
    }

    func test_copiedMeals_emptySourceDay_returnsNothing() {
        let wholeDay = LifestyleDataLogic.copiedMeals(
            from: date(20, 0), to: date(28, 0), in: history, now: later, calendar: calendar
        )
        let missingMeal = LifestyleDataLogic.copiedMeals(
            from: date(27, 0), to: date(28, 0), category: .snack, in: history, now: later, calendar: calendar
        )

        XCTAssertTrue(wholeDay.isEmpty)
        XCTAssertTrue(missingMeal.isEmpty)
    }

    /// Documented behaviour: a copy is not idempotent. Copying the same
    /// meal twice yields a second, distinct set of entries; the meal
    /// reminder's `repeatMeals` guards against that by checking the
    /// target day first.
    func test_copiedMeals_runTwice_copiesAgainWithDistinctIDs() {
        var updated = history
        let first = LifestyleDataLogic.copiedMeals(
            from: date(27, 0), to: date(28, 0), category: .lunch, in: updated, now: later, calendar: calendar
        )
        updated += first
        let second = LifestyleDataLogic.copiedMeals(
            from: date(27, 0), to: date(28, 0), category: .lunch, in: updated, now: later, calendar: calendar
        )

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        XCTAssertNotEqual(first.first?.id, second.first?.id)
    }

    func test_copiedMeals_ontoToday_neverLandsAfterNow() {
        let now = date(28, 9)
        let copies = LifestyleDataLogic.copiedMeals(
            from: date(27, 0), to: date(28, 0), in: history, now: now, calendar: calendar
        )

        XCTAssertEqual(copies.map(\.date), [date(28, 7, 30), date(28, 7, 45), now])
    }
}
