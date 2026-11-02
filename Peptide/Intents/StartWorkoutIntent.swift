import AppIntents
import Foundation

/// "Start a workout in Atlas" — opens Train with a session running, the
/// same hand-off as the Start workout quick action and Control Center
/// control. With a routine picked, the session is seeded from it first;
/// a workout already in progress is resumed rather than replaced.
struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start workout"

    static let description = IntentDescription(
        "Opens Atlas and starts a workout from a routine, or an empty workout when none is picked.",
        categoryName: "Training"
    )

    static let openAppWhenRun: Bool = true

    @Parameter(
        title: "Routine",
        description: "The routine to train. Leave empty for an empty workout."
    )
    var routine: RoutineEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        if let routineID = routine?.id {
            Self.startRoutine(id: routineID)
        }
        // Switches to Train and starts an empty workout if none is running.
        QuickActionInbox.shared.pending = .startWorkout
        return .result()
    }

    @MainActor
    private static func startRoutine(id: String) {
        guard WorkoutSessionService.shared.activeSession == nil,
              let routine = RoutineEntityQuery.loadRoutines().first(where: { $0.id.uuidString == id })
        else { return }
        RoutineStore.shared.startWorkout(from: routine)
    }
}
