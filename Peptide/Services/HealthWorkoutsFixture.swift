#if DEBUG
import Foundation

/// Screenshot runs only. A simulator has no Apple Watch, so this hands the
/// training history the Health workouts a diver's week produces: two dives
/// Health typed properly, one it left as a plain "Workout", and a run.
enum HealthWorkoutsFixture {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--health-workouts-fixture")
            && UserDefaults.standard.bool(forKey: "com.peptidesai.app.screenshotMode.enabled")
    }

    static func workouts(now: Date = Date()) -> [ImportedCardioWorkout] {
        let rows: [(UUID, CardioActivity, Double, Double, Double?, Double)] = [
            (UUID(uuidString: "6F1C1D2A-0001-4A61-9C1B-2D5E0A7B1001")!, .diving, 1, 67, nil, 410),
            (UUID(uuidString: "6F1C1D2A-0002-4A61-9C1B-2D5E0A7B1002")!, .other, 2, 94, nil, 520),
            (UUID(uuidString: "6F1C1D2A-0003-4A61-9C1B-2D5E0A7B1003")!, .diving, 3, 102, nil, 560),
            (UUID(uuidString: "6F1C1D2A-0004-4A61-9C1B-2D5E0A7B1004")!, .running, 5, 31, 5_420, 380),
        ]
        return rows.map { id, activity, daysAgo, minutes, meters, kcal in
            let start = now.addingTimeInterval(-daysAgo * 86_400)
            return ImportedCardioWorkout(
                id: id,
                activity: activity,
                start: start,
                end: start.addingTimeInterval(minutes * 60),
                duration: minutes * 60,
                distanceMeters: meters,
                activeKilocalories: kcal,
                averageHeartRate: 96,
                sourceName: "Apple Watch"
            )
        }
    }
}
#endif
