import XCTest
@testable import Peptide

@MainActor
final class WorkoutTypeOverrideStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var store: WorkoutTypeOverrideStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "WorkoutTypeOverrideStoreTests")
        defaults.removePersistentDomain(forName: "WorkoutTypeOverrideStoreTests")
        store = WorkoutTypeOverrideStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "WorkoutTypeOverrideStoreTests")
        super.tearDown()
    }

    private func healthWorkout(_ activity: CardioActivity) -> ImportedCardioWorkout {
        ImportedCardioWorkout(
            id: UUID(),
            activity: activity,
            start: Date(timeIntervalSince1970: 1_800_000_000),
            duration: 3_600,
            distanceMeters: nil,
            activeKilocalories: 320,
            averageHeartRate: 98,
            sourceName: "Apple Watch"
        )
    }

    func test_pickedType_replacesHealthsTypeAndKeepsEverythingElse() {
        let dive = healthWorkout(.other)
        store.set(.diving, for: dive.id)

        let shown = store.applied(to: [dive])

        XCTAssertEqual(shown.first?.activity, .diving)
        XCTAssertEqual(shown.first?.id, dive.id)
        XCTAssertEqual(shown.first?.duration, dive.duration)
        XCTAssertEqual(shown.first?.activeKilocalories, dive.activeKilocalories)
    }

    func test_workoutWithoutPick_keepsHealthsType() {
        let run = healthWorkout(.running)
        store.set(.diving, for: UUID())

        XCTAssertEqual(store.applied(to: [run]).first?.activity, .running)
    }

    func test_clearingPick_returnsToHealthsType() {
        let dive = healthWorkout(.other)
        store.set(.diving, for: dive.id)
        store.set(nil, for: dive.id)

        XCTAssertNil(store.activity(for: dive.id))
        XCTAssertEqual(store.applied(to: [dive]).first?.activity, .other)
    }

    func test_pick_survivesANewStoreOnTheSameDefaults() {
        let dive = healthWorkout(.other)
        store.set(.diving, for: dive.id)

        XCTAssertEqual(WorkoutTypeOverrideStore(defaults: defaults).activity(for: dive.id), .diving)
    }
}
