import XCTest
@testable import Peptide

final class BodyMeasurementInputTests: XCTestCase {

    func test_metricValue_swedishDecimalComma_parses() {
        XCTAssertEqual(BodyMeasurementInput.metricValue("18,5", for: .bodyFat, unit: .metric), 18.5)
    }

    func test_metricValue_imperialWaist_convertsToCentimeters() {
        let value = BodyMeasurementInput.metricValue("34", for: .waist, unit: .imperial)
        XCTAssertEqual(value ?? 0, 86.36, accuracy: 0.001)
    }

    func test_metricValue_fahrenheit_convertsToCelsius() {
        let value = BodyMeasurementInput.metricValue("98.6", for: .bodyTemperature, unit: .imperial)
        XCTAssertEqual(value ?? 0, 37, accuracy: 0.001)
    }

    func test_metricValue_slippedDigit_isRejected() {
        XCTAssertNil(BodyMeasurementInput.metricValue("185", for: .bodyFat, unit: .metric))
        XCTAssertNil(BodyMeasurementInput.metricValue("8,6", for: .waist, unit: .metric))
    }

    func test_metricValue_notANumber_isRejected() {
        XCTAssertNil(BodyMeasurementInput.metricValue("abc", for: .waist, unit: .metric))
    }

    func test_metricValue_biomarkerNotTypedByHand_isRejected() {
        XCTAssertNil(BodyMeasurementInput.metricValue("60", for: .hrvBaseline, unit: .metric))
    }

    func test_bloodPressure_validPair_parses() {
        let reading = BodyMeasurementInput.bloodPressure(systolic: "120", diastolic: "80")
        XCTAssertEqual(reading?.systolic, 120)
        XCTAssertEqual(reading?.diastolic, 80)
    }

    func test_bloodPressure_swappedHalves_isRejected() {
        XCTAssertNil(BodyMeasurementInput.bloodPressure(systolic: "80", diastolic: "120"))
    }

    func test_bloodPressure_outOfRange_isRejected() {
        XCTAssertNil(BodyMeasurementInput.bloodPressure(systolic: "300", diastolic: "80"))
    }
}
