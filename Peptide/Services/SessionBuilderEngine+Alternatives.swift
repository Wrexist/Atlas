import Foundation

/// Next-best exercises to swap in for one the user doesn't want today:
/// the same movement on the same part of the muscle first, then the same
/// movement at another angle, then the same movement on another muscle,
/// then another shortlist lift of the same kind on the same muscle. Shared by the session
/// builder's swipe and the active workout's swap button.
extension SessionBuilderEngine {

    struct Alternative: Equatable, Sendable {
        enum Match: Int, CaseIterable, Comparable, Sendable {
            /// Another muscle, or the same muscle by another movement.
            case sameMuscle
            /// The same movement pattern on another muscle.
            case similarMovement
            /// The same movement on the same muscle at another angle.
            case otherAngle
            /// The same movement loading the same part of the muscle.
            case sameMovement

            static func < (lhs: Match, rhs: Match) -> Bool { lhs.rawValue < rhs.rawValue }
        }

        let id: String
        let match: Match
    }

    /// How many swaps a row offers: enough to choose, few enough to scan.
    static let alternativeLimit = 5

    /// Best first. Only curated shortlist lifts the user's kit and
    /// experience allow, never the exercise itself or one in `taken`.
    /// Inside a match, the muscle's preferred lifts, then ones the user
    /// has logged, then the coach's shortlist order.
    static func alternatives(
        for exerciseID: String,
        taken: Set<String>,
        equipment: EquipmentProfile,
        experience: Exercise.Level,
        familiar: Set<String>,
        catalog: [Exercise],
        limit: Int = alternativeLimit
    ) -> [Alternative] {
        let pool = Pool(profile: equipment, experience: experience, catalog: catalog)
        guard let original = pool.byID[exerciseID] else { return [] }
        let patterns = Set(MovementPattern.allCases.filter {
            ProgramGeneratorEngine.candidates(for: $0).contains(exerciseID)
        })
        let muscles = targets(of: original)
        let head = dominantHead(of: original)
        let preferred = muscles.reduce(into: Set<String>()) { $0.formUnion($1.preferred) }

        var matches: [String: Alternative.Match] = [:]
        for pattern in MovementPattern.allCases {
            for id in pool.eligible(for: pattern) where id != exerciseID && !taken.contains(id) {
                guard let candidate = pool.byID[id] else { continue }
                let samePattern = patterns.contains(pattern)
                let sameMuscle = !muscles.isDisjoint(with: targets(of: candidate))
                let match: Alternative.Match
                switch (samePattern, sameMuscle) {
                case (true, true): match = dominantHead(of: candidate) == head ? .sameMovement : .otherAngle
                case (true, false): match = .similarMovement
                case (false, true) where candidate.mechanic == original.mechanic: match = .sameMuscle
                default: continue
                }
                matches[id] = max(matches[id] ?? match, match)
            }
        }
        var seen: Set<String> = []
        let shortlist = MovementPattern.allCases.flatMap(ProgramGeneratorEngine.candidates(for:))
            .filter { matches[$0] != nil && seen.insert($0).inserted }
        func weight(_ id: String) -> Int {
            (preferred.contains(id) ? 2 : 0) + (familiar.contains(id) ? 1 : 0)
        }
        return shortlist.enumerated()
            .sorted { lhs, rhs in
                let left = matches[lhs.element] ?? .sameMuscle, right = matches[rhs.element] ?? .sameMuscle
                if left != right { return left > right }
                let leftWeight = weight(lhs.element), rightWeight = weight(rhs.element)
                return leftWeight != rightWeight ? leftWeight > rightWeight : lhs.offset < rhs.offset
            }
            .prefix(limit)
            .map { Alternative(id: $0.element, match: matches[$0.element] ?? .sameMuscle) }
    }

    /// The head an exercise loads most: flat and incline presses both train
    /// the chest, but not the same part of it.
    private static func dominantHead(of exercise: Exercise) -> AnatomicalMuscle? {
        WeeklyMuscleHeatmap.stimulusHeads(for: exercise).primary.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key.rawValue > rhs.key.rawValue
        }?.key
    }

    /// Puts `exerciseID` in the slot, keeping its sets, rest and superset.
    /// A bodyweight swap-in gets the reps a bodyweight lift needs.
    static func swapping(slotID: UUID, to exerciseID: String, in routine: Routine, catalog: [Exercise]) -> Routine {
        var routine = routine
        guard let index = routine.exercises.firstIndex(where: { $0.id == slotID }) else { return routine }
        routine.exercises[index].exerciseID = exerciseID
        if catalog.first(where: { $0.id == exerciseID })?.equipmentKind == .bodyweight {
            routine.exercises[index].targetReps = max(routine.exercises[index].targetReps,
                                                      ProgramGeneratorEngine.bodyweightMinimumReps)
        }
        return routine
    }
}
