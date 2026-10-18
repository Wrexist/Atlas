import Foundation

/// Turns an exercise's raw muscle lists into the per-region involvement the
/// muscle map shows: which body parts a lift trains, how hard, and in what
/// order they light up. Pure computation so the map, the legend and the
/// body picker agree on the same numbers.
@MainActor
enum MuscleInvolvementEngine {

    enum Role: String, Sendable {
        case primary = "Primary"
        case supporting = "Supporting"
    }

    struct Row: Identifiable, Equatable, Sendable {
        let name: String
        let role: Role
        /// 0…1 share of full stimulus for the hardest-worked head in the region.
        let share: Double
        let muscles: [AnatomicalMuscle]
        var id: String { name }
    }

    /// Supporting muscles get roughly half the stimulus of a prime mover.
    static let supportingWeight = 0.5

    /// One row per visible region (heads grouped by display name), prime
    /// movers first, then by share. Only heads the map actually lights are
    /// listed, so the legend never names a muscle the figure leaves grey.
    static func rows(for exercise: Exercise) -> [Row] {
        let highlights = MuscleMapView.highlights(for: exercise)
        let weights = headWeights(for: exercise)
        let grouped = Dictionary(grouping: highlights.keys, by: \.displayName)
        return grouped.map { name, heads in
            let ordered = AnatomicalMuscle.allCases.filter { heads.contains($0) }
            return Row(
                name: name,
                role: heads.contains { highlights[$0] == .primary } ? .primary : .supporting,
                share: heads.map { weights[$0] ?? 0 }.max() ?? 0,
                muscles: ordered
            )
        }
        .sorted { lhs, rhs in
            if lhs.role != rhs.role { return lhs.role == .primary }
            if lhs.share != rhs.share { return lhs.share > rhs.share }
            return lhs.name < rhs.name
        }
    }

    /// Highlight frames for the ignite animation: prime movers first, then
    /// the full picture. A single frame when there's nothing to stage.
    static func revealStages(
        for highlights: [AnatomicalMuscle: MuscleHighlight]
    ) -> [[AnatomicalMuscle: MuscleHighlight]] {
        let primaries = highlights.filter { $0.value == .primary }
        guard !primaries.isEmpty, primaries.count < highlights.count else { return [highlights] }
        return [primaries, highlights]
    }

    /// Narrows a highlight map to one region, keeping each head's tier.
    static func focus(
        _ highlights: [AnatomicalMuscle: MuscleHighlight],
        on row: Row
    ) -> [AnatomicalMuscle: MuscleHighlight] {
        highlights.filter { row.muscles.contains($0.key) }
    }

    /// The library filter group a tapped head belongs to.
    static func group(for muscle: AnatomicalMuscle) -> MuscleGroup {
        switch muscle {
        case .pecClavicular, .pecSternal:
            return .chest
        case .deltAnterior, .deltLateralFront, .deltLateralBack, .deltPosterior, .neck:
            return .shoulders
        case .biceps, .tricepsLong, .tricepsLateral, .forearmFront, .forearmBack:
            return .arms
        case .abdominals, .obliques:
            return .core
        case .trapsUpper, .trapsLower, .rhomboids, .lats, .lowerBack:
            return .back
        case .glutes, .gluteMedius:
            return .glutes
        case .quadRectus, .quadLateralis, .quadMedialis, .adductors, .tibialis,
             .hamstringLateral, .hamstringMedial, .gastrocnemius, .soleus:
            return .legs
        }
    }

    /// Every head drawn for a filter group — what lights when it's picked.
    static func muscles(in group: MuscleGroup) -> [AnatomicalMuscle] {
        AnatomicalMuscle.allCases.filter { self.group(for: $0) == group }
    }

    private static func headWeights(for exercise: Exercise) -> [AnatomicalMuscle: Double] {
        var weights: [AnatomicalMuscle: Double] = [:]
        func merge(_ raws: [String], scale: Double) {
            for raw in raws {
                for (muscle, weight) in AnatomicalMuscle.headWeights(
                    forRawMuscle: raw, exerciseName: exercise.name
                ) {
                    weights[muscle] = max(weights[muscle] ?? 0, weight * scale)
                }
            }
        }
        merge(exercise.secondaryMuscles, scale: supportingWeight)
        merge(exercise.primaryMuscles, scale: 1)
        return weights
    }
}
