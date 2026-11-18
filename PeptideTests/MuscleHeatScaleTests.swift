import XCTest
@testable import Peptide

/// The heat legend and the figure have to agree on how strongly each
/// intensity is drawn, or the legend shows colours no muscle gets.
@MainActor
final class MuscleHeatScaleTests: XCTestCase {

    func test_heatStrength_rampEnds_matchFaintWashAndFullTint() {
        XCTAssertEqual(MuscleMapView.heatStrength(for: 0), 0.3, accuracy: 0.0001)
        XCTAssertEqual(MuscleMapView.heatStrength(for: 1), 1.0, accuracy: 0.0001)
    }

    func test_heatStrength_outOfRangeIntensity_clampsToRampEnds() {
        XCTAssertEqual(MuscleMapView.heatStrength(for: -0.5), 0.3, accuracy: 0.0001)
        XCTAssertEqual(MuscleMapView.heatStrength(for: 2), 1.0, accuracy: 0.0001)
    }

    func test_heatStrength_midIntensity_isLinear() {
        XCTAssertEqual(MuscleMapView.heatStrength(for: 0.5), 0.65, accuracy: 0.0001)
    }
}
