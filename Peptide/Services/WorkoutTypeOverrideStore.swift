import Foundation

/// The type the user picked for an Apple Health workout whose own type was
/// wrong or too vague ("Workout"). Atlas can't change another app's Health
/// samples, so the choice lives here, keyed by the sample's uuid, and is
/// laid over every fetch.
@MainActor
final class WorkoutTypeOverrideStore {
    static let shared: WorkoutTypeOverrideStore = {
        let store = WorkoutTypeOverrideStore()
        #if DEBUG
        // Screenshot runs start from Health's own types every launch.
        if HealthWorkoutsFixture.isRequested { store.defaults.removeObject(forKey: store.key) }
        #endif
        return store
    }()

    private let defaults: UserDefaults
    private let key = "workoutTypeOverrides.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func activity(for workoutID: UUID) -> CardioActivity? {
        stored[workoutID.uuidString].flatMap(CardioActivity.init(rawValue:))
    }

    /// Nil goes back to the type Health recorded. Callers pass nil, not
    /// Health's own type, so a stored pick always differs from Health's.
    func set(_ activity: CardioActivity?, for workoutID: UUID) {
        var overrides = stored
        overrides[workoutID.uuidString] = activity?.rawValue
        defaults.set(overrides, forKey: key)
    }

    func deleteAll() {
        defaults.removeObject(forKey: key)
    }

    func applied(to workouts: [ImportedCardioWorkout]) -> [ImportedCardioWorkout] {
        workouts.map { workout in
            activity(for: workout.id).map(workout.categorized(as:)) ?? workout
        }
    }

    private var stored: [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}
