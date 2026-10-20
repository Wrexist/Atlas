import Foundation

/// Double progression: hold a weight until every working set reaches the
/// top of its rep range, then add the smallest practical load and drop
/// back to the bottom of the range. Pure, so the rule is testable without
/// a store; `WorkoutSessionService` feeds it the last session's sets.
enum ProgressionEngine {

    struct Suggestion: Equatable, Sendable {
        enum Reason: Equatable, Sendable {
            /// Every top set reached the range's ceiling at a manageable effort.
            case addWeight
            /// Short of the ceiling: same load, one more rep.
            case addRep
            /// Short of a fixed target, or the last sets were near failure.
            case repeatLoad
        }

        let weightKg: Double
        let reps: Int
        let reason: Reason
    }

    /// At or above this RPE the last session was a grind, so the load holds.
    static let grindRPE = 9.5

    /// A routine's fixed target, otherwise the usual hypertrophy ranges:
    /// compounds progress from fewer reps than isolation work.
    static func repRange(targetReps: Int?, mechanic: Exercise.Mechanic?) -> ClosedRange<Int> {
        if let targetReps, targetReps > 0 { return targetReps...targetReps }
        return mechanic == .compound ? 6...10 : 8...12
    }

    /// The smallest jump the equipment usually allows, in kilograms. Zero
    /// for bodyweight (progress by reps); nil where load isn't comparable
    /// session to session (bands, unknown kit).
    static func incrementKg(for equipment: EquipmentKind, unit: MeasurementUnit) -> Double? {
        switch equipment {
        case .barbell, .smith, .machine, .cable:
            return unit == .metric ? 2.5 : unit.kilograms(fromDisplayed: 5)
        case .dumbbell, .kettlebell:
            return unit == .metric ? 2 : unit.kilograms(fromDisplayed: 5)
        case .bodyweight:
            return 0
        case .band, .other:
            return nil
        }
    }

    static func suggestion(
        previous: [SetEntry],
        repRange: ClosedRange<Int>,
        incrementKg: Double?
    ) -> Suggestion? {
        guard let incrementKg else { return nil }
        let working = previous.filter {
            $0.completed && !$0.isWarmup && $0.reps > 0 && $0.supportsRepLogging
        }
        guard let topWeight = working.map(\.weightKg).max() else { return nil }
        let topSets = working.filter { abs($0.weightKg - topWeight) < 0.01 }
        let fewestReps = topSets.map(\.reps).min() ?? 0
        let hardestRPE = topSets.compactMap(\.rpe).max() ?? 0

        if topWeight <= 0 || incrementKg <= 0 {
            return Suggestion(weightKg: topWeight, reps: SetEntryLimits.clampReps(fewestReps + 1), reason: .addRep)
        }
        if fewestReps >= repRange.upperBound && hardestRPE < grindRPE {
            return Suggestion(
                weightKg: SetEntryLimits.clampWeightKg(topWeight + incrementKg),
                reps: repRange.lowerBound,
                reason: .addWeight
            )
        }
        if repRange.lowerBound == repRange.upperBound || hardestRPE >= grindRPE {
            let reps = min(max(fewestReps, repRange.lowerBound), repRange.upperBound)
            return Suggestion(weightKg: topWeight, reps: reps, reason: .repeatLoad)
        }
        let reps = min(max(fewestReps + 1, repRange.lowerBound), repRange.upperBound)
        return Suggestion(weightKg: topWeight, reps: reps, reason: .addRep)
    }

    /// Writes the suggestion into every working set the user hasn't
    /// checked off yet. Logged sets and warm-ups are never touched.
    static func apply(_ suggestion: Suggestion, to sets: [SetEntry]) -> [SetEntry] {
        sets.map { set in
            guard !set.completed, !set.isWarmup, set.supportsRepLogging else { return set }
            var updated = set
            updated.weightKg = suggestion.weightKg
            updated.reps = suggestion.reps
            return updated
        }
    }

    /// True when some pending working set still differs from the suggestion,
    /// which is when offering "Use" makes sense.
    static func isPending(_ suggestion: Suggestion, in sets: [SetEntry]) -> Bool {
        apply(suggestion, to: sets) != sets
    }
}
