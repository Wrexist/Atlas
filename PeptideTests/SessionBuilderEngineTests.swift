import XCTest
@testable import Peptide

/// The session builder's promises, checked against the bundled dataset:
/// the picked muscle leads, resting muscles are never suggested, every
/// exercise exists and fits the user's equipment, and the session fits
/// the time they have.
@MainActor
final class SessionBuilderEngineTests: XCTestCase {

    private typealias Engine = SessionBuilderEngine
    private static let fullGym: Set<EquipmentKind> = [.barbell, .dumbbell, .kettlebell, .cable, .machine, .band]

    private var catalog: [Exercise] = []
    private var byID: [String: Exercise] = [:]

    override func setUp() async throws {
        try await super.setUp()
        await ExerciseLibrary.shared.load()
        catalog = ExerciseLibrary.shared.bundled
        byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Targets

    func test_everyMapHead_belongsToATargetWithHeadsAndCompanions() {
        for target in Engine.Target.allCases {
            XCTAssertFalse(target.heads.isEmpty, "\(target)")
            XCTAssertFalse(target.patterns.isEmpty, "\(target)")
            XCTAssertFalse(target.companions.contains(target), "\(target)")
        }
        XCTAssertEqual(Engine.Target(.pecClavicular), .chest)
        XCTAssertEqual(Engine.Target(.lowerBack), .lowerBack)
        XCTAssertEqual(Engine.Target(.trapsUpper), .traps)
        XCTAssertEqual(Engine.Target(.forearmFront), .forearms)
    }

    func test_categories_listEveryMuscleExactlyOnce() {
        let listed = Engine.Target.Category.allCases.flatMap(\.targets)
        XCTAssertEqual(listed.count, Set(listed).count, "a muscle sits in two categories")
        XCTAssertEqual(Set(listed), Set(Engine.Target.allCases))
    }

    func test_targetsOfExercise_namesOnlyTheMainMuscles() throws {
        let curl = try XCTUnwrap(byID["Dumbbell_Bicep_Curl"])
        let squat = try XCTUnwrap(byID["Barbell_Full_Squat"])
        XCTAssertEqual(Engine.targets(of: curl), [.biceps])
        XCTAssertEqual(Engine.targets(of: squat), [.quads])
    }

    func test_lengthenedFavourites_areAllOnTheShortlist() {
        let shortlist = Set(MovementPattern.allCases.flatMap(ProgramGeneratorEngine.candidates(for:)))
        XCTAssertTrue(Engine.lengthenedFavourites.isSubset(of: shortlist),
                      "\(Engine.lengthenedFavourites.subtracting(shortlist))")
    }

    // MARK: - Companions

    func test_companions_restingMuscleIsNeverSuggested() {
        var states = fresh()
        states[.shoulders] = state(fraction: 0.4)
        let result = Engine.companions(for: .chest, states: states, experience: .intermediate)
        XCTAssertFalse(result.suggested.contains(.shoulders))
        XCTAssertEqual(result.resting, [.shoulders])
    }

    func test_companions_muscleFarFromWeeklyTargetRanksFirst() {
        var states = fresh()
        states[.shoulders] = state(fraction: 1, weeklySets: 16)
        states[.triceps] = state(fraction: 1, weeklySets: 16)
        let result = Engine.companions(for: .chest, states: states, experience: .intermediate)
        XCTAssertEqual(result.suggested.first, .back)
        XCTAssertLessThanOrEqual(result.suggested.count, Engine.maxCompanions)
    }

    func test_smartFocus_picksRecoveredMuscleWithMostVolumeLeft() {
        var states = Dictionary(uniqueKeysWithValues: Engine.Target.allCases.map { ($0, state(fraction: 1, weeklySets: 12)) })
        states[.glutes] = state(fraction: 1, weeklySets: 0)
        states[.chest] = state(fraction: 0.2, weeklySets: 0)
        XCTAssertEqual(Engine.smartFocus(states: states, experience: .intermediate), .glutes)
        let allResting = states.mapValues { _ in state(fraction: 0.1) }
        XCTAssertNil(Engine.smartFocus(states: allResting, experience: .intermediate))
    }

    func test_states_leastRecoveredHeadDecides() {
        let recovery: [AnatomicalMuscle: MuscleRecoveryEngine.Recovery] = [
            .hamstringLateral: .init(fraction: 1, lastTrained: nil),
            .hamstringMedial: .init(fraction: 0.3, lastTrained: nil),
        ]
        let states = Engine.states(recovery: recovery, weekly: [.hamstringLateral: 4, .hamstringMedial: 4])
        XCTAssertEqual(states[.hamstrings]?.recovery.status, .rest)
    }

    // MARK: - Building

    func test_build_focusExercisesLeadWithCompoundsFirst() {
        let routine = build(focus: .chest, companions: [.shoulders, .triceps])
        let chest = routine.exercises.prefix { byID[$0.exerciseID].map(Engine.targets(of:))?.contains(.chest) == true }
        XCTAssertGreaterThanOrEqual(chest.count, 2, "chest should open the session")
        XCTAssertFalse(routine.exercises.dropFirst(chest.count).contains {
            byID[$0.exerciseID].map(Engine.targets(of:)) == [.chest]
        }, "no chest-only exercise after the companions start")
        let patterns = chest.compactMap { pattern(of: $0.exerciseID) }
        XCTAssertEqual(patterns.first, .horizontalPush)
        let firstIsolation = patterns.firstIndex { !$0.isCompound } ?? patterns.count
        XCTAssertTrue(patterns[firstIsolation...].allSatisfy { !$0.isCompound })
        XCTAssertEqual(routine.name, Engine.Target.chest.displayName)
    }

    func test_build_coreFocus_leadsWithCore_otherwiseCoreCloses() {
        let coreDay = build(focus: .abs, companions: [.quads])
        let first = coreDay.exercises.first.flatMap { byID[$0.exerciseID] }
        XCTAssertTrue(first.map(Engine.targets(of:))?.contains(.abs) == true, "abs day should open with abs")

        let legDay = build(focus: .quads, companions: [.abs])
        let core = legDay.exercises.drop { byID[$0.exerciseID].map(Engine.targets(of:))?.contains(.abs) != true }
        XCTAssertFalse(core.isEmpty, "leg day with abs should include core work")
        XCTAssertLessThan(core.count, legDay.exercises.count, "legs should come first")
        XCTAssertTrue(core.allSatisfy { byID[$0.exerciseID].map(Engine.targets(of:))?.contains(.abs) == true },
                      "nothing but core after the core block starts")
    }

    func test_build_smallMuscleFocus_trainsItAndKeepsTrunkWorkLast() {
        for focus in [Engine.Target.traps, .forearms, .adductors, .lowerBack, .obliques] {
            let routine = build(focus: focus, companions: focus.companions.prefix(1).map { $0 })
            let patterns = Set(routine.exercises.compactMap { pattern(of: $0.exerciseID) })
            XCTAssertFalse(patterns.isDisjoint(with: focus.patterns), "\(focus): \(routine.exercises.map(\.exerciseID))")
        }
        let lowerBack = build(focus: .lowerBack, companions: [.hamstrings]).exercises
            .compactMap { pattern(of: $0.exerciseID) }
        let trunk: Set<MovementPattern> = [.backExtension, .core, .oblique]
        let start = lowerBack.firstIndex(of: .backExtension)
        XCTAssertTrue(lowerBack[(start ?? lowerBack.count)...].allSatisfy(trunk.contains), "\(lowerBack)")
        XCTAssertNotNil(start, "lower back focus should include back extensions")
    }

    func test_build_neverAddsASmallMuscleToFillTime() {
        for focus in Engine.Target.allCases where !focus.isMinor {
            let plan = Engine.build(request(focus: focus, companions: [], minutes: 75), catalog: catalog)
            XCTAssertFalse(plan.added.contains(where: \.isMinor), "\(focus): \(plan.added)")
        }
    }

    func test_fillCandidates_staySameRegionBeforeTheRestOfTheBody() {
        let candidates = Engine.fillCandidates(for: request(focus: .chest, companions: []))
        let afterCompanions = candidates.filter { !Engine.Target.chest.companions.contains($0) }
        XCTAssertEqual(afterCompanions.first, .rearDelts, "\(candidates)")
    }

    func test_build_focusTheKitCantTrain_buildsNothing() {
        let home = EquipmentProfile.standard(for: .home)
        let plan = Engine.build(request(focus: .adductors, companions: [.quads], profile: EquipmentProfile(
            kinds: home.kinds.subtracting([.band]), accessories: home.accessories, machines: home.machines
        )), catalog: catalog)
        XCTAssertTrue(plan.routine.exercises.isEmpty, "\(plan.routine.exercises.map(\.exerciseID))")
    }

    func test_build_restingFocus_isLighterAndNeverGrown() {
        var states = fresh()
        states[.chest] = state(fraction: 0.2)
        var resting = request(focus: .chest, companions: [], minutes: 75)
        resting.states = states
        let rested = Engine.build(resting, catalog: catalog).routine
        let normal = build(focus: .chest, companions: [], minutes: 75)
        func chestSets(_ routine: Routine) -> Int {
            routine.exercises.filter { byID[$0.exerciseID].map(Engine.targets(of:))?.contains(.chest) == true }
                .reduce(0) { $0 + $1.targetSets }
        }
        XCTAssertLessThan(chestSets(rested), chestSets(normal))
        XCTAssertLessThanOrEqual(chestSets(rested), Engine.plannedSets(for: .chest, in: resting))
    }

    func test_build_gluteAndHamstringDay_hasOneHeavyHinge() {
        let ids = build(focus: .glutes, companions: [.hamstrings], minutes: 75).exercises.map(\.exerciseID)
        let heavy: Set<String> = ["Romanian_Deadlift", "Barbell_Deadlift", "Trap_Bar_Deadlift"]
        XCTAssertLessThanOrEqual(ids.filter(heavy.contains).count, 1, "\(ids)")
        XCTAssertTrue(ids.contains("Barbell_Hip_Thrust"), "\(ids)")
    }

    func test_build_backDay_opensWithAPullNotAPullover() {
        let first = build(focus: .back, companions: [], minutes: 45).exercises.first?.exerciseID
        XCTAssertNotEqual(first, "Straight-Arm_Dumbbell_Pullover")
        XCTAssertEqual(first.flatMap(pattern(of:)), .verticalPull)
    }

    func test_build_neverPicksExcludedDrills() {
        for focus in Engine.Target.allCases {
            for equipment in [Self.fullGym, [.dumbbell, .band]] as [Set<EquipmentKind>] {
                let ids = Set(build(focus: focus, companions: [], minutes: 75, equipment: equipment).exercises.map(\.exerciseID))
                XCTAssertTrue(ids.isDisjoint(with: Engine.excluded), "\(focus): \(ids.intersection(Engine.excluded))")
            }
        }
    }

    func test_build_everyExerciseGetsAtLeastThreeSets() {
        for focus in Engine.Target.allCases {
            let routine = build(focus: focus, companions: [], minutes: 60)
            XCTAssertTrue(routine.exercises.allSatisfy { $0.targetSets >= Engine.minSetsPerExercise },
                          "\(focus): \(routine.exercises.map(\.targetSets))")
        }
    }

    func test_build_validUniqueExercisesWithinEquipmentAndTime() {
        for equipment in [Self.fullGym, [.barbell, .dumbbell], [.machine, .cable], [.bodyweight]] as [Set<EquipmentKind>] {
            for minutes in [30, 45, 60, 75] {
                let routine = build(focus: .back, companions: [.biceps, .rearDelts], minutes: minutes, equipment: equipment)
                let ids = routine.exercises.map(\.exerciseID)
                if equipment == Self.fullGym { XCTAssertGreaterThanOrEqual(ids.count, 4) }
                XCTAssertEqual(Set(ids).count, ids.count, "duplicate in \(ids)")
                for id in ids {
                    let kind = byID[id]?.equipmentKind
                    XCTAssertTrue(kind?.isAvailable(with: equipment.union([.bodyweight])) == true, "\(id) for \(equipment)")
                }
                XCTAssertLessThanOrEqual(ProgramGeneratorEngine.plannedSeconds(for: routine), minutes * 60 + 1,
                                         "\(minutes) min, \(equipment)")
            }
        }
    }

    func test_build_familiarExerciseBeatsShortlistFavourite() {
        let familiar = "Barbell_Bench_Press_-_Medium_Grip"
        let routine = build(focus: .chest, companions: [], familiar: [familiar])
        XCTAssertEqual(routine.exercises.first?.exerciseID, familiar)
    }

    func test_build_shortSession_supersetsComeInPairs() {
        let routine = build(focus: .biceps, companions: [.triceps], minutes: 30)
        let groups = Dictionary(grouping: routine.exercises.compactMap(\.supersetGroup), by: { $0 })
        XCTAssertTrue(groups.values.allSatisfy { $0.count == 2 })
    }

    /// The workout's suggestions apply the deload when it starts, so the
    /// builder only eases the effort; halving sets too deloaded it twice.
    func test_build_deload_keepsSetsAndEasesEffort() {
        let normal = build(focus: .quads, companions: [.glutes])
        let deload = build(focus: .quads, companions: [.glutes], deload: true)
        XCTAssertEqual(RoutineSeedEngine.totalSets(in: deload), RoutineSeedEngine.totalSets(in: normal))
        XCTAssertTrue(deload.exercises.allSatisfy { $0.targetRPE == 6.5 })
    }

    func test_build_companionsThatFit_areNamedInTheSubtitle() {
        let routine = build(focus: .chest, companions: [.triceps])
        XCTAssertEqual(routine.subtitle?.components(separatedBy: " · ").first, "Triceps")
    }

    // MARK: - Filling the time

    /// Abs alone made a 10-minute "60-minute" session: two exercises of
    /// four sets. The builder now grows the volume and brings in companions
    /// until the time is used.
    func test_build_singleSmallMuscle_fillsTheChosenTime() {
        let plan = Engine.build(request(focus: .abs, companions: [], minutes: 60), catalog: catalog)
        let seconds = ProgramGeneratorEngine.plannedSeconds(for: plan.routine)
        XCTAssertGreaterThanOrEqual(seconds, 45 * 60, "\(seconds / 60) min")
        XCTAssertLessThanOrEqual(seconds, 60 * 60)
        XCTAssertFalse(plan.added.isEmpty)
        XCTAssertFalse(plan.added.contains(.abs))
    }

    func test_build_everyDurationLandsCloseToItsBudget() {
        for minutes in [30, 45, 60, 75] {
            let seconds = ProgramGeneratorEngine.plannedSeconds(for: build(focus: .chest, companions: [.triceps], minutes: minutes))
            XCTAssertGreaterThanOrEqual(Double(seconds), Double(minutes * 60) * 0.85, "\(minutes) min")
            XCTAssertLessThanOrEqual(seconds, minutes * 60, "\(minutes) min")
        }
    }

    func test_build_noExerciseGetsMoreThanFiveSets() {
        for focus in Engine.Target.allCases {
            let routine = build(focus: focus, companions: [], minutes: 75)
            XCTAssertTrue(routine.exercises.allSatisfy { $0.targetSets <= Engine.maxSetsPerExercise }, "\(focus)")
        }
    }

    func test_build_restingMuscleIsNeverAddedToFill() {
        var session = request(focus: .abs, companions: [], minutes: 75)
        session.states[.quads] = state(fraction: 0.3)
        let plan = Engine.build(session, catalog: catalog)
        XCTAssertFalse(plan.added.contains(.quads))
        XCTAssertFalse(Engine.fillCandidates(for: session).contains(.quads))
    }

    func test_build_pickedCompanionsAreNotReportedAsAdded() {
        let plan = Engine.build(request(focus: .back, companions: [.biceps], minutes: 75), catalog: catalog)
        XCTAssertFalse(plan.added.contains(.biceps))
    }

    // MARK: - Equipment profile

    func test_build_homeProfile_usesOnlyItsKit() {
        let home = EquipmentProfile.standard(for: .home)
        for focus in Engine.Target.allCases {
            let plan = Engine.build(request(focus: focus, companions: [], profile: home), catalog: catalog)
            for slot in plan.routine.exercises {
                let exercise = byID[slot.exerciseID]
                XCTAssertTrue(exercise.map(home.allows) == true, "\(slot.exerciseID) at home")
                XCTAssertTrue(exercise.map { [.bodyweight, .dumbbell, .band].contains($0.equipmentKind) } == true, slot.exerciseID)
            }
        }
    }

    func test_build_untickedMachineIsNeverPicked() {
        var gym = EquipmentProfile.standard(for: .gym)
        gym.machines.subtract([.legPress, .hackSquat, .legExtension])
        let plan = Engine.build(request(focus: .quads, companions: [.glutes], profile: gym), catalog: catalog)
        let ids = Set(plan.routine.exercises.map(\.exerciseID))
        XCTAssertTrue(ids.isDisjoint(with: ["Leg_Press", "Hack_Squat", "Leg_Extensions", "Single-Leg_Leg_Extension"]), "\(ids)")
        XCTAssertFalse(ids.isEmpty)
    }

    func test_build_withoutPullUpBar_noHangingWork() {
        var gym = EquipmentProfile.standard(for: .gym)
        gym.accessories.remove(.pullUpBar)
        let plan = Engine.build(request(focus: .back, companions: [], profile: gym), catalog: catalog)
        for slot in plan.routine.exercises {
            XCTAssertFalse(byID[slot.exerciseID]?.equipmentAccessories.contains(.pullUpBar) ?? true, slot.exerciseID)
        }
    }

    func test_gymMachine_everyShortlistedMachineExerciseNamesItsMachine() {
        let shortlist = Set(MovementPattern.allCases.flatMap(ProgramGeneratorEngine.candidates(for:)))
        // A back-extension bench stands in every gym with machines; it
        // counts as there whenever any machine is.
        let anyMachine: Set<String> = ["Hyperextensions_Back_Extensions"]
        for id in shortlist where byID[id]?.equipmentKind == .machine && !anyMachine.contains(id) {
            XCTAssertNotNil(GymMachine.required(for: id), id)
        }
    }

    func test_equipmentProfileStore_remembersPlaceAndKit() throws {
        let suite = "EquipmentProfileStoreTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = EquipmentProfileStore(defaults: defaults)
        XCTAssertEqual(store.location, .gym)
        var home = store.profile(for: .home)
        home.kinds.insert(.kettlebell)
        store.set(home, for: .home)
        store.select(.home)

        let reopened = EquipmentProfileStore(defaults: defaults)
        XCTAssertEqual(reopened.location, .home)
        XCTAssertEqual(reopened.current, home)
        XCTAssertEqual(reopened.profile(for: .gym), .standard(for: .gym))
        defaults.removePersistentDomain(forName: suite)
    }

    func test_build_shortSessionTrimsACompanion_subtitleDropsIt() {
        let routine = build(focus: .chest, companions: [.shoulders, .back, .triceps], minutes: 20)
        XCTAssertLessThan(routine.exercises.count, 5, "A 20-minute session trims the trailing isolation work")
        XCTAssertFalse(routine.subtitle?.contains("Triceps") ?? false, routine.subtitle ?? "")
    }

    func test_plannedSets_recoveringCompanionGetsLess() {
        var session = request(focus: .chest, companions: [.triceps])
        let ready = Engine.plannedSets(for: .triceps, in: session)
        session.states[.triceps] = state(fraction: 0.8)
        XCTAssertLessThan(Engine.plannedSets(for: .triceps, in: session), ready)
        XCTAssertEqual(Engine.plannedSets(for: .chest, in: session), MuscleVolumeTargets.sessionCap(for: .intermediate))
    }

    func test_split_extraSetsGoToTheFirstExercise() {
        XCTAssertEqual(Engine.split(7, over: 2), [4, 3])
        XCTAssertEqual(Engine.split(4, over: 1), [4])
        XCTAssertEqual(Engine.split(3, over: 0), [])
    }

    // MARK: - Helpers

    private func fresh() -> [Engine.Target: Engine.State] {
        Dictionary(uniqueKeysWithValues: Engine.Target.allCases.map { ($0, state(fraction: 1)) })
    }

    private func state(fraction: Double, weeklySets: Double = 0) -> Engine.State {
        Engine.State(recovery: .init(fraction: fraction, lastTrained: nil), weeklySets: weeklySets)
    }

    private func request(
        focus: Engine.Target,
        companions: [Engine.Target],
        minutes: Int = 60,
        equipment: Set<EquipmentKind> = SessionBuilderEngineTests.fullGym,
        profile: EquipmentProfile? = nil,
        familiar: Set<String> = [],
        deload: Bool = false
    ) -> Engine.Request {
        Engine.Request(focus: focus, companions: companions, minutes: minutes, experience: .intermediate,
                       equipment: profile ?? EquipmentProfile(access: equipment), states: fresh(),
                       familiarExerciseIDs: familiar, isDeload: deload)
    }

    private func build(
        focus: Engine.Target,
        companions: [Engine.Target],
        minutes: Int = 60,
        equipment: Set<EquipmentKind> = SessionBuilderEngineTests.fullGym,
        familiar: Set<String> = [],
        deload: Bool = false
    ) -> Routine {
        Engine.build(request(focus: focus, companions: companions, minutes: minutes, equipment: equipment,
                             familiar: familiar, deload: deload), catalog: catalog).routine
    }

    private func pattern(of id: String) -> MovementPattern? {
        MovementPattern.allCases.first { ProgramGeneratorEngine.candidates(for: $0).contains(id) }
    }
}
