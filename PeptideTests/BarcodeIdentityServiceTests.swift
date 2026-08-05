import XCTest
@testable import Peptide

/// Behaviour of the non-food fallback: what a barcode is when Open Food
/// Facts has never heard of it.
///
/// Every test here goes through `MockURLProtocol`, which intercepts by
/// host — the same mechanism the service uses in production, since each
/// sibling catalogue lives on its own domain. That means these tests
/// exercise the real URL construction rather than a test-only seam.
final class BarcodeIdentityServiceTests: XCTestCase {

    private var session: URLSession!
    private var service: BarcodeIdentityService!

    private static let barcode = "3600542525558"

    override func setUp() async throws {
        try await super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        service = BarcodeIdentityService(session: session, userAgent: "PeptideTests/1.0")
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
        session = nil
        service = nil
        try await super.tearDown()
    }

    // MARK: - Hits

    func test_identify_returnsProductFromBeautyCatalogue() async throws {
        respond { host in
            host == BarcodeIdentity.Catalogue.beauty.rawValue
                ? Self.hit(name: "Elsève Total Repair 5", brand: "L'Oréal")
                : Self.miss()
        }

        let identity = await service.identify(barcode: Self.barcode)

        XCTAssertEqual(identity?.name, "Elsève Total Repair 5")
        XCTAssertEqual(identity?.brand, "L'Oréal")
        XCTAssertEqual(identity?.catalogue, .beauty)
        XCTAssertEqual(identity?.barcode, Self.barcode)
    }

    func test_identify_prefersGeneralCatalogue_whenSeveralAnswer() async throws {
        // A barcode listed in more than one catalogue should resolve to
        // the general one — it's the broadest description and the least
        // likely to be a stale duplicate of a more specific entry.
        respond { _ in Self.hit(name: "Some Article", brand: "Acme") }

        let identity = await service.identify(barcode: Self.barcode)

        XCTAssertEqual(identity?.catalogue, .products)
    }

    func test_identify_requestsTheBarcodeFromEveryCatalogue() async throws {
        let seen = HostRecorder()
        MockURLProtocol.handler = { request in
            seen.record(request.url?.host ?? "")
            XCTAssertTrue(
                request.url?.path.hasSuffix("/api/v2/product/\(Self.barcode).json") == true,
                "unexpected path \(request.url?.path ?? "nil")"
            )
            return Self.miss()
        }

        _ = await service.identify(barcode: Self.barcode)

        XCTAssertEqual(
            Set(seen.hosts),
            Set(BarcodeIdentity.Catalogue.allCases.map(\.rawValue))
        )
    }

    // MARK: - Misses

    func test_identify_returnsNil_whenNoCatalogueKnowsTheBarcode() async {
        respond { _ in Self.miss() }
        let identity = await service.identify(barcode: Self.barcode)
        XCTAssertNil(identity)
    }

    func test_identify_returnsNil_forMalformedBarcode() async {
        // Short-circuits before any network call — the handler is left
        // unset, so a request reaching it would fail the lookup anyway.
        let identity = await service.identify(barcode: "not-a-barcode")
        XCTAssertNil(identity)
    }

    func test_identify_returnsNil_whenProductNameIsBlank() async {
        // A record that exists but carries no usable name is worse than
        // no record: "we identified it: (nothing)" reads as a bug.
        respond { _ in Self.hit(name: "   ", brand: "Acme") }
        let identity = await service.identify(barcode: Self.barcode)
        XCTAssertNil(identity)
    }

    func test_identify_returnsNil_onServerError() async {
        respond { _ in
            (Self.response(status: 500), Data("{}".utf8))
        }
        let identity = await service.identify(barcode: Self.barcode)
        XCTAssertNil(identity)
    }

    func test_identify_returnsNil_onTransportFailure() async {
        // The whole point of this path is that it can never make the
        // not-found screen worse — a dead catalogue is a silent nil.
        MockURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        let identity = await service.identify(barcode: Self.barcode)
        XCTAssertNil(identity)
    }

    func test_identify_returnsNil_onUnparseablePayload() async {
        respond { _ in (Self.response(status: 200), Data("<html>nope</html>".utf8)) }
        let identity = await service.identify(barcode: Self.barcode)
        XCTAssertNil(identity)
    }

    // MARK: - Display title

    func test_displayTitle_joinsBrandAndName() {
        let identity = BarcodeIdentity(
            barcode: Self.barcode, name: "Total Repair 5", brand: "L'Oréal", catalogue: .beauty
        )
        XCTAssertEqual(identity.displayTitle, "L'Oréal Total Repair 5")
    }

    func test_displayTitle_doesNotRepeatBrandAlreadyInName() {
        let identity = BarcodeIdentity(
            barcode: Self.barcode, name: "L'Oréal Total Repair 5", brand: "L'Oréal", catalogue: .beauty
        )
        XCTAssertEqual(identity.displayTitle, "L'Oréal Total Repair 5")
    }

    func test_displayTitle_fallsBackToNameWithoutBrand() {
        let identity = BarcodeIdentity(
            barcode: Self.barcode, name: "Dog Chow", brand: nil, catalogue: .petFood
        )
        XCTAssertEqual(identity.displayTitle, "Dog Chow")
    }

    // MARK: - Catalogue policy

    func test_onlyTheGeneralCatalogueKeepsTheNutritionLabelFallback() {
        // Offering "scan the nutrition label" on a shampoo bottle is the
        // detail that tells a user the app didn't understand them.
        XCTAssertTrue(BarcodeIdentity.Catalogue.products.mayStillBeEdible)
        XCTAssertFalse(BarcodeIdentity.Catalogue.beauty.mayStillBeEdible)
        XCTAssertFalse(BarcodeIdentity.Catalogue.petFood.mayStillBeEdible)
    }

    func test_everyCatalogueExplainsWhyItIsNotLoggable() {
        for catalogue in BarcodeIdentity.Catalogue.allCases {
            XCTAssertFalse(catalogue.reasonNotLoggable.isEmpty, "\(catalogue) has no reason copy")
            XCTAssertFalse(catalogue.displayName.isEmpty, "\(catalogue) has no attribution")
            XCTAssertFalse(catalogue.icon.isEmpty, "\(catalogue) has no icon")
        }
    }

    // MARK: - Helpers

    /// Installs a handler that answers per requested host.
    private func respond(
        _ body: @escaping @Sendable (String) -> (HTTPURLResponse, Data)
    ) {
        MockURLProtocol.handler = { request in body(request.url?.host ?? "") }
    }

    private static func hit(name: String, brand: String) -> (HTTPURLResponse, Data) {
        let json = """
        {"status":1,"product":{"product_name":"\(name)","brands":"\(brand)"}}
        """
        return (response(status: 200), Data(json.utf8))
    }

    /// A miss still arrives as HTTP 200 with `status: 0` — that's the
    /// Open *Facts* convention, and treating it as a hit would surface
    /// an empty identification card.
    private static func miss() -> (HTTPURLResponse, Data) {
        (response(status: 200), Data(#"{"status":0}"#.utf8))
    }

    private static func response(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://world.openproductsfacts.org/api/v2/product/\(barcode).json")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}

/// The three catalogue lookups run concurrently on URLSession's loader
/// queue, so the hosts they request have to be collected under a lock.
private final class HostRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func record(_ host: String) {
        lock.lock(); defer { lock.unlock() }
        storage.append(host)
    }

    var hosts: [String] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
