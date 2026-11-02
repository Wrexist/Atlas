import XCTest
@testable import Peptide

final class SetCarryEngineTests: XCTestCase {

    private func set(_ index: Int, _ weightKg: Double, done: Bool = false, warmup: Bool = false) -> SetEntry {
        SetEntry(index: index, weightKg: weightKg, reps: 8, completed: done, isWarmup: warmup)
    }

    func test_carryingWeight_untouchedLaterSets_takeTheTypedWeight() {
        var sets = [set(1, 0), set(2, 0), set(3, 0)]
        sets[0].weightKg = 25

        let carried = SetCarryEngine.carryingWeight(sets, after: sets[0], fromKg: 0)

        XCTAssertEqual(carried.map(\.weightKg), [25, 25, 25])
    }

    func test_carryingWeight_setsTheUserChanged_keepTheirValue() {
        var sets = [set(1, 60), set(2, 70), set(3, 60)]
        sets[0].weightKg = 62.5

        let carried = SetCarryEngine.carryingWeight(sets, after: sets[0], fromKg: 60)

        XCTAssertEqual(carried.map(\.weightKg), [62.5, 70, 62.5])
    }

    func test_carryingWeight_earlierCompletedAndWarmupSets_areLeftAlone() {
        var sets = [set(1, 0, warmup: true), set(2, 0, done: true), set(3, 0), set(4, 0, warmup: true), set(5, 0)]
        sets[2].weightKg = 40

        let carried = SetCarryEngine.carryingWeight(sets, after: sets[2], fromKg: 0)

        XCTAssertEqual(carried.map(\.weightKg), [0, 0, 40, 0, 40])
    }
}
