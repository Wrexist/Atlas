import Foundation

/// Builds one hypertrophy session around a muscle the user picked on the
/// body map: suggests companion muscles that are recovered and still short
/// of their weekly volume, picks the best exercises from the generator's
/// curated shortlist, and fits sets, reps, effort and rest to the time
/// the user has.
///
/// Deterministic and offline, like `ProgramGeneratorEngine`, whose
/// shortlist, eligibility rules, supersets and time estimate it reuses.
enum SessionBuilderEngine {

    /// A trainable muscle as the user thinks of it; groups the map's heads.
    enum Target: String, CaseIterable, Sendable {
        case chest, back, shoulders, rearDelts, biceps, triceps
        case quads, hamstrings, glutes, calves, abs

        init(_ muscle: AnatomicalMuscle) {
            switch muscle {
            case .pecSternal, .pecClavicular: self = .chest
            case .lats, .rhomboids, .trapsUpper, .trapsLower, .neck: self = .back
            case .deltAnterior, .deltLateralFront, .deltLateralBack: self = .shoulders
            case .deltPosterior: self = .rearDelts
            case .biceps, .forearmFront, .forearmBack: self = .biceps
            case .tricepsLong, .tricepsLateral: self = .triceps
            case .quadRectus, .quadLateralis, .quadMedialis, .adductors: self = .quads
            case .hamstringLateral, .hamstringMedial, .lowerBack: self = .hamstrings
            case .glutes, .gluteMedius: self = .glutes
            case .gastrocnemius, .soleus, .tibialis: self = .calves
            case .abdominals, .obliques: self = .abs
            }
        }

        var displayName: String {
            switch self {
            case .chest: String(localized: "Chest")
            case .back: String(localized: "Back")
            case .shoulders: String(localized: "Shoulders")
            case .rearDelts: String(localized: "Rear delts")
            case .biceps: String(localized: "Biceps")
            case .triceps: String(localized: "Triceps")
            case .quads: String(localized: "Quads")
            case .hamstrings: String(localized: "Hamstrings")
            case .glutes: String(localized: "Glutes")
            case .calves: String(localized: "Calves")
            case .abs: String(localized: "Abs")
            }
        }

        /// The heads whose recovery and volume speak for this muscle.
        var heads: [AnatomicalMuscle] {
            AnatomicalMuscle.allCases.filter { Target($0) == self && !$0.isAccessoryHead }
        }

        /// Compound pattern first, then the isolation that finishes it.
        var patterns: [MovementPattern] {
            switch self {
            case .chest: [.horizontalPush, .chestIsolation]
            case .back: [.verticalPull, .horizontalPull]
            case .shoulders: [.verticalPush, .lateralDelt]
            case .rearDelts: [.rearDelt]
            case .biceps: [.biceps]
            case .triceps: [.triceps]
            case .quads: [.squat, .quadIsolation]
            case .hamstrings: [.hinge, .hamstringIsolation]
            case .glutes: [.lunge, .hinge]
            case .calves: [.calves]
            case .abs: [.core]
            }
        }

        /// Muscles that share a session well, best match first.
        var companions: [Target] {
            switch self {
            case .chest: [.shoulders, .triceps, .back]
            case .back: [.biceps, .rearDelts, .chest]
            case .shoulders: [.triceps, .chest, .rearDelts]
            case .rearDelts: [.back, .biceps, .shoulders]
            case .biceps: [.triceps, .back, .rearDelts]
            case .triceps: [.biceps, .chest, .shoulders]
            case .quads: [.glutes, .hamstrings, .calves, .abs]
            case .hamstrings: [.glutes, .quads, .calves]
            case .glutes: [.hamstrings, .quads, .calves]
            case .calves: [.quads, .hamstrings, .abs]
            case .abs: [.quads, .calves, .glutes]
            }
        }
    }

    struct State: Equatable, Sendable {
        let recovery: MuscleRecoveryEngine.Recovery
        /// Hard sets in the last 7 days (secondary work counts half).
        let weeklySets: Double
    }

    /// Per-target state: the least recovered head decides, so a fried
    /// lower back keeps hamstrings off the menu.
    static func states(
        recovery: [AnatomicalMuscle: MuscleRecoveryEngine.Recovery],
        weekly: [AnatomicalMuscle: Double]
    ) -> [Target: State] {
        Dictionary(uniqueKeysWithValues: Target.allCases.map { target in
            let heads = target.heads
            let worst = heads.compactMap { recovery[$0] }.min { $0.fraction < $1.fraction }
            let sets = heads.map { weekly[$0] ?? 0 }.reduce(0, +) / Double(max(heads.count, 1))
            return (target, State(recovery: worst ?? MuscleRecoveryEngine.Recovery(fraction: 1, lastTrained: nil),
                                  weeklySets: sets))
        })
    }

