import Foundation

/// Builds a training program from a `ProgramRequest`: picks a split for
/// the day count, fills each day's movement-pattern slots from the
/// curated shortlist (see `+Catalog`), sets the scheme by goal and
/// experience, and trims to the session length.
///
/// Deterministic and offline on purpose. The same answers always give
/// the same exercises, the result is instant, and every invariant —
/// valid ids, no repeats within a day, equipment, time budget — is
/// checkable in a unit test, which a model call could never promise.
enum ProgramGeneratorEngine {

    /// A day thinner than this reads as a warm-up, not a session. Sets are
    /// trimmed before exercises drop below it.
    static let minimumExercises = 3
    static let minimumSets = 2
    /// How many sets per slot a short session may shave off.
    static let maxSetTrim = 3
    /// Per-exercise setup the routine card's estimate leaves out: warm-up
    /// sets, loading the bar, walking to the next station. Budgeted here
    /// so a "60 minute" day actually finishes inside the hour.
    static let transitionSeconds = 90
    /// A bodyweight lift can't be loaded for a 5-rep strength set, so its
    /// target never drops below this.
    static let bodyweightMinimumReps = 10

    struct SetScheme: Equatable, Sendable {
        let sets: Int
        let reps: Int
        let restSeconds: Int
    }

    enum SlotRole: Sendable {
        /// The day's first compound — the heaviest, longest-rested lift.
        case main
        case compound
        case accessory
        case core
    }

    // MARK: - Generating

    static func generate(_ request: ProgramRequest, catalog: [Exercise]) -> GeneratedProgram {
        let pool = Pool(request: request, catalog: catalog)
        let (split, templates) = plannedWeek(days: request.daysPerWeek, pool: pool)
        let titles = dayTitles(for: templates)
        var usedInProgram: Set<String> = []
        var days: [GeneratedDay] = []
        for (number, template) in templates.enumerated() {
            let picks = pickExercises(for: template, from: pool, avoiding: usedInProgram)
            let day = fitted(
                picks,
                request: request,
                name: titles[number],
                subtitle: "\(request.goal.displayName) · day \(number + 1) of \(templates.count)"
            )
            usedInProgram.formUnion(day.routine.exercises.map(\.exerciseID))
            days.append(day)
        }
        return GeneratedProgram(request: request, split: split, days: days)
    }

    /// The split `generate` will use for this request — what the form
    /// shows before the program is built.
    static func split(for request: ProgramRequest, catalog: [Exercise]) -> TrainingSplit {
        plannedWeek(days: request.daysPerWeek, pool: Pool(request: request, catalog: catalog)).split
    }

    /// The day-count split, unless one of its days can't be filled with the
    /// user's kit (a pull day with nothing to pull on) — then a full-body
    /// rotation rather than a two-exercise day.
    private static func plannedWeek(days: Int, pool: Pool) -> (split: TrainingSplit, templates: [DayTemplate]) {
        let preferred = week(forDays: days)
        let fillable = preferred.allSatisfy { template in
            pickExercises(for: template, from: pool, avoiding: []).count >= minimumExercises
        }
        return fillable ? (TrainingSplit.forDays(days), preferred) : (.fullBody, fullBodyWeek(days: days))
    }

    /// Other exercises that do the same job as the slot, and that the user
    /// can do, minus anything already in that day.
    static func alternatives(
        forSlot slotID: UUID,
        in day: GeneratedDay,
        request: ProgramRequest,
        catalog: [Exercise]
    ) -> [String] {
        guard let pattern = day.patterns[slotID] else { return [] }
        let taken = Set(day.routine.exercises.map(\.exerciseID))
        return Pool(request: request, catalog: catalog)
            .eligible(for: pattern)
            .filter { !taken.contains($0) }
    }

    /// Replaces one slot's exercise, keeping its set scheme and superset.
    static func swapping(slotID: UUID, to exerciseID: String, in program: GeneratedProgram) -> GeneratedProgram {
        var updated = program
        for day in updated.days.indices {
            guard let slot = updated.days[day].routine.exercises.firstIndex(where: { $0.id == slotID }) else { continue }
            updated.days[day].routine.exercises[slot].exerciseID = exerciseID
        }
        return updated
    }

    // MARK: - Set schemes

    static func scheme(
        for role: SlotRole,
        goal: TrainingGoal,
        experience: Exercise.Level,
        trim: Int = 0
    ) -> SetScheme {
        let base = baseScheme(for: role, goal: goal)
        var sets = base.sets
        var reps = base.reps
        let isCompound = role == .main || role == .compound
        switch experience {
        case .beginner where isCompound && sets > 3:
            sets -= 1
        case .expert where isCompound:
            sets = min(sets + 1, 6)
            if goal == .strength && role == .main { reps = 3 }
        default:
            break
        }
        return SetScheme(sets: max(minimumSets, sets - trim), reps: reps, restSeconds: base.restSeconds)
    }

