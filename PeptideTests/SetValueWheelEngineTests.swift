import XCTest
@testable import Peptide

/// The maths behind the set picker's wheels and its minus and plus buttons.
final class SetValueWheelEngineTests: XCTestCase {

    // MARK: - Split onto the wheels

    func test_split_halfKilogram_landsOnHalfFraction() {
        XCTAssertEqual(SetValueWheelEngine.split(22.5, unit: .metric), .init(whole: 22, fraction: 0.5))
    }

    func test_split_offGridKilograms_snapsToNearestQuarter() {
        XCTAssertEqual(SetValueWheelEngine.split(72.3, unit: .metric), .init(whole: 72, fraction: 0.25))
    }

    func test_split_fractionRoundingUp_carriesIntoWholeUnit() {
        XCTAssertEqual(SetValueWheelEngine.split(59.9, unit: .metric), .init(whole: 60, fraction: 0))
        XCTAssertEqual(SetValueWheelEngine.split(134.8, unit: .imperial), .init(whole: 135, fraction: 0))
    }

    func test_split_pounds_useHalves() {
        XCTAssertEqual(SetValueWheelEngine.split(102.5, unit: .imperial), .init(whole: 102, fraction: 0.5))
        XCTAssertEqual(SetValueWheelEngine.fractions(for: .imperial), [0, 0.5])
    }

    func test_split_negative_clampsToZero() {
        XCTAssertEqual(SetValueWheelEngine.split(-3, unit: .metric), .init(whole: 0, fraction: 0))
    }

    func test_split_poundsStoredAsKilograms_roundTripsToSameWheels() {
        let kilograms = MeasurementUnit.imperial.kilograms(fromDisplayed: 225)
        let display = MeasurementUnit.imperial.weightForDisplay(kilograms)
        XCTAssertEqual(SetValueWheelEngine.split(display, unit: .imperial), .init(whole: 225, fraction: 0))
    }

    // MARK: - Ranges

    func test_wholeRange_coversHeavierStoredWeight() {
        XCTAssertEqual(SetValueWheelEngine.wholeRange(for: .metric, holding: 80).upperBound, 500)
        XCTAssertEqual(SetValueWheelEngine.wholeRange(for: .metric, holding: 612.5).upperBound, 613)
    }

    func test_wholeRange_neverPassesTheSetLimit() {
        XCTAssertEqual(SetValueWheelEngine.wholeRange(for: .metric, holding: 5000).upperBound,
                       Int(SetEntryLimits.weightKg.upperBound))
    }

    func test_repsRange_extendsForHighRepSets() {
        XCTAssertEqual(SetValueWheelEngine.repsRange(holding: 12), 0...100)
        XCTAssertEqual(SetValueWheelEngine.repsRange(holding: 150), 0...150)
    }

    // MARK: - Step buttons

    func test_displayStep_usesEquipmentIncrement() {
        XCTAssertEqual(SetValueWheelEngine.displayStep(incrementKg: 2.5, unit: .metric), 2.5)
        let fivePounds = MeasurementUnit.imperial.kilograms(fromDisplayed: 5)
        XCTAssertEqual(SetValueWheelEngine.displayStep(incrementKg: fivePounds, unit: .imperial), 5)
    }

    func test_displayStep_withoutComparableStep_fallsBackToSmallUnit() {
        XCTAssertEqual(SetValueWheelEngine.displayStep(incrementKg: nil, unit: .metric), 1)
        XCTAssertEqual(SetValueWheelEngine.displayStep(incrementKg: 0, unit: .imperial), 2.5)
    }

    func test_stepped_onGrid_movesOneStep() {
        XCTAssertEqual(SetValueWheelEngine.stepped(60, by: 2.5, up: true), 62.5)
        XCTAssertEqual(SetValueWheelEngine.stepped(60, by: 2.5, up: false), 57.5)
    }

    func test_stepped_offGrid_snapsToNextGridLineInDirection() {
        XCTAssertEqual(SetValueWheelEngine.stepped(81, by: 2.5, up: true), 82.5)
        XCTAssertEqual(SetValueWheelEngine.stepped(81, by: 2.5, up: false), 80)
    }

    func test_stepped_down_neverGoesBelowZero() {
        XCTAssertEqual(SetValueWheelEngine.stepped(1, by: 2.5, up: false), 0)
        XCTAssertEqual(SetValueWheelEngine.stepped(0, by: 2.5, up: false), 0)
    }

    func test_stepped_pounds_fivePoundGrid() {
        XCTAssertEqual(SetValueWheelEngine.stepped(135, by: 5, up: true), 140)
        XCTAssertEqual(SetValueWheelEngine.stepped(137.5, by: 5, up: false), 135)
    }
}
