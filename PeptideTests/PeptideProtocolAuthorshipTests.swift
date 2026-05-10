import XCTest
@testable import Peptide

@MainActor
final class PeptideProtocolAuthorshipTests: XCTestCase {

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func testEncodeDecodeRoundTripPreservesAuthorship() throws {
        let original = PeptideProtocol(
            id: UUID(),
            name: "Roundtrip",
            peptides: [],
            schedule: ProtocolSchedule(daysOfWeek: [1, 2, 3], timesPerDay: 1, preferredTimes: ["8:00 AM"]),
            cycleLengthWeeks: 8,
            startDate: Date(),
            status: .active,
            notes: "",
            authorName: "Dr. Test",
            authorHandle: "@test.handle",
            forkedFromStackId: UUID(),
            createdAt: Date()
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PeptideProtocol.self, from: data)

        XCTAssertEqual(decoded.authorName, original.authorName)
        XCTAssertEqual(decoded.authorHandle, original.authorHandle)
        XCTAssertEqual(decoded.forkedFromStackId, original.forkedFromStackId)
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970,
                       original.createdAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testLegacyProtocolWithoutAuthorshipDecodes() throws {
        let id = UUID().uuidString
        let date = ISO8601DateFormatter().string(from: Date())
        let legacyJSON = """
        {
            "id": "\(id)",
            "name": "Legacy Stack",
            "peptides": [],
            "schedule": {
                "daysOfWeek": [1, 2, 3],
                "timesPerDay": 1,
                "preferredTimes": ["8:00 AM"]
            },
            "cycleLengthWeeks": 8,
            "startDate": "\(date)",
            "status": "active",
            "notes": ""
        }
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let decoded = try decoder.decode(PeptideProtocol.self, from: data)

        XCTAssertEqual(decoded.name, "Legacy Stack")
        XCTAssertNil(decoded.authorName)
        XCTAssertNil(decoded.authorHandle)
        XCTAssertNil(decoded.forkedFromStackId)
        // createdAt defaults to "now" when absent — just confirm it's a sane timestamp.
        XCTAssertGreaterThan(decoded.createdAt.timeIntervalSince1970, 0)
    }
}
