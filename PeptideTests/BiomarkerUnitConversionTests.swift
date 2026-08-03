import XCTest
@testable import Peptide

/// Regression cover for the imperial-units ship-blocker: the conversion
/// helpers existed but nothing in the render path called them, so a US user
/// saw the kilogram number labelled "kg". The trap when wiring that up is
/// temperature — °C→°F has an *offset*, so a delta must be computed from two
/// converted values, never by converting the delta.
@MainActor
final class BiomarkerUnitConversionTests: XCTestCase {

    // MARK: - Labels

    func test_displayUnit_swapsOnlyTheUnitsThatDiffer() {
        XCTAssertEqual(Biomarker.weight.displayUnit(for: .metric), "kg")
        XCTAssertEqual(Biomarker.weight.displayUnit(for: .imperial), "lb")
        XCTAssertEqual(Biomarker.waist.displayUnit(for: .metric), "cm")
        XCTAssertEqual(Biomarker.waist.displayUnit(for: .imperial), "in")
        XCTAssertEqual(Biomarker.bodyTemperature.displayUnit(for: .metric), "°C")
        XCTAssertEqual(Biomarker.bodyTemperature.displayUnit(for: .imperial), "°F")
    }

    /// HRV, resting heart rate, sleep and steps are the same number in both
    /// systems — relabelling them would be actively wrong.
    func test_displayUnit_unitAgnosticBiomarkersDoNotChange() {
        for biomarker in [Biomarker.hrvBaseline, .rhrBaseline, .sleepBaseline, .stepsBaseline, .bodyFat] {
            XCTAssertEqual(
                biomarker.displayUnit(for: .metric),
                biomarker.displayUnit(for: .imperial),
                "\(biomarker) should read identically in both unit systems"
            )
        }
    }

    // MARK: - Values

    func test_displayValue_metricPassesThroughUnchanged() {
        XCTAssertEqual(Biomarker.weight.displayValue(80, for: .metric), 80)
        XCTAssertEqual(Biomarker.waist.displayValue(86, for: .metric), 86)
        XCTAssertEqual(Biomarker.bodyTemperature.displayValue(36.6, for: .metric), 36.6)
    }

    func test_displayValue_convertsWeightWaistAndTemperature() {
        XCTAssertEqual(Biomarker.weight.displayValue(80, for: .imperial), 176.37, accuracy: 0.01)
        XCTAssertEqual(Biomarker.waist.displayValue(86, for: .imperial), 33.86, accuracy: 0.01)
        XCTAssertEqual(Biomarker.bodyTemperature.displayValue(37, for: .imperial), 98.6, accuracy: 0.01)
    }

    func test_displayValue_leavesUnitAgnosticBiomarkersAlone() {
        for biomarker in [Biomarker.hrvBaseline, .rhrBaseline, .sleepBaseline, .stepsBaseline, .bodyFat] {
            XCTAssertEqual(biomarker.displayValue(58, for: .imperial), 58)
        }
    }

    // MARK: - Deltas

    /// A 1 °C rise is a 1.8 °F rise, not 33.8. Subtracting two already-
    /// converted values is what makes that come out right; converting the
    /// delta itself would drag the +32 offset in.
    func test_temperatureDelta_scalesWithoutCarryingTheOffset() {
        let latest = Biomarker.bodyTemperature.displayValue(37.0, for: .imperial)
        let previous = Biomarker.bodyTemperature.displayValue(36.0, for: .imperial)
        XCTAssertEqual(latest - previous, 1.8, accuracy: 0.001)
    }

    func test_weightDelta_scalesLinearly() {
        let latest = Biomarker.weight.displayValue(81, for: .imperial)
        let previous = Biomarker.weight.displayValue(80, for: .imperial)
        XCTAssertEqual(latest - previous, 2.20462, accuracy: 0.0001)
    }

    // MARK: - Rendered copy

    func test_changeText_rendersTheUsersUnitNotTheStoredOne() {
        let imperial = BiomarkerSeriesService.changeText(
            for: .weight, trend: BiomarkerSnapshot.Trend.flat, latest: 80, unit: .imperial
        )
        XCTAssertTrue(imperial.contains("lb"), imperial)
        XCTAssertFalse(imperial.contains("kg"), imperial)
        XCTAssertTrue(imperial.contains("176"), imperial)

        let metric = BiomarkerSeriesService.changeText(
            for: .weight, trend: BiomarkerSnapshot.Trend.flat, latest: 80, unit: .metric
        )
        XCTAssertTrue(metric.contains("kg"), metric)
        XCTAssertTrue(metric.contains("80"), metric)
    }
}
