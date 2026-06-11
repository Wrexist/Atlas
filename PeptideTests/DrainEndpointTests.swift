import XCTest
@testable import Peptide

/// Pins the scheme + host policy that gates every PII drain. A
/// regression here means a tampered Info.plist could exfiltrate
/// affiliate applications or funnel snapshots to an arbitrary
/// collector, so each rejection case is pinned individually.
final class DrainEndpointTests: XCTestCase {

    func test_validated_allowsAtlasDomains() {
        XCTAssertNotNil(DrainEndpoint.validated("https://peptidesai.com/intake"))
        XCTAssertNotNil(DrainEndpoint.validated("https://api.peptidesai.com/intake"))
        XCTAssertNotNil(DrainEndpoint.validated("https://peptidex.site/funnel"))
        XCTAssertNotNil(DrainEndpoint.validated("https://drain.peptidex.site/funnel"))
    }

    func test_validated_isCaseInsensitiveOnSchemeAndHost() {
        XCTAssertNotNil(DrainEndpoint.validated("HTTPS://API.PEPTIDESAI.COM/intake"))
    }

    func test_validated_rejectsForeignHosts() {
        XCTAssertNil(DrainEndpoint.validated("https://attacker.example/collect"))
        XCTAssertNil(DrainEndpoint.validated("https://peptidesai.com.attacker.example/collect"))
    }

    func test_validated_rejectsSuffixSpoof() {
        // Host merely *ending* in the domain string must not match —
        // only an exact host or a true subdomain.
        XCTAssertNil(DrainEndpoint.validated("https://evilpeptidesai.com/collect"))
        XCTAssertNil(DrainEndpoint.validated("https://notpeptidex.site/collect"))
    }

    func test_validated_rejectsNonHTTPSSchemes() {
        XCTAssertNil(DrainEndpoint.validated("http://peptidesai.com/intake"))
        XCTAssertNil(DrainEndpoint.validated("ftp://peptidesai.com/intake"))
    }

    func test_validated_rejectsMissingOrEmpty() {
        XCTAssertNil(DrainEndpoint.validated(nil))
        XCTAssertNil(DrainEndpoint.validated(""))
        XCTAssertNil(DrainEndpoint.validated("not a url"))
    }
}
