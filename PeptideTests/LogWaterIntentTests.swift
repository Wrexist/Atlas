import XCTest
@testable import Peptide

/// Pins how the "Log water" intent turns its optional amounts into
/// fluid ounces, so metric Shortcuts don't have to convert by hand.
final class LogWaterIntentTests: XCTestCase {

    func test_fluidOunces_millilitresGiven_convertsMillilitres() {
        let ounces = LogWaterIntent.fluidOunces(ounces: nil, millilitres: 500, unit: .metric)
        XCTAssertEqual(LifestyleDataLogic.millilitres(fluidOunces: ounces), 500)
    }

    func test_fluidOunces_bothGiven_prefersMillilitres() {
        let ounces = LogWaterIntent.fluidOunces(ounces: 8, millilitres: 250, unit: .imperial)
        XCTAssertEqual(LifestyleDataLogic.millilitres(fluidOunces: ounces), 250)
    }

    func test_fluidOunces_onlyOuncesGiven_usesOunces() {
        XCTAssertEqual(LogWaterIntent.fluidOunces(ounces: 12, millilitres: nil, unit: .metric), 12)
    }

    func test_fluidOunces_noAmount_logsOneGlassInUserUnit() {
        XCTAssertEqual(LogWaterIntent.fluidOunces(ounces: nil, millilitres: nil, unit: .imperial), 8)
        XCTAssertEqual(LifestyleDataLogic.millilitres(
            fluidOunces: LogWaterIntent.fluidOunces(ounces: nil, millilitres: nil, unit: .metric)), 250)
    }
}
