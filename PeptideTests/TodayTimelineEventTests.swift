import XCTest
@testable import Peptide

/// `TodayTimelineEvent.build(...)` is pure value-in / value-out so
/// we can lock down the sorting + completed/pending inference
/// without standing up a DataStore.
final class TodayTimelineEventTests: XCTestCase {

    // MARK: - Empty

    func test_build_emptyInputs_returnsEmpty() {
        let events = TodayTimelineEvent.build(
            doses: [],
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
            doses: [],
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

    // MARK: - Dose completion / pending inference

    /// A scheduled dose whose time has passed but isn't logged →
    /// pending. The yellow badge in the timeline is the cue to
    /// catch up.
    func test_build_pastUnloggedDose_markedPending() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduled = now.addingTimeInterval(-3600)   // 1 hour ago
        let dose = makeDose(scheduledFor: scheduled, completed: false)

        let events = TodayTimelineEvent.build(
            doses: [dose],
            meals: [],
            checkIn: nil,
            workouts: [],
            now: now
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].isPending)
        XCTAssertFalse(events[0].isCompleted)
    }

    /// A future dose isn't pending yet — it's just upcoming. The
    /// pending badge would be misleading.
    func test_build_futureDose_notPending() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let later = now.addingTimeInterval(3600)        // 1 hour from now
        let dose = makeDose(scheduledFor: later, completed: false)

        let events = TodayTimelineEvent.build(
            doses: [dose],
            meals: [],
            checkIn: nil,
            workouts: [],
            now: now
        )
        XCTAssertFalse(events[0].isPending)
        XCTAssertFalse(events[0].isCompleted)
    }

    /// A logged dose → completed. Uses `actualTime` if present so
    /// the timeline reflects when the user actually took it.
    func test_build_loggedDose_usesActualTime() {
        let scheduled = Date(timeIntervalSince1970: 1_700_000_000)
        let actual    = scheduled.addingTimeInterval(900)   // 15 min late
        let dose = makeDose(scheduledFor: scheduled, completed: true, actualTime: actual)

        let events = TodayTimelineEvent.build(
            doses: [dose],
            meals: [],
            checkIn: nil,
            workouts: []
        )
        XCTAssertEqual(events[0].date, actual)
        XCTAssertTrue(events[0].isCompleted)
        XCTAssertFalse(events[0].isPending)
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
            doses: [], meals: [], checkIn: entry, workouts: []
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].subtitle?.contains("3.8") ?? false)
    }

    // MARK: - Helpers

    private func makeDose(
        scheduledFor date: Date,
        completed: Bool,
        actualTime: Date? = nil
    ) -> ProtocolEntry {
        // Memberwise initializer — field order matches the Peptide
        // and ProtocolEntry struct definitions. If those models
        // gain fields, this helper updates in one place.
        let peptide = Peptide(
            name: "BPC-157",
            abbreviation: "BPC-157",
            category: .growth,
            description: "",
            benefits: [],
            dosageRange: "",
            frequency: "",
            halfLife: "",
            adminRoute: "",
            researchLinks: [],
            imageSystemName: "syringe.fill"
        )
        return ProtocolEntry(
            id: UUID(),
            protocolId: UUID(),
            peptide: peptide,
            date: date,
            dose: "5 mg",
            notes: "",
            completed: completed,
            actualDose: nil,
            actualTime: actualTime,
            injectionSite: nil
        )
    }

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