    private static func baseScheme(for role: SlotRole, goal: TrainingGoal) -> SetScheme {
        switch (goal, role) {
        case (.strength, .main):         return SetScheme(sets: 5, reps: 5, restSeconds: 180)
        case (.strength, .compound):     return SetScheme(sets: 4, reps: 6, restSeconds: 150)
        case (.strength, .accessory):    return SetScheme(sets: 3, reps: 10, restSeconds: 75)
        case (.strength, .core):         return SetScheme(sets: 3, reps: 12, restSeconds: 60)
        case (.hypertrophy, .main):      return SetScheme(sets: 4, reps: 8, restSeconds: 120)
        case (.hypertrophy, .compound):  return SetScheme(sets: 3, reps: 10, restSeconds: 90)
        case (.hypertrophy, .accessory): return SetScheme(sets: 3, reps: 12, restSeconds: 60)
        case (.hypertrophy, .core):      return SetScheme(sets: 3, reps: 15, restSeconds: 45)
        case (.fatLoss, .main):          return SetScheme(sets: 3, reps: 10, restSeconds: 75)
        case (.fatLoss, .compound):      return SetScheme(sets: 3, reps: 12, restSeconds: 60)
        case (.fatLoss, .accessory):     return SetScheme(sets: 3, reps: 15, restSeconds: 45)
        case (.fatLoss, .core):          return SetScheme(sets: 3, reps: 15, restSeconds: 30)
        case (.general, .main):          return SetScheme(sets: 3, reps: 8, restSeconds: 90)
        case (.general, .compound):      return SetScheme(sets: 3, reps: 10, restSeconds: 75)
        case (.general, .accessory):     return SetScheme(sets: 2, reps: 12, restSeconds: 60)
        case (.general, .core):          return SetScheme(sets: 2, reps: 15, restSeconds: 45)
        }
    }

    // MARK: - Days

    private struct Pick {
        let pattern: MovementPattern
        let exerciseID: String
        let isBodyweight: Bool
    }

    /// One exercise per pattern, never repeating within the day. Exercises
    /// already used on an earlier day are passed over while an unused one
    /// fits, so Upper B isn't a copy of Upper A.
    private static func pickExercises(
        for template: DayTemplate,
        from pool: Pool,
        avoiding usedInProgram: Set<String>
    ) -> [Pick] {
        var picks: [Pick] = []
        var usedToday: Set<String> = []
        for pattern in template.patterns {
            let options = pool.eligible(for: pattern).filter { !usedToday.contains($0) }
            guard let choice = options.first(where: { !usedInProgram.contains($0) }) ?? options.first else { continue }
            picks.append(Pick(pattern: pattern, exerciseID: choice, isBodyweight: pool.isBodyweight(choice)))
            usedToday.insert(choice)
        }
        return picks
    }

    /// The longest front slice of the day that fits the session. Tries full
    /// sets first, then supersets, and only trims sets when fewer than
    /// `minimumExercises` would otherwise survive.
    private static func fitted(
        _ picks: [Pick],
        request: ProgramRequest,
        name: String,
        subtitle: String
    ) -> GeneratedDay {
        let floor = min(minimumExercises, picks.count)
        var best: GeneratedDay?
        for trim in 0...maxSetTrim {
            for pairs in [false, true] {
                guard let fit = largestFit(picks, trim: trim, pairs: pairs, request: request, name: name, subtitle: subtitle)
                else { continue }
                if fit.routine.exercises.count == picks.count { return fit }
                if fit.routine.exercises.count > (best?.routine.exercises.count ?? 0) { best = fit }
            }
            if let best, best.routine.exercises.count >= floor { return best }
        }
        return best ?? build([], trim: 0, pairs: false, request: request, name: name, subtitle: subtitle)
    }

    private static func largestFit(
        _ picks: [Pick],
        trim: Int,
        pairs: Bool,
        request: ProgramRequest,
        name: String,
        subtitle: String
    ) -> GeneratedDay? {
        let budget = request.sessionMinutes * 60
        for count in stride(from: picks.count, through: 1, by: -1) {
            let day = build(Array(picks.prefix(count)), trim: trim, pairs: pairs,
                            request: request, name: name, subtitle: subtitle)
            if plannedSeconds(for: day.routine) <= budget { return day }
        }
        return nil
    }

