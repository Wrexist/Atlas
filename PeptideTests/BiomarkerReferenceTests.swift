import XCTest
@testable import Peptide

final class BiomarkerReferenceTests: XCTestCase {

    /// Every charted row explains itself with a source; lab results point
    /// to Labs instead.
    func test_reference_everyChartedBiomarkerHasHTTPSSource() {
        for biomarker in Biomarker.allCases where biomarker != .latestLabPanel {
            let reference = biomarker.reference
            XCTAssertEqual(reference?.url.scheme, "https", "\(biomarker) needs a Learn more link")
            XCTAssertFalse(reference?.publisher.isEmpty ?? true)
        }
        XCTAssertNil(Biomarker.latestLabPanel.reference)
    }
}
