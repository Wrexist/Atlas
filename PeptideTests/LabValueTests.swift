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
}
