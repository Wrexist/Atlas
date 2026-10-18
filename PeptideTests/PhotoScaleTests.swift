import XCTest
@testable import Peptide

/// The LiDAR scale handed to the scanner: a robust distance and the
/// photo's real size at that distance.
final class PhotoScaleTests: XCTestCase {

    func test_medianDistance_ignoresOutOfRangeAndNoise() {
        let depths: [Float] = Array(repeating: 0.4, count: 30) + [0.05, 3.5, .nan, .infinity] + Array(repeating: 0.45, count: 10)
        XCTAssertEqual(PhotoScale.medianDistance(depths) ?? 0, 0.4, accuracy: 0.001)
    }

    func test_medianDistance_needsEnoughReadings() {
        XCTAssertNil(PhotoScale.medianDistance(Array(repeating: 0.4, count: 19)))
    }

    func test_photoSpan_followsDistanceAndFieldOfView() {
        // 90° across the long edge at 40 cm: 2 × 40 × tan(45°) = 80 cm.
        let scale = PhotoScale(distanceMeters: 0.4, longEdgeFOVDegrees: 90, aspect: 0.75)
        XCTAssertEqual(scale.longEdgeCm, 80, accuracy: 0.01)
        XCTAssertEqual(scale.shortEdgeCm, 60, accuracy: 0.01)
        XCTAssertTrue(scale.hint.contains("about 40 cm"))
        XCTAssertTrue(scale.hint.contains("80 × 60 cm"))
    }
}
