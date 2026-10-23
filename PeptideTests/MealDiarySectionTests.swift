import XCTest
@testable import Peptide

/// Pins how the Meals diary groups a day's entries.
@MainActor
final class MealDiarySectionTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func entry(_ name: String, _ category: MealCategory, hour: Int, calories: Int = 100) -> MealEntry {
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 14))!
        let date = calendar.date(byAdding: .hour, value: hour, to: day)!
        return MealEntry(date: date, category: category, name: name, calories: calories,
                         proteinG: 0, carbsG: 0, fatG: 0, source: .manual)
    }

    func test_mixedEntries_groupInMealOrderOldestFirst() {
        let entries = [
            entry("Apple", .snack, hour: 16),
            entry("Pasta", .dinner, hour: 19),
            entry("Coffee", .breakfast, hour: 9),
            entry("Oats", .breakfast, hour: 7),
        ]

        let sections = MealDiarySection.sections(of: entries)

        XCTAssertEqual(sections.map(\.category), [.breakfast, .dinner, .snack])
        XCTAssertEqual(sections.first?.entries.map(\.name), ["Oats", "Coffee"])
    }

    func test_sectionCalories_sumOnlyThatMeal() {
        let entries = [
            entry("Oats", .breakfast, hour: 7, calories: 350),
            entry("Coffee", .breakfast, hour: 9, calories: 40),
            entry("Pasta", .dinner, hour: 19, calories: 700),
        ]

        let sections = MealDiarySection.sections(of: entries)

        XCTAssertEqual(sections.map(\.calories), [390, 700])
    }

    func test_noEntries_yieldsNoSections() {
        XCTAssertTrue(MealDiarySection.sections(of: []).isEmpty)
    }
}
