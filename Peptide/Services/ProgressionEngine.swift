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
            /// Below the range's floor: same load, build up to the floor.
            case reachRange
            /// Short of a fixed target, or the last sets were near failure.
            case repeatLoad
        }

        let weightKg: Double
        let reps: Int
        let reason: Reason
        /// Set when today's readiness or a deload week lowered the target.
        var adjustment: Adjustment?
    }

    /// Why today's target sits below the plain progression.
    enum Adjustment: Equatable, Sendable {
        /// Low recovery: about 10% less load, same reps.
        case lowRecovery
        /// Deload week: the same lighter load and a third fewer reps,
        /// about 60% of the usual volume without dropping sets.
        case deload
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
    /// session to session (bands, balls, rollers, loose plates, unknown
    /// kit). A plate-loaded bar moves by one of the user's lightest
    /// plates a side when `plates` (in `unit`) is given.
    static func incrementKg(for equipment: EquipmentKind, unit: MeasurementUnit, plates: [Double]? = nil) -> Double? {
        if equipment.bar != nil, let plates, let jump = PlateCalculatorEngine.smallestJump(plates: plates) {
            return unit.kilograms(fromDisplayed: jump)
        }
        switch equipment {
        case .barbell, .smith, .ezBar, .trapBar, .machine, .cable:
            return unit == .metric ? 2.5 : unit.kilograms(fromDisplayed: 5)
        case .dumbbell, .kettlebell:
            return unit == .metric ? 2 : unit.kilograms(fromDisplayed: 5)
        case .bodyweight:
            return 0
        case .band, .plate, .medicineBall, .swissBall, .foamRoller, .other:
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
        return Suggestion(weightKg: topWeight, reps: reps, reason: reps == fewestReps + 1 ? .addRep : .reachRange)
    }

    static let reducedLoadFactor = 0.9
    static let deloadRepFactor = 2.0 / 3.0

    /// Lowers a suggestion for `adjustment`, landing the load on a step the
    /// equipment can make. Bodyweight work keeps its load.
    static func adjusted(_ suggestion: Suggestion, for adjustment: Adjustment, incrementKg: Double) -> Suggestion {
        let reps = adjustment == .deload
            ? max(1, Int((Double(suggestion.reps) * deloadRepFactor).rounded()))
            : suggestion.reps
        return Suggestion(
            weightKg: reducedLoad(suggestion.weightKg, stepKg: incrementKg),
            reps: reps,
            reason: suggestion.reason,
            adjustment: adjustment
        )
    }

    /// About 10% lighter, rounded to the nearest step; at least one step
    /// down so the change is visible, and never down to nothing.
    static func reducedLoad(_ weightKg: Double, stepKg: Double) -> Double {
        guard weightKg > 0, stepKg > 0 else { return weightKg }
        let rounded = (weightKg * reducedLoadFactor / stepKg).rounded() * stepKg
        if rounded > 0, rounded < weightKg - 0.01 { return rounded }
        let oneStepDown = weightKg - stepKg
        return oneStepDown > 0 ? oneStepDown : weightKg
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

    /// Moves each pending working set that still shows `old` to `new`.
    /// Sets the user edited keep their values, set by set.
    static func reseed(from old: Suggestion, to new: Suggestion, in sets: [SetEntry]) -> [SetEntry] {
        sets.map { set in
            guard !set.completed, !set.isWarmup, set.supportsRepLogging,
                  set.weightKg == old.weightKg, set.reps == old.reps
            else { return set }
            var updated = set
            updated.weightKg = new.weightKg
            updated.reps = new.reps
            return updated
        }
    }

    /// True when some pending working set still differs from the suggestion,
    /// which is when offering "Use" makes sense.
    static func isPending(_ suggestion: Suggestion, in sets: [SetEntry]) -> Bool {
        apply(suggestion, to: sets) != sets
    }
}
