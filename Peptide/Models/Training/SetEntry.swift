import Foundation

/// One logged set within an exercise within a workout session. Stored
/// inline on `WorkoutExerciseEntry.sets` rather than as its own
/// SwiftData row because (a) reads always pull the whole session and
/// (b) a typical session has 20-40 sets — fine to encode as a JSON
/// blob on the parent.
///
/// Weight is canonicalized to **kilograms** so the persisted history
/// survives a metric/imperial unit toggle. The UI converts on read /
/// write using `MeasurementUnit` from the user's profile.
/// Sanity bounds for manually entered set values. Lower bounds are hard
/// floors — negative weight or reps are never legitimate and would
/// silently subtract from session volume. Upper bounds sit far beyond
/// elite performance (world-record squat ≈ 505 kg) so no real lift is
/// ever rejected; they exist to stop a fat-fingered or pasted "9999"
/// from becoming a permanent personal record. Weight 0 stays valid —
/// it is the bodyweight track (audit Train H3).
enum SetEntryLimits {
    static let weightKg: ClosedRange<Double> = 0...1000
    static let reps: ClosedRange<Int> = 0...500

    static func clampWeightKg(_ value: Double) -> Double {
        guard value.isFinite else { return weightKg.lowerBound }
        return min(max(value, weightKg.lowerBound), weightKg.upperBound)
    }

    static func clampReps(_ value: Int) -> Int {
        min(max(value, reps.lowerBound), reps.upperBound)
    }
}

struct SetEntry: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    /// Position within the parent exercise's set list — 1-indexed for
    /// display. Sets are sorted by `index` on read; mutating the index
    /// is how the user reorders.
    var index: Int
    var weightKg: Double
    var reps: Int
    /// Rate of Perceived Exertion, 1.0–10.0 in half-point increments.
    /// Optional because the user only fills it in when they want to.
    var rpe: Double?
    /// Free-form per-set note (e.g. "form felt off", "knee twinge").
    /// Capped at ~200 chars in the UI.
    var note: String?
    /// True when the user has checked the set off in the active workout
    /// screen. Incomplete sets aren't counted toward volume / PRs.
    var completed: Bool
    /// True for ramp-up sets that shouldn't count toward working volume
    /// or trigger PR detection. Drives the "W" badge on the set row.
    var isWarmup: Bool
    /// Wall-clock timestamp the set was checked off. Nil until completed.
    /// Used to compute realized rest intervals for future analytics.
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        index: Int,
        weightKg: Double,
        reps: Int,
        rpe: Double? = nil,
        note: String? = nil,
        completed: Bool = false,
        isWarmup: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.index = index
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.note = note
        self.completed = completed
        self.isWarmup = isWarmup
        self.completedAt = completedAt
    }

    /// Volume contribution of this set: `weight * reps`, in kg. Zero
    /// for incomplete or warm-up sets so the volume aggregate sums to
    /// the user's working volume only.
    var volumeKg: Double {
        guard completed, !isWarmup else { return 0 }
        return weightKg * Double(reps)
    }

    /// Epley 1RM estimate for the working load. Returns `nil` for
    /// warm-up sets, incomplete sets, or 0 reps so callers don't have
    /// to special-case those branches.
    var estimatedOneRepMaxKg: Double? {
        guard completed, !isWarmup, reps > 0, weightKg > 0 else { return nil }
        if reps == 1 { return weightKg }
        return weightKg * (1.0 + Double(reps) / 30.0)
    }
}
