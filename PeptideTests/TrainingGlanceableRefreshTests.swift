import XCTest
@testable import Peptide

/// Pins that a training-lifecycle event actually rewrites the glanceable
/// payload.
///
/// Start / finish / discard write `StoredWorkoutSession` through the repo,
/// not through `protocols` / `entries` / `profile`, so none of DataStore's
/// `didSet` bumps fire on them. Nothing else calls `updateWidgetData` on
/// those paths — which meant the training widget could show a running
/// timer for a discarded workout, or yesterday's session in the moment
/// right after the user finished today's. These tests fail if that wiring
/// is ever unhooked.
@MainActor
final class TrainingGlanceableRefreshTests: XCTestCase {

    private var store: DataStore!

    override func setUp() {
        super.setUp()
        SwiftDataRepository.shared.configureForTesting()
        // `DataStore.init` assigns `Self.current`, which is what
        // `WorkoutSessionService` reaches through.
        store = DataStore(seedSampleData: true)
    }

    override func tearDown() {
        // A leaked active session would seed the next test's store with a
        // workout already in progress.
        WorkoutSessionService.shared.discardWorkout()
        SwiftDataRepository.shared.deleteAll()
        store = nil
        super.tearDown()
    }

    func test_startingAWorkout_refreshesTheWidgetPayload() {
        let baseline = store.widgetUpdateCountForTesting

        WorkoutSessionService.shared.startWorkout()

        XCTAssertGreaterThan(store.widgetUpdateCountForTesting, baseline)
    }

    func test_finishingAWorkout_refreshesTheWidgetPayload() {
        WorkoutSessionService.shared.startWorkout()
        let baseline = store.widgetUpdateCountForTesting

        WorkoutSessionService.shared.finishWorkout()

        XCTAssertGreaterThan(store.widgetUpdateCountForTesting, baseline)
    }

    func test_discardingAWorkout_refreshesTheWidgetPayload() {
        WorkoutSessionService.shared.startWorkout()
        let baseline = store.widgetUpdateCountForTesting

        WorkoutSessionService.shared.discardWorkout()

        XCTAssertGreaterThan(store.widgetUpdateCountForTesting, baseline)
    }

    func test_finishedWorkout_landsInTheNextSnapshotAsHistory() {
        // The end-to-end shape of the fix: after a finish, the payload
        // describes a completed workout and no workout in progress.
        WorkoutSessionService.shared.startWorkout()
        WorkoutSessionService.shared.finishWorkout()

        let snapshot = WidgetSnapshotBuilder.build(
            today: store.todayEntries,
            next: nil,
            workouts: SwiftDataRepository.shared.loadWorkoutSessions(limit: 30),
            activeWorkout: WorkoutSessionService.shared.activeSession
        )

        XCTAssertNil(snapshot.activeWorkoutStartedAt)
        XCTAssertFalse(snapshot.workoutInProgress)
        XCTAssertNotNil(snapshot.lastWorkout)
    }
}
