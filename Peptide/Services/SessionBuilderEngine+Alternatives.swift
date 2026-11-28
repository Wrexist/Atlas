import Foundation

/// Next-best exercises to swap in for one the user doesn't want today:
/// the same movement on the same muscle first, then the same movement,
/// then another shortlist lift on the same muscle. Shared by the session
/// builder's swipe and the active workout's swap button.
extension SessionBuilderEngine {

    struct Alternative: Equatable, Sendable {
        let id: String
        /// Same movement pattern as the lift it replaces; otherwise it
        /// only shares the main muscle.
        let isSameMovement: Bool
    }

    /// How many swaps a row offers: enough to choose, few enough to scan.
    static let alternativeLimit = 5

    /// Best first. Only curated shortlist lifts the user's kit and
    /// experience allow, never the exercise itself or one in `taken`.
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
        let patterns = Set(MovementPattern.allCases.filter {
            ProgramGeneratorEngine.candidates(for: $0).contains(exerciseID)
        })
        let muscles = pool.byID[exerciseID].map(targets(of:)) ?? []
        let mechanic = pool.byID[exerciseID]?.mechanic
        let preferred = muscles.reduce(into: Set<String>()) { $0.formUnion($1.preferred) }

        var tiers: [String: Int] = [:]
        for pattern in MovementPattern.allCases {
            for id in pool.eligible(for: pattern) where id != exerciseID && !taken.contains(id) {
                guard let candidate = pool.byID[id] else { continue }
                let samePattern = patterns.contains(pattern)
                let sameMuscle = !muscles.isDisjoint(with: targets(of: candidate))
                let tier: Int
                switch (samePattern, sameMuscle) {
                case (true, true): tier = 3
                case (true, false): tier = 2
                case (false, true): tier = candidate.mechanic == mechanic ? 1 : 0
                case (false, false): continue
                }
                tiers[id] = max(tiers[id] ?? 0, tier)
            }
        }
        // Shortlist order inside a tier, so each tier reads like the coach's list.
        var seen: Set<String> = []
        let unique = MovementPattern.allCases.flatMap(ProgramGeneratorEngine.candidates(for:))
            .filter { tiers[$0] != nil && seen.insert($0).inserted }
        let byTier = Dictionary(grouping: unique) { tiers[$0] ?? 0 }
        return byTier.keys.sorted(by: >).flatMap { tier in
            ranked(byTier[tier] ?? [], familiar: familiar, preferred: preferred)
                .map { Alternative(id: $0, isSameMovement: tier >= 2) }
        }
        .prefix(limit)
        .map { $0 }
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
