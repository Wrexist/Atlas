import XCTest
@testable import Peptide

final class PeptideSearchTests: XCTestCase {

    func test_matchesSearch_trailingSpace_stillMatches() {
        XCTAssertTrue(MockPeptides.bpc157.matchesSearch("bpc "))
    }

    func test_matchesSearch_ignoresCaseAndDiacritics() {
        XCTAssertTrue(MockPeptides.bpc157.matchesSearch("BPÇ"))
    }

    func test_matchesSearch_blankQuery_matchesEverything() {
        XCTAssertTrue(MockPeptides.bpc157.matchesSearch("  \n"))
    }

    func test_matchesSearch_unrelatedQuery_doesNotMatch() {
        XCTAssertFalse(MockPeptides.bpc157.matchesSearch("zzzz"))
    }
}
