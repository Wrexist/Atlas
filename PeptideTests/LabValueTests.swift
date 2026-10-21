import XCTest
@testable import Peptide

/// Forward-compat decoding and SI-unit conversion for lab values.
final class LabValueTests: XCTestCase {

    func test_decode_unknownPanel_mapsToOther() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":0,"panel":"futurePanel","value":4.2,"updatedAt":0}"#
        let value = try JSONDecoder().decode(LabValue.self, from: Data(json.utf8))
        XCTAssertEqual(value.panel, .other)
        XCTAssertEqual(value.value, 4.2)
    }

    func test_decode_knownPanel_roundTrips() throws {
        let original = LabValue(date: Date(timeIntervalSince1970: 0), panel: .hba1c, value: 5.4)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(LabValue.self, from: data), original)
    }

    func test_canonicalValue_hba1cMmolPerMol_convertsToPercent() {
        XCTAssertEqual(LabPanel.hba1c.canonicalValue(fromSI: 38), 5.627, accuracy: 0.01)
    }

    func test_canonicalValue_glucoseMmolPerL_convertsToMgPerDL() {
        XCTAssertEqual(LabPanel.fastingGlucose.canonicalValue(fromSI: 5.0), 90.08, accuracy: 0.1)
    }

    func test_canonicalValue_cholesterolMmolPerL_convertsToMgPerDL() {
        XCTAssertEqual(LabPanel.totalCholesterol.canonicalValue(fromSI: 5.2), 201.1, accuracy: 0.1)
    }

    func test_canonicalValue_testosteroneNmolPerL_convertsToNgPerDL() {
        XCTAssertEqual(LabPanel.totalTestosterone.canonicalValue(fromSI: 20), 576.8, accuracy: 0.1)
    }

    func test_panelWithoutSIAlternative_hasNoSIUnitAndPassesValueThrough() {
        XCTAssertNil(LabPanel.alt.siUnit)
        XCTAssertEqual(LabPanel.alt.canonicalValue(fromSI: 30), 30)
    }
}
