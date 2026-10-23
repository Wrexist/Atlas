import XCTest
@testable import Peptide

/// Pins how the Siri / Shortcuts water amount is read: in the user's own
/// unit, so a metric "250" is a glass, not 7.4 litres.
final class LogWaterIntentTests: XCTestCase {

    func test_metricAmount_logsThatManyMillilitres() {
        let ounces = LogWaterIntent.fluidOunces(amount: 250, unit: .metric)

        XCTAssertEqual(LifestyleDataLogic.millilitres(fluidOunces: ounces), 250)
    }

    func test_imperialAmount_logsThatManyFluidOunces() {
        XCTAssertEqual(LogWaterIntent.fluidOunces(amount: 16, unit: .imperial), 16)
    }

    func test_noAmount_logsOneGlassInTheUsersUnit() {
        XCTAssertEqual(LogWaterIntent.fluidOunces(amount: nil, unit: .imperial), 8)
        XCTAssertEqual(
            LifestyleDataLogic.millilitres(fluidOunces: LogWaterIntent.fluidOunces(amount: nil, unit: .metric)),
            250
        )
    }

    func test_oversizedImperialAmount_isCappedAtTwoGallons() {
        XCTAssertEqual(LogWaterIntent.fluidOunces(amount: 5000, unit: .imperial), 256)
    }
}
