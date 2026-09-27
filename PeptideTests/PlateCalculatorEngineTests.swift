import XCTest
@testable import Peptide

/// The plate maths behind the bar-loading sheet. Every figure is in one
/// display unit; the engine never converts, so kg and lb cases are the same
/// algorithm with different defaults.
final class PlateCalculatorEngineTests: XCTestCase {

    private func loadout(
        _ target: Double,
        bar: Double = 20,
        plates: [Double] = PlateCalculatorEngine.kilogramPlates,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> PlateCalculatorEngine.Loadout? {
        guard case .loaded(let loadout) = PlateCalculatorEngine.calculate(
            target: target, barWeight: bar, plates: plates
        ) else {
            XCTFail("expected a loadout for \(target)", file: file, line: line)
            return nil
        }
        return loadout
    }

    // MARK: - Defaults

    func test_defaultBarWeight_isTwentyKilosOrFortyFivePounds() {
        XCTAssertEqual(PlateCalculatorEngine.defaultBarWeight(for: .metric), 20)
        XCTAssertEqual(PlateCalculatorEngine.defaultBarWeight(for: .imperial), 45)
    }

    func test_defaultPlates_matchUnit() {
        XCTAssertEqual(PlateCalculatorEngine.defaultPlates(for: .metric), [25, 20, 15, 10, 5, 2.5, 1.25])
        XCTAssertEqual(PlateCalculatorEngine.defaultPlates(for: .imperial), [45, 35, 25, 10, 5, 2.5])
    }

    // MARK: - Exact loads

    func test_targetEqualToBar_loadsNoPlates() {
        let result = loadout(20)
        XCTAssertEqual(result?.platesPerSide, [])
        XCTAssertEqual(result?.loadedTotal, 20)
        XCTAssertEqual(result?.isExact, true)
    }

    func test_hundredKilos_isTwentyFivePlusFifteenPerSide() {
        let result = loadout(100)
        XCTAssertEqual(result?.platesPerSide, [25, 15])
        XCTAssertEqual(result?.remainder, 0)
    }

    func test_repeatedPlate_isCountedNotRepeatedInPerSide() {
        let result = loadout(220)
        XCTAssertEqual(result?.perSide, [
            PlateCalculatorEngine.PlateCount(weight: 25, count: 4)
        ])
        XCTAssertEqual(result?.platesPerSide, [25, 25, 25, 25])
    }

    func test_changePlates_addUpExactlyWithoutFloatingPointDrift() {
        // 20 + 2 × (25 + 10 + 2.5 + 1.25) = 97.5
        let result = loadout(97.5)
        XCTAssertEqual(result?.platesPerSide, [25, 10, 2.5, 1.25])
        XCTAssertEqual(result?.loadedTotal, 97.5)
        XCTAssertEqual(result?.isExact, true)
    }

    func test_pounds_twoTwentyFive_isTwoFortyFivesPerSide() {
        let result = loadout(225, bar: 45, plates: PlateCalculatorEngine.poundPlates)
        XCTAssertEqual(result?.platesPerSide, [45, 45])
        XCTAssertEqual(result?.isExact, true)
    }

    func test_pounds_oneThirtyFive_usesTheFortyFive() {
        let result = loadout(135, bar: 45, plates: PlateCalculatorEngine.poundPlates)
        XCTAssertEqual(result?.platesPerSide, [45])
    }

    func test_pounds_mixedPlates_greedyLargestFirst() {
        // 220 lb: 87.5 per side → 45 + 35 + 5 + 2.5.
        let result = loadout(220, bar: 45, plates: PlateCalculatorEngine.poundPlates)
        XCTAssertEqual(result?.platesPerSide, [45, 35, 5, 2.5])
        XCTAssertEqual(result?.isExact, true)
    }

    // MARK: - Remainders

    func test_unloadableTarget_reportsRemainderAndNeverOvershoots() {
        // 101 kg: 40.5 per side → 25 + 15 = 40, leaving 0.5 per side.
        let result = loadout(101)
        XCTAssertEqual(result?.platesPerSide, [25, 15])
        XCTAssertEqual(result?.loadedTotal, 100)
        XCTAssertEqual(result?.remainder, 1)
        XCTAssertEqual(result?.isExact, false)
    }

    func test_remainderBelowSmallestPlatePair_leavesBarOnly() {
        let result = loadout(22)
        XCTAssertEqual(result?.platesPerSide, [])
        XCTAssertEqual(result?.loadedTotal, 20)
        XCTAssertEqual(result?.remainder, 2)
    }

    func test_oddHundredthSplit_roundsPerSideDown() {
        // 20.01 can't split into two equal sides of a whole hundredth.
        let result = loadout(20.01)
        XCTAssertEqual(result?.loadedTotal, 20)
        XCTAssertEqual(result?.remainder, 0.01)
    }

    // MARK: - Plate sets

    func test_customPlates_areSortedAndDeduplicated() {
        let result = loadout(60, plates: [5, 10, 10, 5])
        XCTAssertEqual(result?.platesPerSide, [10, 10])
    }

    func test_nonPositiveAndNonFinitePlates_areIgnored() {
        let result = loadout(40, plates: [0, -10, .nan, .infinity, 10])
        XCTAssertEqual(result?.platesPerSide, [10])
    }

    func test_noPlates_leavesWholeLoadAsRemainder() {
        let result = loadout(60, plates: [])
        XCTAssertEqual(result?.platesPerSide, [])
        XCTAssertEqual(result?.remainder, 40)
    }

    // MARK: - Guards

    func test_targetBelowBar_isBelowBar() {
        XCTAssertEqual(
            PlateCalculatorEngine.calculate(target: 15, barWeight: 20, plates: PlateCalculatorEngine.kilogramPlates),
            .belowBar
        )
    }

    func test_nonPositiveOrNonFiniteInputs_areInvalid() {
        let plates = PlateCalculatorEngine.kilogramPlates
        XCTAssertEqual(PlateCalculatorEngine.calculate(target: 0, barWeight: 20, plates: plates), .invalid)
        XCTAssertEqual(PlateCalculatorEngine.calculate(target: -60, barWeight: 20, plates: plates), .invalid)
        XCTAssertEqual(PlateCalculatorEngine.calculate(target: .nan, barWeight: 20, plates: plates), .invalid)
        XCTAssertEqual(PlateCalculatorEngine.calculate(target: 60, barWeight: 0, plates: plates), .invalid)
        XCTAssertEqual(PlateCalculatorEngine.calculate(target: 60, barWeight: .infinity, plates: plates), .invalid)
    }

    func test_absurdTarget_isInvalidRatherThanOverflowing() {
        XCTAssertEqual(
            PlateCalculatorEngine.calculate(target: 1e300, barWeight: 20, plates: PlateCalculatorEngine.kilogramPlates),
            .invalid
        )
    }

    func test_largeButPlausibleTarget_countsPlatesWithoutLooping() {
        let result = loadout(PlateCalculatorEngine.maximumWeight)
        // (10 000 − 20) / 2 = 4 990 per side = 199 × 25 + 15.
        XCTAssertEqual(result?.perSide, [
            PlateCalculatorEngine.PlateCount(weight: 25, count: 199),
            PlateCalculatorEngine.PlateCount(weight: 15, count: 1)
        ])
        XCTAssertEqual(result?.isExact, true)
    }
}
