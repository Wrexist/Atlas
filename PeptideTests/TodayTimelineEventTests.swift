import XCTest
@testable import Peptide

/// `TodayTimelineEvent.build(...)` is pure value-in / value-out so
/// we can lock down sorting and row content without standing up a
/// DataStore.
final class TodayTimelineEventTests: XCTestCase {

    // MARK: - Empty

    func test_build_emptyInputs_returnsEmpty() {
        let events = TodayTimelineEvent.build(
            meals: [],
            checkIn: nil,
            workouts: []
        )
        XCTAssertEqual(events, [])
    }

    // MARK: - Sorting

    func test_build_sortsChronologically() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar.current
        let morning = cal.date(byAdding: .hour, value: 7,  to: now)!
        let noon    = cal.date(byAdding: .hour, value: 12, to: now)!
        let evening = cal.date(byAdding: .hour, value: 18, to: now)!

        // Deliberately insert in reverse-chronological order to
        // verify the sort actually runs and isn't trivially passing
        // because the input was already in order.
        let events = TodayTimelineEvent.build(
            meals: [
                makeMeal(date: evening, name: "Dinner"),
                makeMeal(date: noon,    name: "Lunch"),
                makeMeal(date: morning, name: "Breakfast"),
            ],
            checkIn: nil,
            workouts: []
        )

        XCTAssertEqual(events.map(\.title), ["Breakfast", "Lunch", "Dinner"])
    }

    // MARK: - Check-in subtitle

    func test_build_checkIn_subtitleShowsAverage() {
        let entry = OutcomeEntry(
            id: UUID(),
            date: Date(),
            energy: 4, sleepQuality: 3, recovery: 5, mood: 4, focus: 3
        )
        // average = 3.8
        let events = TodayTimelineEvent.build(
            meals: [], checkIn: entry, workouts: []
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].subtitle?.contains("3.8") ?? false)
    }

    // MARK: - Helpers

    private func makeMeal(date: Date, name: String) -> MealEntry {
        MealEntry(
            id: UUID(),
            date: date,
            category: MealCategory.auto(for: date),
            name: name,
            calories: 400,
            proteinG: 25,
            carbsG: 45,
            fatG: 12,
            sourceID: nil,
            source: .photo
        )
    }
}
