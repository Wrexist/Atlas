import XCTest
@testable import Peptide

final class ProgressionEngineTests: XCTestCase {

    private func sets(_ pairs: [(Double, Int)], rpe: Double? = nil) -> [SetEntry] {
        pairs.enumerated().map { index, pair in
            SetEntry(index: index + 1, weightKg: pair.0, reps: pair.1, rpe: rpe, completed: true)
        }
    }

    // MARK: - Rule

    func test_everySetAtRangeCeiling_addsIncrementAndDropsToFloor() {
        let suggestion = ProgressionEngine.suggestion(
            previous: sets([(60, 10), (60, 10), (60, 10)]), repRange: 6...10, incrementKg: 2.5
        )
        XCTAssertEqual(suggestion, .init(weightKg: 62.5, reps: 6, reason: .addWeight))
    }

    func test_oneSetShortOfCeiling_holdsWeightAndAddsARepToTheWeakestSet() {
        let suggestion = ProgressionEngine.suggestion(
            previous: sets([(60, 10), (60, 9), (60, 8)]), repRange: 6...10, incrementKg: 2.5
        )
        XCTAssertEqual(suggestion, .init(weightKg: 60, reps: 9, reason: .addRep))
    }

    func test_weakestSetBelowRangeFloor_holdsWeightAndAimsForTheFloor() {
        let suggestion = ProgressionEngine.suggestion(
            previous: sets([(60, 6), (60, 3)]), repRange: 6...10, incrementKg: 2.5
        )
        XCTAssertEqual(suggestion, .init(weightKg: 60, reps: 6, reason: .reachRange))
    }

    func test_fixedRoutineTargetHit_addsWeightAtTheTarget() {
        let suggestion = ProgressionEngine.suggestion(
            previous: sets([(80, 8), (80, 8), (80, 9)]), repRange: 8...8, incrementKg: 2.5
        )
        XCTAssertEqual(suggestion, .init(weightKg: 82.5, reps: 8, reason: .addWeight))
    }

    func test_fixedRoutineTargetMissed_repeatsTheLoadAtTheTarget() {
        let suggestion = ProgressionEngine.suggestion(
            previous: sets([(80, 8), (80, 6)]), repRange: 8...8, incrementKg: 2.5
        )
        XCTAssertEqual(suggestion, .init(weightKg: 80, reps: 8, reason: .repeatLoad))
    }

    func test_ceilingReachedButNearFailure_doesNotAddWeight() {
        let suggestion = ProgressionEngine.suggestion(
            previous: sets([(100, 10), (100, 10)], rpe: 10), repRange: 6...10, incrementKg: 2.5
        )
        XCTAssertEqual(suggestion, .init(weightKg: 100, reps: 10, reason: .repeatLoad))
    }

    func test_onlyTheHeaviestSetsCount_backoffSetsDoNotHoldProgressionBack() {
        let suggestion = ProgressionEngine.suggestion(
            previous: sets([(100, 10), (100, 10), (80, 6)]), repRange: 6...10, incrementKg: 2.5
        )
        XCTAssertEqual(suggestion?.weightKg, 102.5)
    }

    func test_warmupsAndUncheckedSetsAreIgnored() {
        var history = sets([(60, 10), (60, 10)])
        history.append(SetEntry(index: 3, weightKg: 70, reps: 2, completed: false))
        history.append(SetEntry(index: 0, weightKg: 90, reps: 1, completed: true, isWarmup: true))
        let suggestion = ProgressionEngine.suggestion(previous: history, repRange: 6...10, incrementKg: 2.5)
        XCTAssertEqual(suggestion, .init(weightKg: 62.5, reps: 6, reason: .addWeight))
    }

    func test_bodyweight_progressesByReps() {
        let suggestion = ProgressionEngine.suggestion(
            previous: sets([(0, 12), (0, 10)]), repRange: 8...12, incrementKg: 0
        )
        XCTAssertEqual(suggestion, .init(weightKg: 0, reps: 11, reason: .addRep))
    }

    func test_noHistoryOrNoComparableLoad_hasNoSuggestion() {
        XCTAssertNil(ProgressionEngine.suggestion(previous: [], repRange: 6...10, incrementKg: 2.5))
        XCTAssertNil(ProgressionEngine.suggestion(previous: sets([(20, 10)]), repRange: 6...10, incrementKg: nil))
    }

    func test_timedSets_areNotTreatedAsReps() {
        var plank = SetEntry(index: 1, weightKg: 0, reps: 1, completed: true)
        plank.measurement = .init(kind: .timed, seconds: 60)
        XCTAssertNil(ProgressionEngine.suggestion(previous: [plank], repRange: 8...12, incrementKg: 0))
    }

    // MARK: - Inputs

    func test_repRange_prefersTheRoutineTarget() {
        XCTAssertEqual(ProgressionEngine.repRange(targetReps: 5, mechanic: .compound), 5...5)
        XCTAssertEqual(ProgressionEngine.repRange(targetReps: nil, mechanic: .compound), 6...10)
        XCTAssertEqual(ProgressionEngine.repRange(targetReps: nil, mechanic: .isolation), 8...12)
    }

