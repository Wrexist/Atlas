#if DEBUG
import Foundation

/// Isolated tests only. Never installed into the user's on-disk repository.
enum WorkoutRecapFixture {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--completion-fixture")
            && UserDefaults.standard.bool(forKey: "com.peptidesai.app.screenshotMode.enabled")
    }
    static func push(finishedAt end: Date = Date()) -> WorkoutSession {
        let rows: [(String, Int, Double, SetEntry.Measurement.Load)] = [
            ("Barbell_Bench_Press_-_Medium_Grip", 8, 95, .total),
            ("Incline_Dumbbell_Press", 10, 25, .eachPair),
            ("Dumbbell_Shoulder_Press", 8, 20, .eachPair),
            ("Side_Lateral_Raise", 12, 10, .eachPair),
            ("Triceps_Pushdown", 12, 35, .total)
        ]
        var entries = rows.enumerated().map { index, row in
            WorkoutExerciseEntry(exerciseID: row.0, index: index, sets: (1...3).map { number in
                SetEntry(index: number, weightKg: MeasurementUnit.imperial.kilograms(fromDisplayed: row.2),
                         reps: row.1, completed: true, completedAt: end,
                         measurement: .init(kind: .repetitions, load: row.3))
            })
        }
        entries[0].sets += [
            SetEntry(index: 4, weightKg: 20, reps: 10, completed: true, isWarmup: true),
            SetEntry(index: 5, weightKg: 100, reps: 8)
        ]
        return WorkoutSession(name: "Push Workout", startedAt: end.addingTimeInterval(-42 * 60),
                              finishedAt: end, exercises: entries, focus: WorkoutFocusState(timing: .tracked))
    }
}
#endif
