import XCTest
@testable import Peptide

/// Pins how Siri's spoken peptide names resolve to an entity.
final class PeptideEntityQueryTests: XCTestCase {

    private let bpc = PeptideEntity(id: UUID().uuidString, displayName: "BPC-157", abbreviation: "BPC-157")
    private let tb = PeptideEntity(id: UUID().uuidString, displayName: "TB-500", abbreviation: "TB4")

    func test_spokenVariants_resolveToTheHyphenatedName() {
        for spoken in ["bpc 157", "BPC157", "bpc-157", "Bpc"] {
            XCTAssertTrue(PeptideEntityQuery.matches(bpc, query: spoken), spoken)
        }
    }

    func test_otherPeptide_doesNotMatch() {
        XCTAssertFalse(PeptideEntityQuery.matches(tb, query: "bpc 157"))
    }

    func test_abbreviation_matches() {
        XCTAssertTrue(PeptideEntityQuery.matches(tb, query: "tb 4"))
    }

    func test_emptyQuery_matchesNothing() {
        XCTAssertFalse(PeptideEntityQuery.matches(bpc, query: " - "))
    }
}
