import XCTest
@testable import Peptide

/// Swapping an exercise for the next best: in the session builder (the
/// engine's ranked list and the slot swap) and in the active workout (the
/// service's swap, its split around logged sets, and undo).
@MainActor
final class ExerciseSwapTests: XCTestCase {

    private typealias Engine = SessionBuilderEngine
    private static let fullGym: Set<EquipmentKind> = [.barbell, .dumbbell, .kettlebell, .cable, .machine, .band]
    private static let bench = "Barbell_Bench_Press_-_Medium_Grip"

    private var catalog: [Exercise] = []
    private var byID: [String: Exercise] = [:]
    private var service: WorkoutSessionService!

    override func setUp() async throws {
        try await super.setUp()
        await ExerciseLibrary.shared.load()
        catalog = ExerciseLibrary.shared.bundled
        byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        SwiftDataRepository.shared.configureForTesting()
        service = WorkoutSessionService.shared
        service.discardWorkout()
    }

    override func tearDown() async throws {
        service.discardWorkout()
        SwiftDataRepository.shared.deleteAll()
        try await super.tearDown()
    }

    // MARK: - Ranking

    func test_benchAlternatives_leadWithAnotherHorizontalPressOnTheChest() throws {
        let swaps = alternatives(for: Self.bench)
        let best = try XCTUnwrap(swaps.first)
        XCTAssertTrue(best.isSameMovement)
        XCTAssertTrue(ProgramGeneratorEngine.candidates(for: .horizontalPush).contains(best.id), best.id)
        let lift = try exercise(best.id)
        XCTAssertTrue(Engine.targets(of: lift).contains(.chest), best.id)
    }

    func test_alternatives_neverOfferTheExerciseItselfOrOneAlreadyPlanned() {
        let planned: Set<String> = ["Dumbbell_Bench_Press", "Incline_Dumbbell_Press"]
        let ids = alternatives(for: Self.bench, taken: planned).map(\.id)
        XCTAssertFalse(ids.contains(Self.bench))
        XCTAssertTrue(planned.isDisjoint(with: ids))
        XCTAssertEqual(ids.count, Set(ids).count, "an alternative is listed twice")
    }

    func test_alternatives_areCappedAndSameMovementComesFirst() {
        let swaps = alternatives(for: "Barbell_Squat")
        XCTAssertFalse(swaps.isEmpty)
        XCTAssertLessThanOrEqual(swaps.count, Engine.alternativeLimit)
        let firstOther = swaps.firstIndex { !$0.isSameMovement } ?? swaps.endIndex
        XCTAssertTrue(swaps[firstOther...].allSatisfy { !$0.isSameMovement }, "a same-movement lift ranked under a muscle-only one")
    }

    func test_homeKit_onlyOffersWhatTheKitAllows() {
        let home = EquipmentProfile(access: [.dumbbell, .band])
        let swaps = alternatives(for: Self.bench, equipment: home)
        XCTAssertFalse(swaps.isEmpty, "dumbbells should still give a chest press")
        for swap in swaps {
            XCTAssertTrue(byID[swap.id].map(home.allows) ?? false, "\(swap.id) needs kit the user doesn't have")
        }
    }

    func test_everyAlternative_sharesTheMovementOrTheMainMuscle() throws {
        let curl = "Dumbbell_Bicep_Curl"
        let muscles = Engine.targets(of: try exercise(curl))
        for swap in alternatives(for: curl) where !swap.isSameMovement {
            let lift = try exercise(swap.id)
            XCTAssertFalse(Engine.targets(of: lift).isDisjoint(with: muscles), swap.id)
        }
    }

    func test_familiarLift_winsItsTier() throws {
        let unfamiliar = alternatives(for: Self.bench).filter(\.isSameMovement)
        let last = try XCTUnwrap(unfamiliar.last?.id)
        XCTAssertEqual(alternatives(for: Self.bench, familiar: [last]).first?.id, last)
    }

    func test_unknownExercise_hasNoAlternatives() {
        XCTAssertTrue(alternatives(for: "Not_A_Real_Exercise").isEmpty)
    }

    // MARK: - Builder slot swap

    func test_swappingASlot_keepsItsSetsRestAndSuperset() throws {
        let group = UUID()
        let slot = RoutineExercise(exerciseID: Self.bench, index: 0, targetSets: 4, targetReps: 8,
                                   targetRPE: 7.5, restSeconds: 150, supersetGroup: group)
        let routine = Routine(name: "Chest", exercises: [slot])

        let swapped = try XCTUnwrap(Engine.swapping(slotID: slot.id, to: "Dumbbell_Bench_Press",
                                                    in: routine, catalog: catalog).exercises.first)

        XCTAssertEqual(swapped.id, slot.id)
        XCTAssertEqual(swapped.exerciseID, "Dumbbell_Bench_Press")
        XCTAssertEqual(swapped.targetSets, 4)
        XCTAssertEqual(swapped.targetReps, 8)
        XCTAssertEqual(swapped.restSeconds, 150)
        XCTAssertEqual(swapped.supersetGroup, group)
    }

    func test_swappingInABodyweightLift_raisesItsReps() throws {
        let slot = RoutineExercise(exerciseID: Self.bench, index: 0, targetSets: 3, targetReps: 6)
        let swapped = try XCTUnwrap(Engine.swapping(slotID: slot.id, to: "Pushups",
                                                    in: Routine(name: "Chest", exercises: [slot]),
                                                    catalog: catalog).exercises.first)
        XCTAssertEqual(swapped.targetReps, ProgramGeneratorEngine.bodyweightMinimumReps)
    }

