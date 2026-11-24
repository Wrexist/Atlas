import Foundation

/// The type the user picked for an Apple Health workout whose own type was
/// wrong or too vague ("Workout"). Atlas can't change another app's Health
/// samples, so the choice lives in `UserProfile.workoutTypeOverrides` —
/// synced and backed up with the profile — keyed by the sample's uuid, and
/// is laid over every fetch.
enum WorkoutTypeOverrideStore {
    static func activity(for workoutID: UUID, in overrides: [String: String]) -> CardioActivity? {
        overrides[workoutID.uuidString].flatMap(CardioActivity.init(rawValue:))
    }

    /// Nil goes back to the type Health recorded. Callers pass nil, not
    /// Health's own type, so a stored pick always differs from Health's.
    static func setting(
        _ activity: CardioActivity?, for workoutID: UUID, in overrides: [String: String]
    ) -> [String: String] {
        var updated = overrides
        updated[workoutID.uuidString] = activity?.rawValue
        return updated
    }

    static func applied(_ overrides: [String: String], to workouts: [ImportedCardioWorkout]) -> [ImportedCardioWorkout] {
        workouts.map { workout in
            activity(for: workout.id, in: overrides).map(workout.categorized(as:)) ?? workout
        }
    }

    // MARK: - Device-local picks from older builds

    private static let legacyKey = "workoutTypeOverrides.v1"

    /// Picks an older build kept in this device's defaults. Nil when there
    /// are none. Left in place until `deleteLegacy`.
    static func legacy(from defaults: UserDefaults = .standard) -> [String: String]? {
        guard let legacy = defaults.dictionary(forKey: legacyKey) as? [String: String], !legacy.isEmpty else { return nil }
        return legacy
    }

    static func deleteLegacy(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: legacyKey)
    }
}