    func test_imperialIncrement_isFivePoundsInKilograms() throws {
        let increment = try XCTUnwrap(ProgressionEngine.incrementKg(for: .barbell, unit: .imperial))
        XCTAssertEqual(MeasurementUnit.imperial.weightForDisplay(increment), 5, accuracy: 0.001)
        XCTAssertEqual(ProgressionEngine.incrementKg(for: .dumbbell, unit: .metric), 2)
        XCTAssertNil(ProgressionEngine.incrementKg(for: .band, unit: .metric))
    }

    func test_barbellIncrement_withPlates_isAPairOfTheLightestPlate() {
        XCTAssertEqual(ProgressionEngine.incrementKg(for: .barbell, unit: .metric, plates: [25, 20, 10, 5, 1.25]), 2.5)
        XCTAssertEqual(ProgressionEngine.incrementKg(for: .smith, unit: .metric, plates: [25, 20, 10, 5]), 10)
        XCTAssertEqual(ProgressionEngine.incrementKg(for: .trapBar, unit: .metric, plates: [20, 2.5]), 5)
    }

    func test_imperialBarbellIncrement_withPlates_convertsThePairToKilos() throws {
        let increment = try XCTUnwrap(ProgressionEngine.incrementKg(for: .ezBar, unit: .imperial, plates: [45, 10, 5]))
        XCTAssertEqual(MeasurementUnit.imperial.weightForDisplay(increment), 10, accuracy: 0.001)
    }

    func test_barbellIncrement_withNoPlates_fallsBackToTheStandardJump() {
        XCTAssertEqual(ProgressionEngine.incrementKg(for: .barbell, unit: .metric, plates: []), 2.5)
    }

    func test_nonBarIncrement_ignoresPlates() {
        XCTAssertEqual(ProgressionEngine.incrementKg(for: .machine, unit: .metric, plates: [25, 5]), 2.5)
        XCTAssertEqual(ProgressionEngine.incrementKg(for: .dumbbell, unit: .metric, plates: [25, 5]), 2)
        XCTAssertNil(ProgressionEngine.incrementKg(for: .medicineBall, unit: .metric, plates: [25, 5]))
    }

    // MARK: - Apply

    func test_apply_fillsOnlyPendingWorkingSets() {
        let logged = SetEntry(index: 1, weightKg: 60, reps: 10, completed: true)
        let warmup = SetEntry(index: 0, weightKg: 20, reps: 10, isWarmup: true)
        let pending = SetEntry(index: 2, weightKg: 60, reps: 10)
        let suggestion = ProgressionEngine.Suggestion(weightKg: 62.5, reps: 6, reason: .addWeight)

        let applied = ProgressionEngine.apply(suggestion, to: [warmup, logged, pending])

        XCTAssertEqual(applied[0], warmup)
        XCTAssertEqual(applied[1], logged)
        XCTAssertEqual(applied[2].weightKg, 62.5)
        XCTAssertEqual(applied[2].reps, 6)
        XCTAssertTrue(ProgressionEngine.isPending(suggestion, in: [pending]))
        XCTAssertFalse(ProgressionEngine.isPending(suggestion, in: applied))
    }

    // MARK: - In-session tuning

    private func logged(_ weight: Double, _ reps: Int, rpe: Double? = nil) -> SetEntry {
        SetEntry(index: 1, weightKg: weight, reps: reps, rpe: rpe, completed: true)
    }

    func test_setTwoRepsShortOfTarget_dropsOneStep() {
        XCTAssertEqual(ProgressionEngine.nextSetLoad(after: logged(80, 6), targetReps: 8, incrementKg: 2.5), 77.5)
    }

    func test_setTwoRepsOverTargetAtManageableEffort_addsOneStep() {
        XCTAssertEqual(ProgressionEngine.nextSetLoad(after: logged(80, 10, rpe: 8), targetReps: 8, incrementKg: 2.5), 82.5)
    }

    func test_setOverTargetButAGrind_keepsTheLoad() {
        XCTAssertNil(ProgressionEngine.nextSetLoad(after: logged(80, 10, rpe: 10), targetReps: 8, incrementKg: 2.5))
    }

    func test_setOneRepOffTarget_keepsTheLoad() {
        XCTAssertNil(ProgressionEngine.nextSetLoad(after: logged(80, 7), targetReps: 8, incrementKg: 2.5))
        XCTAssertNil(ProgressionEngine.nextSetLoad(after: logged(80, 9), targetReps: 8, incrementKg: 2.5))
    }

    func test_bodyweightSet_keepsTheLoad() {
        XCTAssertNil(ProgressionEngine.nextSetLoad(after: logged(0, 4), targetReps: 10, incrementKg: 0))
    }

    func test_retuned_movesOnlyPendingSetsStillAtTheOldLoad() {
        let done = SetEntry(index: 1, weightKg: 80, reps: 6, completed: true)
        let pending = SetEntry(index: 2, weightKg: 80, reps: 8, completed: false)
        let edited = SetEntry(index: 3, weightKg: 70, reps: 8, completed: false)
        let warmup = SetEntry(index: 0, weightKg: 80, reps: 5, completed: false, isWarmup: true)

        let result = ProgressionEngine.retuned([warmup, done, pending, edited], fromKg: 80, toKg: 77.5)

        XCTAssertEqual(result.map(\.weightKg), [80, 80, 77.5, 70])
    }
}
