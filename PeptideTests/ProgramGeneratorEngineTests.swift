import XCTest
@testable import Peptide

/// The generator's promises, checked against the real bundled dataset:
/// every program it can produce uses exercises that exist, never repeats
/// one within a day, only asks for equipment the user has, and fits the
/// session they said they have time for.
@MainActor
final class ProgramGeneratorEngineTests: XCTestCase {

    private var catalog: [Exercise] = []
    private var byID: [String: Exercise] = [:]

    private static let fullGym: Set<EquipmentKind> = [.barbell, .dumbbell, .kettlebell, .cable, .machine, .band]

    private static let equipmentSets: [Set<EquipmentKind>] = [
        [.bodyweight],
        [.dumbbell],
        [.band],
        [.kettlebell],
        [.barbell, .dumbbell],
        [.machine, .cable],
        [.trapBar, .swissBall, .medicineBall],
        fullGym,
        Set(EquipmentKind.allCases),
    ]

    override func setUp() async throws {
        try await super.setUp()
        await ExerciseLibrary.shared.load()
        catalog = ExerciseLibrary.shared.bundled
        byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func generate(
        days: Int = 4,
        minutes: Int = 60,
        goal: TrainingGoal = .hypertrophy,
        experience: Exercise.Level = .intermediate,
        equipment: Set<EquipmentKind> = ProgramGeneratorEngineTests.fullGym
    ) -> GeneratedProgram {
        ProgramGeneratorEngine.generate(
            ProgramRequest(goal: goal, experience: experience, daysPerWeek: days,
                           sessionMinutes: minutes, equipment: equipment),
            catalog: catalog
        )
    }

    // MARK: - Catalog

    func test_everyCandidateID_resolvesInTheBundledLibrary() {
        XCTAssertFalse(catalog.isEmpty, "exercises.json failed to load")
        for pattern in MovementPattern.allCases {
            let candidates = ProgramGeneratorEngine.candidates(for: pattern)
            XCTAssertFalse(candidates.isEmpty, "\(pattern) has no candidates")
            for id in candidates {
                XCTAssertNotNil(byID[id], "\(pattern) lists '\(id)', which is not in exercises.json")
            }
        }
    }

    func test_everyDayTemplatePattern_hasABodyweightBeginnerFallbackWhenCompound() {
        for pattern in MovementPattern.allCases where pattern.isCompound {
            let fallback = ProgramGeneratorEngine.candidates(for: pattern).contains { id in
                guard let exercise = byID[id] else { return false }
                return exercise.equipmentKind == .bodyweight && exercise.level == .beginner
            }
            XCTAssertTrue(fallback, "\(pattern) can't be filled for a beginner with no equipment")
        }
    }

    // MARK: - Every combination

    func test_everyCombination_producesValidRoutinesWithinTheConstraints() {
        for days in ProgramRequest.dayRange {
            for equipment in Self.equipmentSets {
                for goal in TrainingGoal.allCases {
                    for experience in [Exercise.Level.beginner, .intermediate, .expert] {
                        for minutes in ProgramRequest.sessionOptions {
                            let program = generate(days: days, minutes: minutes, goal: goal,
                                                   experience: experience, equipment: equipment)
                            let label = "\(days)d \(minutes)m \(goal) \(experience) \(equipment.map(\.rawValue).sorted())"
                            XCTAssertEqual(program.days.count, days, label)
                            for day in program.days {
                                assertValid(day, equipment: equipment, experience: experience,
                                            minutes: minutes, label: "\(label) \(day.routine.name)")
                            }
                        }
                    }
                }
            }
        }
    }

    private func assertValid(
        _ day: GeneratedDay,
        equipment: Set<EquipmentKind>,
        experience: Exercise.Level,
        minutes: Int,
        label: String
    ) {
        let slots = day.routine.exercises
        let ids = slots.map(\.exerciseID)
        XCTAssertGreaterThanOrEqual(slots.count, ProgramGeneratorEngine.minimumExercises, label)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate exercise in \(label): \(ids)")
        XCTAssertEqual(slots.map(\.index), Array(0..<slots.count), label)
        XCTAssertLessThanOrEqual(ProgramGeneratorEngine.plannedSeconds(for: day.routine), minutes * 60, label)
        XCTAssertLessThanOrEqual(RoutineSeedEngine.estimatedMinutes(for: day.routine), minutes, label)
        let allowed = equipment.union([.bodyweight])
        for slot in slots {
            guard let exercise = byID[slot.exerciseID] else {
                XCTFail("\(label) uses unknown id \(slot.exerciseID)")
                continue
            }
            XCTAssertTrue(exercise.equipmentKind.isAvailable(with: allowed),
                          "\(label) needs \(exercise.equipmentKind) for \(exercise.id)")
            XCTAssertTrue(exercise.equipmentAccessories.isSubset(of: EquipmentAccessory.implied(by: allowed)),
                          "\(label) needs \(exercise.equipmentAccessories) for \(exercise.id)")
            XCTAssertLessThanOrEqual(ProgramGeneratorEngine.rank(exercise.level),
                                     ProgramGeneratorEngine.rank(experience),
                                     "\(label) is too advanced: \(exercise.id)")
            XCTAssertNotNil(day.patterns[slot.id], label)
            XCTAssertGreaterThanOrEqual(slot.targetSets, ProgramGeneratorEngine.minimumSets, label)
        }
        assertSupersetsArePairedAntagonists(day, label: label)
    }

    private func assertSupersetsArePairedAntagonists(_ day: GeneratedDay, label: String) {
        let slots = day.routine.exercises.sorted { $0.index < $1.index }
        let groups = Dictionary(grouping: slots.filter { $0.supersetGroup != nil }, by: { $0.supersetGroup })
        for members in groups.values {
            XCTAssertEqual(members.count, 2, label)
            guard members.count == 2 else { continue }
            XCTAssertEqual(members[1].index - members[0].index, 1, "superset not adjacent in \(label)")
            XCTAssertEqual(day.patterns[members[0].id]?.antagonist, day.patterns[members[1].id], label)
        }
    }

    // MARK: - Split

    func test_split_followsDaysPerWeek() {
        XCTAssertEqual(generate(days: 2).split, .fullBody)
        XCTAssertEqual(generate(days: 3).split, .fullBody)
        XCTAssertEqual(generate(days: 4).split, .upperLower)
        XCTAssertEqual(generate(days: 5).split, .pushPullLegs)
        XCTAssertEqual(generate(days: 6).split, .pushPullLegs)
    }

    func test_dayNames_letterOnlyRepeatedTitles() {
        XCTAssertEqual(generate(days: 4).days.map(\.routine.name), ["Upper A", "Lower A", "Upper B", "Lower B"])
        XCTAssertEqual(generate(days: 5).days.map(\.routine.name), ["Push", "Pull", "Legs", "Upper", "Lower"])
        XCTAssertEqual(generate(days: 6).days.map(\.routine.name),
                       ["Push A", "Pull A", "Legs A", "Push B", "Pull B", "Legs B"])
    }

    // MARK: - Selection

    func test_generate_isDeterministic() {
        let first = generate(days: 5, minutes: 45, goal: .strength)
        let second = generate(days: 5, minutes: 45, goal: .strength)

        XCTAssertEqual(
            first.days.map { $0.routine.exercises.map(\.exerciseID) },
            second.days.map { $0.routine.exercises.map(\.exerciseID) }
        )
    }

    func test_fullGym_leadsWithTheClassicBarbellLifts() {
        let upper = generate(days: 4).days[0].routine.exercises.map(\.exerciseID)
        let lower = generate(days: 4).days[1].routine.exercises.map(\.exerciseID)

        XCTAssertEqual(upper.first, "Barbell_Bench_Press_-_Medium_Grip")
        XCTAssertEqual(lower.first, "Barbell_Squat")
    }

    func test_repeatedDay_prefersDifferentExercises() {
        let program = generate(days: 4)
        let upperA = Set(program.days[0].routine.exercises.map(\.exerciseID))
        let upperB = Set(program.days[2].routine.exercises.map(\.exerciseID))

        XCTAssertTrue(upperA.isDisjoint(with: upperB), "Upper B repeats \(upperA.intersection(upperB))")
    }

    func test_bodyweightOnly_usesOnlyBodyweightExercises() {
        let program = generate(days: 3, equipment: [])

        for slot in program.days.flatMap(\.routine.exercises) {
            XCTAssertEqual(byID[slot.exerciseID]?.equipmentKind, .bodyweight, slot.exerciseID)
            XCTAssertGreaterThanOrEqual(slot.targetReps, ProgramGeneratorEngine.bodyweightMinimumReps)
        }
    }

    func test_bodyweightOnly_neverNeedsAPullUpBar() {
        for days in ProgramRequest.dayRange {
            let program = generate(days: days, experience: .beginner, equipment: [])
            for day in program.days {
                for slot in day.routine.exercises {
                    let needs = byID[slot.exerciseID]?.equipmentAccessories ?? []
                    XCTAssertFalse(needs.contains(.pullUpBar), "\(days)d \(day.routine.name): \(slot.exerciseID)")
                    let options = ProgramGeneratorEngine.alternatives(forSlot: slot.id, in: day,
                                                                      request: program.request, catalog: catalog)
                    XCTAssertFalse(options.contains { byID[$0]?.equipmentAccessories.isEmpty == false }, "\(options)")
                }
            }
        }
    }

    func test_noPullingKit_fallsBackToAFullBodyWeek() {
        let program = generate(days: 5, experience: .beginner, equipment: [])

        XCTAssertEqual(program.split, .fullBody)
        XCTAssertEqual(program.days.map(\.routine.name),
                       ["Full body A", "Full body B", "Full body C", "Full body D", "Full body E"])
    }

    func test_newerEquipmentKinds_unlockTheirLifts() {
        let trapBar = generate(days: 4, equipment: [.trapBar]).days.flatMap(\.routine.exercises).map(\.exerciseID)
        XCTAssertTrue(trapBar.contains("Trap_Bar_Deadlift"), "\(trapBar)")

        let swissBall = generate(days: 4, equipment: [.swissBall]).days.flatMap(\.routine.exercises).map(\.exerciseID)
        XCTAssertTrue(swissBall.contains("Ball_Leg_Curl"), "\(swissBall)")
    }

    func test_barbell_impliesAnEZBar() {
        let ids = generate(days: 2, minutes: 90, equipment: [.barbell])
            .days.flatMap(\.routine.exercises).map(\.exerciseID)
        let kinds = Set(ids.compactMap { byID[$0]?.equipmentKind })
        XCTAssertTrue(kinds.isSubset(of: [.barbell, .ezBar, .bodyweight]), "\(kinds)")
        XCTAssertTrue(kinds.contains(.ezBar), "barbell-only lifter never gets the EZ bar: \(ids)")
    }

    // MARK: - Schemes

    func test_strengthGoal_isHeavierAndLongerRestedThanFatLoss() {
        let strength = ProgramGeneratorEngine.scheme(for: .main, goal: .strength, experience: .intermediate)
        let fatLoss = ProgramGeneratorEngine.scheme(for: .main, goal: .fatLoss, experience: .intermediate)

        XCTAssertLessThan(strength.reps, fatLoss.reps)
        XCTAssertGreaterThan(strength.restSeconds, fatLoss.restSeconds)
    }

    func test_experience_scalesCompoundVolume() {
        let beginner = ProgramGeneratorEngine.scheme(for: .main, goal: .strength, experience: .beginner)
        let expert = ProgramGeneratorEngine.scheme(for: .main, goal: .strength, experience: .expert)

        XCTAssertLessThan(beginner.sets, expert.sets)
        XCTAssertEqual(expert.reps, 3)
    }

    func test_trim_neverDropsBelowMinimumSets() {
        let trimmed = ProgramGeneratorEngine.scheme(for: .accessory, goal: .general, experience: .beginner,
                                                    trim: ProgramGeneratorEngine.maxSetTrim)

        XCTAssertEqual(trimmed.sets, ProgramGeneratorEngine.minimumSets)
    }

    // MARK: - Session length

    func test_shortSession_pairsAntagonistsIntoSupersets() {
        let program = generate(days: 4, minutes: 45)

        XCTAssertTrue(program.days.contains { day in day.routine.exercises.contains { $0.supersetGroup != nil } })
    }

    func test_longSession_needsNoSupersets() {
        let program = generate(days: 4, minutes: 90)

        XCTAssertFalse(program.days.contains { day in day.routine.exercises.contains { $0.supersetGroup != nil } })
    }

    func test_shorterSession_neverHasMoreExercises() {
        let short = generate(days: 4, minutes: 30, goal: .strength)
        let long = generate(days: 4, minutes: 90, goal: .strength)

        for (shortDay, longDay) in zip(short.days, long.days) {
            XCTAssertLessThanOrEqual(shortDay.routine.exercises.count, longDay.routine.exercises.count)
        }
    }

    // MARK: - Swapping

    func test_alternatives_doTheSameJob_andSkipWhatTheDayAlreadyHas() throws {
        let program = generate(days: 4)
        let day = program.days[0]
        let slot = try XCTUnwrap(day.routine.exercises.first)
        let pattern = try XCTUnwrap(day.patterns[slot.id])

        let options = ProgramGeneratorEngine.alternatives(forSlot: slot.id, in: day,
                                                          request: program.request, catalog: catalog)

        XCTAssertFalse(options.isEmpty)
        let dayIDs = Set(day.routine.exercises.map(\.exerciseID))
        for id in options {
            XCTAssertFalse(dayIDs.contains(id))
            XCTAssertTrue(ProgramGeneratorEngine.candidates(for: pattern).contains(id))
        }
    }

    func test_swapping_replacesOnlyThatSlot_andKeepsItsScheme() throws {
        let program = generate(days: 4)
        let day = program.days[0]
        let slot = try XCTUnwrap(day.routine.exercises.first)
        let replacement = try XCTUnwrap(
            ProgramGeneratorEngine.alternatives(forSlot: slot.id, in: day,
                                                request: program.request, catalog: catalog).first
        )

        let swapped = ProgramGeneratorEngine.swapping(slotID: slot.id, to: replacement, in: program)

        let updated = try XCTUnwrap(swapped.days[0].routine.exercises.first)
        XCTAssertEqual(updated.exerciseID, replacement)
        XCTAssertEqual(updated.targetSets, slot.targetSets)
        XCTAssertEqual(updated.targetReps, slot.targetReps)
        XCTAssertEqual(Array(swapped.days.dropFirst()), Array(program.days.dropFirst()))
    }

    // MARK: - Prefill

    func test_goalRaw_mapsOnboardingGoals() {
        XCTAssertEqual(TrainingGoal(goalRaw: "getStronger"), .strength)
        XCTAssertEqual(TrainingGoal(goalRaw: "buildMuscle"), .hypertrophy)
        XCTAssertEqual(TrainingGoal(goalRaw: "loseFat"), .fatLoss)
        XCTAssertEqual(TrainingGoal(goalRaw: "betterSleep"), .general)
        XCTAssertEqual(TrainingGoal(goalRaw: nil), .general)
    }

    func test_experienceRaw_mapsOnboardingAnswer() {
        XCTAssertEqual(ProgramRequest.experience(fromRaw: "advanced"), .expert)
        XCTAssertEqual(ProgramRequest.experience(fromRaw: "intermediate"), .intermediate)
        XCTAssertEqual(ProgramRequest.experience(fromRaw: nil), .beginner)
    }

    func test_request_clampsDaysIntoTheSupportedRange() {
        XCTAssertEqual(ProgramRequest(daysPerWeek: 1).daysPerWeek, 2)
        XCTAssertEqual(ProgramRequest(daysPerWeek: 7).daysPerWeek, 6)
    }
}
