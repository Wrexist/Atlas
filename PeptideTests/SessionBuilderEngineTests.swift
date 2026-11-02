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
        XCTAssertEqual(Engine.Target(.lowerBack), .hamstrings)
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
            .lowerBack: .init(fraction: 0.3, lastTrained: nil),
        ]
        let states = Engine.states(recovery: recovery, weekly: [.hamstringLateral: 4, .hamstringMedial: 4])
        XCTAssertEqual(states[.hamstrings]?.recovery.status, .rest)
    }

    // MARK: - Building

    func test_build_focusLeadsAndCompoundsComeBeforeIsolation() {
        let routine = build(focus: .chest, companions: [.shoulders, .triceps])
        let patterns = routine.exercises.compactMap { pattern(of: $0.exerciseID) }
        XCTAssertEqual(patterns.first, .horizontalPush)
        let firstIsolation = patterns.firstIndex { !$0.isCompound } ?? patterns.count
        XCTAssertTrue(patterns[firstIsolation...].allSatisfy { !$0.isCompound })
        XCTAssertEqual(routine.name, Engine.Target.chest.displayName)
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

    func test_build_deload_halvesVolumeAndEasesEffort() {
        let normal = build(focus: .quads, companions: [.glutes])
        let deload = build(focus: .quads, companions: [.glutes], deload: true)
        XCTAssertLessThan(RoutineSeedEngine.totalSets(in: deload), RoutineSeedEngine.totalSets(in: normal))
        XCTAssertTrue(deload.exercises.allSatisfy { $0.targetRPE == 6.5 })
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
        familiar: Set<String> = [],
        deload: Bool = false
    ) -> Engine.Request {
        Engine.Request(focus: focus, companions: companions, minutes: minutes, experience: .intermediate,
                       equipment: equipment, states: fresh(), familiarExerciseIDs: familiar, isDeload: deload)
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
                             familiar: familiar, deload: deload), catalog: catalog)
    }

    private func pattern(of id: String) -> MovementPattern? {
        MovementPattern.allCases.first { ProgramGeneratorEngine.candidates(for: $0).contains(id) }
    }
}
