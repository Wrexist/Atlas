import XCTest
@testable import Peptide

final class ResearchLinkTests: XCTestCase {

    func test_resolvedURL_directURL_winsOverIdentifiers() {
        let link = ResearchLink(title: "T", source: "S", year: 2020, pmid: "123", doi: "10.1/x", url: "https://example.org/a")
        XCTAssertEqual(link.resolvedURL?.absoluteString, "https://example.org/a")
    }

    func test_resolvedURL_doiOnly_opensTheDOIResolver() {
        let link = ResearchLink(title: "T", source: "S", year: 2020, doi: "10.1016/S0140-6736(23)01084-X")
        XCTAssertEqual(link.resolvedURL?.host, "doi.org")
        XCTAssertTrue(link.resolvedURL?.absoluteString.hasSuffix("10.1016/S0140-6736(23)01084-X") ?? false)
    }

    func test_resolvedURL_pmidOnly_opensPubMed() {
        let link = ResearchLink(title: "T", source: "S", year: 2020, pmid: "12345678")
        XCTAssertEqual(link.resolvedURL?.absoluteString, "https://pubmed.ncbi.nlm.nih.gov/12345678/")
    }

    func test_resolvedURL_noIdentifiers_isNil() {
        XCTAssertNil(ResearchLink(title: "T", source: "S", year: 2020).resolvedURL)
    }

    func test_bundledDataset_everyCitationWithAnIdentifier_isTappable() {
        let unresolved = PeptideDatabase.shared
            .flatMap(\.researchLinks)
            .filter { !($0.url.isEmpty && $0.doi.isEmpty && $0.pmid.isEmpty) && $0.resolvedURL == nil }
        XCTAssertTrue(unresolved.isEmpty, "Citations with no resolvable link: \(unresolved.map(\.title))")
    }
}