    // MARK: - Companion muscles

    struct Companions: Equatable, Sendable {
        /// Best first; up to `maxCompanions`.
        let suggested: [Target]
        /// Good matches that should rest today.
        let resting: [Target]
    }

    static let maxCompanions = 3

    /// Scores each companion on recovery (40 %), how far it is from its
    /// weekly target (35 %) and how well it pairs with the focus (25 %).
    static func companions(
        for focus: Target,
        states: [Target: State],
        experience: Exercise.Level
    ) -> Companions {
        let target = MuscleVolumeTargets.weeklySets(for: experience).lowerBound
        var scored: [(target: Target, score: Double)] = []
        var resting: [Target] = []
        for (rank, candidate) in focus.companions.enumerated() {
            guard let state = states[candidate] else { continue }
            guard state.recovery.status != .rest else {
                resting.append(candidate)
                continue
            }
            let gap = MuscleVolumeTargets.remainingSets(done: state.weeklySets, experience: experience) / target
            let synergy = 1 - Double(rank) * 0.25
            scored.append((candidate, 0.4 * state.recovery.fraction + 0.35 * gap + 0.25 * synergy))
        }
        let suggested = scored.sorted { $0.score > $1.score }.prefix(maxCompanions).map { $0.target }
        return Companions(suggested: suggested, resting: resting)
    }

    // MARK: - Building the session

    struct Request: Sendable {
        var focus: Target
        var companions: [Target]
        var minutes: Int
        var experience: Exercise.Level
        var equipment: Set<EquipmentKind>
        var states: [Target: State]
        /// Exercises the user has logged before — they have a weight to
        /// progress from, so they win ties.
        var familiarExerciseIDs: Set<String> = []
        var isDeload = false
    }

    static func build(_ request: Request, catalog: [Exercise]) -> Routine {
        let pool = ProgramGeneratorEngine.Pool(
            request: ProgramRequest(goal: .hypertrophy, experience: request.experience, equipment: request.equipment),
            catalog: catalog
        )
        let bodyweight = Set(catalog.filter { $0.equipmentKind == .bodyweight }.map(\.id))
        var picks: [Pick] = []
        var used: Set<String> = []
        for target in [request.focus] + request.companions {
            let total = plannedSets(for: target, in: request)
            let chosen = exercises(for: target, pool: pool, used: used, familiar: request.familiarExerciseIDs)
                .prefix(max(1, total / ProgramGeneratorEngine.minimumSets))
            let sets = split(total, over: chosen.count)
            for (choice, count) in zip(chosen, sets) {
                picks.append(Pick(pattern: choice.pattern, exerciseID: choice.id, sets: count))
                used.insert(choice.id)
            }
        }
        // Every compound before any isolation; the focus leads each group.
        let ordered = picks.filter(\.pattern.isCompound) + picks.filter { !$0.pattern.isCompound }

        var patterns: [UUID: MovementPattern] = [:]
        var slots: [RoutineExercise] = []
        for (index, pick) in ordered.enumerated() {
            let scheme = scheme(for: pick.pattern, isFirst: index == 0, isDeload: request.isDeload)
            let slot = RoutineExercise(
                exerciseID: pick.exerciseID,
                index: index,
                targetSets: pick.sets,
                targetReps: bodyweight.contains(pick.exerciseID)
                    ? max(scheme.reps, ProgramGeneratorEngine.bodyweightMinimumReps) : scheme.reps,
                targetRPE: scheme.rpe,
                restSeconds: scheme.rest
            )
            patterns[slot.id] = pick.pattern
            slots.append(slot)
        }
        if request.minutes <= 45 {
            slots = ProgramGeneratorEngine.pairingAntagonists(slots, patterns: patterns)
        }
        return fitted(
            Routine(
                name: request.focus.displayName,
                subtitle: request.companions.map(\.displayName).joined(separator: " · "),
                exercises: slots
            ),
            minutes: request.minutes
        )
    }

    /// Hypertrophy favourites that load the muscle at long length or keep
    /// it stable near failure. They lead their pattern when available.
    static let lengthenedFavourites: Set<String> = [
        "Incline_Dumbbell_Press", "Dumbbell_Bench_Press", "Flat_Bench_Cable_Flyes", "Dumbbell_Flyes",
        "Incline_Dumbbell_Flyes", "Cable_Seated_Lateral_Raise", "Incline_Dumbbell_Curl",
        "Standing_Dumbbell_Triceps_Extension", "EZ-Bar_Skullcrusher", "Seated_Leg_Curl",
        "Romanian_Deadlift", "Hack_Squat", "Split_Squat_with_Dumbbells", "Standing_Calf_Raises",
        "Straight-Arm_Dumbbell_Pullover", "Seated_Cable_Rows", "Cable_Crunch",
    ]