    // MARK: - Workout swap

    func test_untouchedExercise_swapsInPlace() throws {
        startWorkout(sets: 3)
        let entry = try XCTUnwrap(service.activeSession?.exercises.first)

        service.swapExercise(entryID: entry.id, to: try exercise("Dumbbell_Bench_Press"))

        let session = try XCTUnwrap(service.activeSession)
        XCTAssertEqual(session.exercises.count, 2)
        XCTAssertEqual(session.exercises[0].id, entry.id)
        XCTAssertEqual(session.exercises[0].exerciseID, "Dumbbell_Bench_Press")
        XCTAssertEqual(session.exercises[0].sets.count, 3)
        XCTAssertTrue(session.exercises[0].sets.allSatisfy { !$0.completed })
        XCTAssertEqual(session.selectedExercise?.id, entry.id)
    }

    func test_swappedSets_keepTheSlotsRepTargetAndIDs() throws {
        startWorkout(sets: 3, reps: 12)
        let entry = try XCTUnwrap(service.activeSession?.exercises.first)

        service.swapExercise(entryID: entry.id, to: try exercise("Dumbbell_Bench_Press"))

        let swapped = try XCTUnwrap(service.activeSession?.exercises.first)
        XCTAssertEqual(swapped.sets.map(\.reps), [12, 12, 12])
        XCTAssertEqual(swapped.sets.map(\.id), entry.sets.map(\.id), "a running rest points at these ids")
    }

    func test_halfDoneExercise_keepsLoggedSetsAndMovesTheRestToTheNewLift() throws {
        startWorkout(sets: 3)
        let entry = try XCTUnwrap(service.activeSession?.exercises.first)
        var first = try XCTUnwrap(entry.sets.first)
        first.completed = true
        first.weightKg = 80
        service.updateSet(first, inExerciseEntryID: entry.id)

        service.swapExercise(entryID: entry.id, to: try exercise("Dumbbell_Bench_Press"))

        let session = try XCTUnwrap(service.activeSession)
        XCTAssertEqual(session.exercises.map(\.exerciseID),
                       [Self.bench, "Dumbbell_Bench_Press", "Standing_Military_Press"])
        XCTAssertEqual(session.exercises.map(\.index), [0, 1, 2])
        XCTAssertEqual(session.exercises[0].sets.count, 1)
        XCTAssertTrue(session.exercises[0].sets[0].completed)
        XCTAssertEqual(session.exercises[1].sets.count, 2)
        XCTAssertEqual(session.selectedExercise?.id, session.exercises[1].id)
    }

    func test_finishedExercise_isNotSwapped() throws {
        startWorkout(sets: 1)
        let entry = try XCTUnwrap(service.activeSession?.exercises.first)
        var set = try XCTUnwrap(entry.sets.first)
        set.completed = true
        service.updateSet(set, inExerciseEntryID: entry.id)

        service.swapExercise(entryID: entry.id, to: try exercise("Dumbbell_Bench_Press"))

        XCTAssertEqual(service.activeSession?.exercises.first?.exerciseID, Self.bench)
        XCTAssertEqual(service.activeSession?.exercises.count, 2)
    }

    func test_undo_restoresTheWorkoutAsItWas() throws {
        startWorkout(sets: 3)
        let before = try XCTUnwrap(service.activeSession?.exercises)

        service.swapExercise(entryID: before[0].id, to: try exercise("Dumbbell_Bench_Press"))
        XCTAssertTrue(service.canUndoSwap)
        service.undoSwap()

        XCTAssertEqual(service.activeSession?.exercises, before)
        XCTAssertFalse(service.canUndoSwap)
    }

    func test_undo_isGoneOnceASetIsLogged() throws {
        startWorkout(sets: 3)
        let entry = try XCTUnwrap(service.activeSession?.exercises.first)
        service.swapExercise(entryID: entry.id, to: try exercise("Dumbbell_Bench_Press"))
        var set = try XCTUnwrap(service.activeSession?.exercises.first?.sets.first)
        set.completed = true
        service.updateSet(set, inExerciseEntryID: entry.id)

        XCTAssertFalse(service.canUndoSwap)
        service.undoSwap()
        XCTAssertEqual(service.activeSession?.exercises.first?.exerciseID, "Dumbbell_Bench_Press")
    }

    // MARK: - Helpers

    private func alternatives(
        for id: String,
        taken: Set<String> = [],
        equipment: EquipmentProfile = EquipmentProfile(access: ExerciseSwapTests.fullGym),
        familiar: Set<String> = []
    ) -> [Engine.Alternative] {
        Engine.alternatives(for: id, taken: taken, equipment: equipment, experience: .intermediate,
                            familiar: familiar, catalog: catalog)
    }

    private func exercise(_ id: String) throws -> Exercise {
        try XCTUnwrap(byID[id], "\(id) missing from exercises.json")
    }

    private func startWorkout(sets: Int, reps: Int = 8) {
        service.startWorkout(routine: Routine(name: "Push", exercises: [
            RoutineExercise(exerciseID: Self.bench, index: 0, targetSets: sets, targetReps: reps),
            RoutineExercise(exerciseID: "Standing_Military_Press", index: 1, targetSets: 3, targetReps: 8),
        ]))
    }
}
