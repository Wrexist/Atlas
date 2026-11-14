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
        let rows: [(CardioActivity, Double, Double, Double?, Double)] = [
            (.diving, 1, 67, nil, 410),
            (.other, 2, 94, nil, 520),
            (.diving, 3, 102, nil, 560),
            (.running, 5, 31, 5_420, 380),
        ]
        return rows.map { activity, daysAgo, minutes, meters, kcal in
            ImportedCardioWorkout(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(Int(daysAgo))") ?? UUID(),
                activity: activity,
                start: now.addingTimeInterval(-daysAgo * 86_400),
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