    // MARK: - Pieces

    private struct Pick {
        let pattern: MovementPattern
        let exerciseID: String
        let sets: Int
    }

    /// One exercise per pattern; a single-pattern muscle gets a second
    /// variation so its volume spreads over two angles.
    private static func exercises(
        for target: Target,
        pool: ProgramGeneratorEngine.Pool,
        used: Set<String>,
        familiar: Set<String>
    ) -> [(id: String, pattern: MovementPattern)] {
        var chosen: [(id: String, pattern: MovementPattern)] = []
        var taken = used
        for pattern in target.patterns {
            let ranked = ranked(pool.eligible(for: pattern).filter { !taken.contains($0) }, familiar: familiar)
            let count = target.patterns.count == 1 ? 2 : 1
            for id in ranked.prefix(count) {
                chosen.append((id, pattern))
                taken.insert(id)
            }
        }
        return chosen
    }

    /// Logged-before first, then lengthened favourites, then shortlist order.
    private static func ranked(_ ids: [String], familiar: Set<String>) -> [String] {
        ids.enumerated().sorted { lhs, rhs in
            let left = (familiar.contains(lhs.element) ? 2 : 0) + (lengthenedFavourites.contains(lhs.element) ? 1 : 0)
            let right = (familiar.contains(rhs.element) ? 2 : 0) + (lengthenedFavourites.contains(rhs.element) ? 1 : 0)
            return left != right ? left > right : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// The focus gets a full session's volume; companions half. A muscle
    /// still recovering gets three quarters, a deload half.
    static func plannedSets(for target: Target, in request: Request) -> Int {
        let cap = Double(MuscleVolumeTargets.sessionCap(for: request.experience))
        var sets = target == request.focus ? cap : (cap / 2).rounded(.up)
        if request.states[target]?.recovery.status == .recovering { sets *= 0.75 }
        if request.isDeload { sets *= 0.5 }
        return max(ProgramGeneratorEngine.minimumSets, Int(sets.rounded()))
    }

    /// Spreads sets evenly, extra sets to the earlier (compound) lift.
    static func split(_ sets: Int, over count: Int) -> [Int] {
        guard count > 0 else { return [] }
        return (0..<count).map { $0 < sets % count ? sets / count + 1 : sets / count }
    }

    struct Scheme: Equatable, Sendable {
        let reps: Int
        /// RPE 7.5 ≈ 2–3 reps in reserve, 9 ≈ 1.
        let rpe: Double
        let rest: Int
    }

    static func scheme(for pattern: MovementPattern, isFirst: Bool, isDeload: Bool) -> Scheme {
        let base: Scheme
        switch pattern {
        case _ where pattern.isCompound && isFirst: base = Scheme(reps: 8, rpe: 7.5, rest: 150)
        case _ where pattern.isCompound: base = Scheme(reps: 10, rpe: 8, rest: 120)
        case .lateralDelt, .rearDelt, .calves, .core: base = Scheme(reps: 15, rpe: 9, rest: 60)
        default: base = Scheme(reps: 12, rpe: 9, rest: 75)
        }
        return isDeload ? Scheme(reps: base.reps, rpe: 6.5, rest: base.rest) : base
    }

    /// Trims sets from the back, then whole exercises, until the session
    /// fits. A superset partner left alone becomes a straight set.
    private static func fitted(_ routine: Routine, minutes: Int) -> Routine {
        var routine = routine
        let budget = minutes * 60
        while ProgramGeneratorEngine.plannedSeconds(for: routine) > budget, routine.exercises.count > 1 {
            if let index = routine.exercises.lastIndex(where: { $0.targetSets > ProgramGeneratorEngine.minimumSets }) {
                routine.exercises[index].targetSets -= 1
                continue
            }
            let dropped = routine.exercises.removeLast()
            if let group = dropped.supersetGroup,
               let partner = routine.exercises.firstIndex(where: { $0.supersetGroup == group }) {
                routine.exercises[partner].supersetGroup = nil
            }
        }
        return routine
    }
}

private extension AnatomicalMuscle {
    /// Heads folded into a bigger muscle on the map but too small to
    /// speak for its recovery (forearms don't stop a biceps day).
    var isAccessoryHead: Bool {
        switch self {
        case .forearmFront, .forearmBack, .neck, .tibialis, .adductors, .trapsUpper: true
        default: false
        }
    }
}