    private static func build(
        _ picks: [Pick],
        trim: Int,
        pairs: Bool,
        request: ProgramRequest,
        name: String,
        subtitle: String
    ) -> GeneratedDay {
        var slots: [RoutineExercise] = []
        var patterns: [UUID: MovementPattern] = [:]
        for (index, pick) in picks.enumerated() {
            let setScheme = scheme(for: role(of: pick.pattern, at: index), goal: request.goal,
                                   experience: request.experience, trim: trim)
            let slot = RoutineExercise(
                exerciseID: pick.exerciseID,
                index: index,
                targetSets: setScheme.sets,
                targetReps: pick.isBodyweight ? max(setScheme.reps, bodyweightMinimumReps) : setScheme.reps,
                restSeconds: setScheme.restSeconds
            )
            slots.append(slot)
            patterns[slot.id] = pick.pattern
        }
        if pairs { slots = pairingAntagonists(slots, patterns: patterns) }
        return GeneratedDay(routine: Routine(name: name, subtitle: subtitle, exercises: slots), patterns: patterns)
    }

    /// The card's estimate plus a transition per exercise — what the
    /// session length is checked against.
    static func plannedSeconds(for routine: Routine) -> Int {
        RoutineSeedEngine.estimatedSeconds(for: routine) + routine.exercises.count * transitionSeconds
    }

    private static func role(of pattern: MovementPattern, at index: Int) -> SlotRole {
        if pattern == .core { return .core }
        guard pattern.isCompound else { return .accessory }
        return index == 0 ? .main : .compound
    }

    /// Links neighbouring antagonists (curl + pushdown) into supersets.
    /// The pair rests once per round, at the longer of the two rests.
    static func pairingAntagonists(
        _ slots: [RoutineExercise],
        patterns: [UUID: MovementPattern]
    ) -> [RoutineExercise] {
        var paired = slots
        var index = 0
        while index + 1 < paired.count {
            let first = patterns[paired[index].id]
            let second = patterns[paired[index + 1].id]
            guard let first, let second, first.antagonist == second else {
                index += 1
                continue
            }
            let group = UUID()
            let rest = max(paired[index].restSeconds ?? 0, paired[index + 1].restSeconds ?? 0)
            for member in [index, index + 1] {
                paired[member].supersetGroup = group
                paired[member].restSeconds = rest
            }
            index += 2
        }
        return paired
    }

    // MARK: - Names

    /// "Upper A", "Upper B" when a title repeats in the week; just "Push"
    /// when it doesn't.
    static func dayTitles(for templates: [DayTemplate]) -> [String] {
        let counts = Dictionary(grouping: templates, by: \.title).mapValues(\.count)
        var seen: [String: Int] = [:]
        return templates.map { template in
            guard (counts[template.title] ?? 0) > 1 else { return template.title }
            let occurrence = seen[template.title, default: 0]
            seen[template.title] = occurrence + 1
            return "\(template.title) \(Character(UnicodeScalar(UInt8(65 + occurrence))))"
        }
    }

    // MARK: - Eligibility

    /// The shortlist narrowed to what this lifter can do: equipment they
    /// have (bodyweight always, plus what `EquipmentKind.isAvailable`
    /// implies — an EZ bar with a barbell, a Smith with machines), no
    /// bench, rack, pull-up bar or box that kit doesn't vouch for, and
    /// nothing above their experience level.
    struct Pool {
        let byID: [String: Exercise]
        let equipment: Set<EquipmentKind>
        let accessories: Set<EquipmentAccessory>
        let maxLevel: Int

        init(request: ProgramRequest, catalog: [Exercise]) {
            byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            equipment = request.equipment.union([.bodyweight])
            accessories = EquipmentAccessory.implied(by: equipment)
            maxLevel = ProgramGeneratorEngine.rank(request.experience)
        }

        func isBodyweight(_ id: String) -> Bool {
            byID[id]?.equipmentKind == .bodyweight
        }

        func eligible(for pattern: MovementPattern) -> [String] {
            ProgramGeneratorEngine.candidates(for: pattern).filter { id in
                guard let exercise = byID[id] else { return false }
                return exercise.equipmentKind.isAvailable(with: equipment)
                    && exercise.equipmentAccessories.isSubset(of: accessories)
                    && ProgramGeneratorEngine.rank(exercise.level) <= maxLevel
            }
        }
    }

    static func rank(_ level: Exercise.Level) -> Int {
        switch level {
        case .beginner:     return 0
        case .intermediate: return 1
        case .expert:       return 2
        }
    }
}
