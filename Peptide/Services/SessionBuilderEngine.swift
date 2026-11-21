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
            case .back: String(localized: "muscle.back", defaultValue: "Back")
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

    /// The muscles an exercise mainly trains, as the user names them.
    static func targets(of exercise: Exercise) -> Set<Target> {
        Set(WeeklyMuscleHeatmap.stimulusHeads(for: exercise).primary
            .filter { $0.value >= 0.5 && !$0.key.isAccessoryHead }
            .map { Target($0.key) })
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

    /// "Pick for me": the most recovered muscle furthest from its weekly
    /// target. Nil only when every muscle should rest.
    static func smartFocus(states: [Target: State], experience: Exercise.Level) -> Target? {
        let target = MuscleVolumeTargets.weeklySets(for: experience).lowerBound
        func score(_ candidate: Target) -> Double {
            guard let state = states[candidate] else { return 1 }
            let gap = MuscleVolumeTargets.remainingSets(done: state.weeklySets, experience: experience) / target
            return 0.5 * state.recovery.fraction + 0.5 * gap
        }
        return Target.allCases
            .filter { states[$0]?.recovery.status != .rest }
            .max { score($0) < score($1) }
    }

    // MARK: - Building the session

    struct Request: Sendable {
        var focus: Target
        var companions: [Target]
        var minutes: Int
        var experience: Exercise.Level
        var equipment: EquipmentProfile
        var states: [Target: State]
        /// Exercises the user has logged before — they have a weight to
        /// progress from, so they win ties.
        var familiarExerciseIDs: Set<String> = []
        var isDeload = false
    }

    /// The built session and the muscles the engine added on its own to
    /// fill the time the picked ones couldn't.
    struct Plan: Sendable {
        var routine: Routine
        var added: [Target]
    }

    /// A session counts as filled once its estimate reaches this share of
    /// the budget; the last few minutes go to warming up and moving kit.
    static let fillShare = 0.9
    /// Most sets one exercise gets before volume moves to another.
    static let maxSetsPerExercise = 5

    static func build(_ request: Request, catalog: [Exercise]) -> Plan {
        let pool = Pool(profile: request.equipment, experience: request.experience, catalog: catalog)
        let budget = request.minutes * 60
        var targets = [request.focus] + request.companions
        var sets = Dictionary(uniqueKeysWithValues: targets.map { ($0, plannedSets(for: $0, in: request)) })
        var extras = fillCandidates(for: request).filter { !targets.contains($0) }
        var assembled = assemble(targets: targets, sets: sets, request: request, pool: pool)

        // Grow the picked muscles to a full session's volume first, then
        // bring in the next-best companion, until the time is used.
        while ProgramGeneratorEngine.plannedSeconds(for: assembled.routine) < Int(Double(budget) * fillShare) {
            var grown = sets
            var grownTargets = targets
            if let target = targets.first(where: { (sets[$0] ?? 0) < ceiling(for: $0, in: request, pool: pool) }) {
                grown[target, default: 0] += 1
            } else if !extras.isEmpty {
                let next = extras.removeFirst()
                guard !pool.exercises(for: next, used: [], familiar: []).isEmpty else { continue }
                // Joins small and grows a set at a time, so the last
                // minutes fill in steps of one set, not one muscle.
                grownTargets.append(next)
                grown[next] = ProgramGeneratorEngine.minimumSets
            } else {
                break
            }
            let candidate = assemble(targets: grownTargets, sets: grown, request: request, pool: pool)
            guard ProgramGeneratorEngine.plannedSeconds(for: candidate.routine) <= budget else { break }
            (sets, targets, assembled) = (grown, grownTargets, candidate)
        }

        var routine = fitted(assembled.routine, minutes: request.minutes)
        // Named after fitting, so a companion trimmed out of a short session
        // isn't promised in the subtitle.
        let kept = Set(routine.exercises.compactMap { assembled.owners[$0.id] })
        let others = targets.dropFirst().filter(kept.contains)
        routine.subtitle = others.map(\.displayName).joined(separator: " · ")
        let added = others.filter { !request.companions.contains($0) }
        return Plan(routine: routine, added: Array(added))
    }

    /// Muscles that may join to fill the time: the focus's own companions
    /// first, then everything else, most recovered and furthest from its
    /// weekly target first. Muscles that should rest never join.
    static func fillCandidates(for request: Request) -> [Target] {
        let target = MuscleVolumeTargets.weeklySets(for: request.experience).lowerBound
        func score(_ candidate: Target) -> Double {
            guard let state = request.states[candidate] else { return 1 }
            let gap = MuscleVolumeTargets.remainingSets(done: state.weeklySets, experience: request.experience) / target
            return 0.5 * state.recovery.fraction + 0.5 * gap
        }
        // Ties keep the declaration order, so the same request always
        // builds the same session.
        let others = Target.allCases
            .filter { !request.focus.companions.contains($0) && $0 != request.focus }
            .enumerated()
            .sorted { lhs, rhs in
                let left = score(lhs.element), right = score(rhs.element)
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .map(\.element)
        return (request.focus.companions + others)
            .filter { request.states[$0]?.recovery.status != .rest }
    }

    /// Most sets a muscle takes in one session: a little past the cap for
    /// the focus, the cap for the rest, and never more than its available
    /// exercises can carry.
    private static func ceiling(for target: Target, in request: Request, pool: Pool) -> Int {
        let cap = MuscleVolumeTargets.sessionCap(for: request.experience)
        let volume = target == request.focus ? cap + 2 : cap
        let available = pool.exercises(for: target, used: [], familiar: []).count
        return min(volume, available * maxSetsPerExercise)
    }

    private struct Assembled {
        var routine: Routine
        var owners: [UUID: Target]
    }

    private static func assemble(
        targets: [Target],
        sets: [Target: Int],
        request: Request,
        pool: Pool
    ) -> Assembled {
        var picks: [Pick] = []
        var used: Set<String> = []
        for target in targets {
            let total = sets[target] ?? 0
            let wanted = max(1, total / ProgramGeneratorEngine.minimumSets,
                             Int((Double(total) / Double(maxSetsPerExercise)).rounded(.up)))
            let chosen = pool.exercises(for: target, used: used, familiar: request.familiarExerciseIDs).prefix(wanted)
            for (choice, count) in zip(chosen, split(total, over: chosen.count)) {
                picks.append(Pick(target: target, pattern: choice.pattern, exerciseID: choice.id,
                                  sets: min(count, maxSetsPerExercise)))
                used.insert(choice.id)
            }
        }
        // Every compound before any isolation; the focus leads each group.
        let ordered = picks.filter(\.pattern.isCompound) + picks.filter { !$0.pattern.isCompound }

        var patterns: [UUID: MovementPattern] = [:]
        var owners: [UUID: Target] = [:]
        var slots: [RoutineExercise] = []
        for (index, pick) in ordered.enumerated() {
            let scheme = scheme(for: pick.pattern, isFirst: index == 0, isDeload: request.isDeload)
            let slot = RoutineExercise(
                exerciseID: pick.exerciseID,
                index: index,
                targetSets: pick.sets,
                targetReps: pool.isBodyweight(pick.exerciseID)
                    ? max(scheme.reps, ProgramGeneratorEngine.bodyweightMinimumReps) : scheme.reps,
                targetRPE: scheme.rpe,
                restSeconds: scheme.rest
            )
            patterns[slot.id] = pick.pattern
            owners[slot.id] = pick.target
            slots.append(slot)
        }
        if request.minutes <= 45 {
            slots = ProgramGeneratorEngine.pairingAntagonists(slots, patterns: patterns)
        }
        return Assembled(routine: Routine(name: request.focus.displayName, exercises: slots), owners: owners)
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
        let target: Target
        let pattern: MovementPattern
        let exerciseID: String
        let sets: Int
    }

    /// The shortlist narrowed to what the user's equipment profile and
    /// experience allow.
    struct Pool {
        let byID: [String: Exercise]
        let profile: EquipmentProfile
        let maxLevel: Int

        init(profile: EquipmentProfile, experience: Exercise.Level, catalog: [Exercise]) {
            byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            self.profile = profile
            maxLevel = ProgramGeneratorEngine.rank(experience)
        }

        func isBodyweight(_ id: String) -> Bool {
            byID[id]?.equipmentKind == .bodyweight
        }

        func eligible(for pattern: MovementPattern) -> [String] {
            ProgramGeneratorEngine.candidates(for: pattern).filter { id in
                guard let exercise = byID[id] else { return false }
                return profile.allows(exercise) && ProgramGeneratorEngine.rank(exercise.level) <= maxLevel
            }
        }

        /// One exercise per pattern; a single-pattern muscle gets a second
        /// variation so its volume spreads over two angles.
        func exercises(
            for target: Target,
            used: Set<String>,
            familiar: Set<String>
        ) -> [(id: String, pattern: MovementPattern)] {
            var chosen: [(id: String, pattern: MovementPattern)] = []
            var taken = used
            for pattern in target.patterns {
                let ranked = SessionBuilderEngine.ranked(eligible(for: pattern).filter { !taken.contains($0) },
                                                         familiar: familiar)
                let count = target.patterns.count == 1 ? 2 : 1
                for id in ranked.prefix(count) {
                    chosen.append((id, pattern))
                    taken.insert(id)
                }
            }
            return chosen
        }
    }

    /// Logged-before first, then lengthened favourites, then shortlist order.
    fileprivate static func ranked(_ ids: [String], familiar: Set<String>) -> [String] {
        ids.enumerated().sorted { lhs, rhs in
            let left = (familiar.contains(lhs.element) ? 2 : 0) + (lengthenedFavourites.contains(lhs.element) ? 1 : 0)
            let right = (familiar.contains(rhs.element) ? 2 : 0) + (lengthenedFavourites.contains(rhs.element) ? 1 : 0)
            return left != right ? left > right : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// The focus gets a full session's volume; companions half. A muscle
    /// still recovering gets three quarters. A deload keeps the sets: the
    /// workout's suggestions lighten the load and reps when it starts, so
    /// cutting sets here too would deload it twice.
    static func plannedSets(for target: Target, in request: Request) -> Int {
        let cap = Double(MuscleVolumeTargets.sessionCap(for: request.experience))
        var sets = target == request.focus ? cap : (cap / 2).rounded(.up)
        if request.states[target]?.recovery.status == .recovering { sets *= 0.75 }
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
