import XCTest
@testable import Peptide

final class OpenFoodFactsServiceTests: XCTestCase {

    private var tempDir: URL!
    private var cache: BarcodeProductCache!
    private var session: URLSession!
    private var service: OpenFoodFactsService!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OFFServiceTests-\(UUID().uuidString)", isDirectory: true)
        cache = BarcodeProductCache(directory: tempDir, ttl: 60 * 60)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)

        service = OpenFoodFactsService(
            session: session,
            cache: cache,
            baseURL: URL(string: "https://openfoodfacts.test/api/v2/product/")!,
            userAgent: "PeptideTests/1.0"
        )
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        cache = nil
        session = nil
        service = nil
        try await super.tearDown()
    }

    // MARK: - normalize

    func test_normalize_acceptsValidThirteenDigitBarcode() throws {
        XCTAssertEqual(try OpenFoodFactsService.normalize(barcode: "5449000000996"), "5449000000996")
    }

    func test_normalize_acceptsValidEightDigitBarcode() throws {
        XCTAssertEqual(try OpenFoodFactsService.normalize(barcode: "12345678"), "12345678")
    }

    func test_normalize_trimsWhitespace() throws {
        XCTAssertEqual(try OpenFoodFactsService.normalize(barcode: "  5449000000996\n"), "5449000000996")
    }

    func test_normalize_rejectsTooShort() {
        XCTAssertThrowsError(try OpenFoodFactsService.normalize(barcode: "1234567"))
    }

    func test_normalize_rejectsTooLong() {
        XCTAssertThrowsError(try OpenFoodFactsService.normalize(barcode: "123456789012345"))
    }

    func test_normalize_rejectsNonNumeric() {
        XCTAssertThrowsError(try OpenFoodFactsService.normalize(barcode: "ABC12345"))
    }

    // MARK: - fetch: success

    func test_fetch_decodesFullProductResponse() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.cocaCola.utf8))
        }
        let product = try await service.fetch(barcode: "5449000000996")
        XCTAssertEqual(product.barcode, "5449000000996")
        XCTAssertEqual(product.name, "Coca-Cola")
        XCTAssertEqual(product.brand, "Coca-Cola")
        XCTAssertEqual(product.servingGrams, 330)
        XCTAssertEqual(product.packageGrams, 330)
        XCTAssertEqual(product.per100g.calories, 42, accuracy: 0.01)
        XCTAssertEqual(product.per100g.carbsG, 10.6, accuracy: 0.01)
        XCTAssertEqual(product.nutriScore, "e")
        XCTAssertEqual(product.novaGroup, 4)
    }

    func test_fetch_fillsNameFromBrand_whenProductNameMissing() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.brandOnly.utf8))
        }
        let product = try await service.fetch(barcode: "1111111111111")
        XCTAssertEqual(product.name, "Generic Brand")
    }

    func test_fetch_fallsBackToUnknown_whenNameAndBrandMissing() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.nameless.utf8))
        }
        let product = try await service.fetch(barcode: "1111111111111")
        XCTAssertEqual(product.name, "Unknown product")
    }

    func test_fetch_decodesNumericFieldsServedAsStrings() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.stringyNumerics.utf8))
        }
        let product = try await service.fetch(barcode: "2222222222222")
        XCTAssertEqual(product.servingGrams, 250)
        XCTAssertEqual(product.per100g.calories, 88, accuracy: 0.01)
        // Exercises FlexibleInt's string branch — nova_group arrives as "3".
        XCTAssertEqual(product.novaGroup, 3)
    }

    func test_fetch_unreadableNumericStrings_stillReturnsProduct() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.unreadableNumerics.utf8))
        }
        let product = try await service.fetch(barcode: "9999999999999")
        XCTAssertEqual(product.name, "Messy record")
        XCTAssertNil(product.servingGrams)
        XCTAssertNil(product.novaGroup)
        XCTAssertEqual(product.per100g.fatG, 0)
        XCTAssertEqual(product.per100g.carbsG, 0, "a \"nan\" string is missing, not NaN")
        XCTAssertEqual(product.per100g.proteinG, 1.5, accuracy: 0.001)
        XCTAssertEqual(product.per100g.calories, 120, accuracy: 0.001)
    }

    func test_search_oneUnreadableProduct_keepsTheRestOfThePage() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.searchWithBadFat.utf8))
        }
        let results = try await service.search(query: "lenient-decode-\(UUID().uuidString)")
        XCTAssertEqual(results.map(\.name), ["Good oats", "Odd oats"])
        XCTAssertEqual(results.last?.per100g.fatG, 0)
    }

    // MARK: - fetch: OFF data quirks

    func test_fetch_fallsBackToKilojoules_whenKcalAbsent() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.kilojoulesOnly.utf8))
        }
        let product = try await service.fetch(barcode: "4444444444444")
        // 1000 kJ / 4.184 = 239.0… kcal/100g
        XCTAssertEqual(product.per100g.calories, 239, accuracy: 0.5)
    }

    func test_fetch_energyUnitKcal_stillConvertsNormalisedKilojoules() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.kilojoulesTypedAsKcal.utf8))
        }
        let product = try await service.fetch(barcode: "6666666666666")
        // energy_100g is kJ even when the contributor typed kcal.
        XCTAssertEqual(product.per100g.calories, 239, accuracy: 0.5)
    }

    func test_fetch_treatsZeroServingQuantityAsMissing() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.zeroServingQuantity.utf8))
        }
        let product = try await service.fetch(barcode: "5555555555555")
        // serving_quantity: 0 must collapse to nil so defaultPortion
        // skips .servings(1) (which would grey out the Add button).
        XCTAssertNil(product.servingGrams)
        XCTAssertNotEqual(product.defaultPortion, .servings(1))
    }

    func test_fetch_zerosOutMissingMacros() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.sparseNutriments.utf8))
        }
        let product = try await service.fetch(barcode: "3333333333333")
        XCTAssertEqual(product.per100g.calories, 100, accuracy: 0.01)
        XCTAssertEqual(product.per100g.proteinG, 0)
        XCTAssertEqual(product.per100g.carbsG, 0)
        XCTAssertEqual(product.per100g.fatG, 0)
    }

    func test_fetch_allZeroNutriments_countsAsHavingNutrition() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.water.utf8))
        }
        let product = try await service.fetch(barcode: "7777777777777")
        XCTAssertTrue(product.hasNutrition)
    }

    func test_fetch_noNutriments_hasNoNutrition() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.noNutriments.utf8))
        }
        let product = try await service.fetch(barcode: "8888888888888")
        XCTAssertFalse(product.hasNutrition)
    }

    func test_fetch_nonFiniteOrHugeNutriments_areDroppedAsMissing() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.malformedNutriments.utf8))
        }
        let product = try await service.fetch(barcode: "9999999999999")
        XCTAssertEqual(product.per100g.calories, 0)
        XCTAssertEqual(product.per100g.proteinG, 0)
        XCTAssertEqual(product.per100g.carbsG, 12)
        XCTAssertEqual(product.per100g.fatG, 0)
        XCTAssertNil(product.per100g.fiberG)
        XCTAssertNil(product.novaGroup)
        XCTAssertTrue(product.hasNutrition)
    }

    func test_fetch_onlyMalformedNutriments_hasNoNutrition() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.onlyMalformedNutriments.utf8))
        }
        let product = try await service.fetch(barcode: "9999999999998")
        XCTAssertFalse(product.hasNutrition)
    }

    func test_fetch_addsUserAgentHeader() async throws {
        let captured: SendableBox<URLRequest?> = .init(nil)
        MockURLProtocol.handler = { request in
            captured.set(request)
            return (Self.ok(for: request), Data(Fixtures.cocaCola.utf8))
        }
        _ = try await service.fetch(barcode: "5449000000996")
        XCTAssertEqual(captured.value?.value(forHTTPHeaderField: "User-Agent"), "PeptideTests/1.0")
    }

    func test_fetch_requestsTrimmedFieldsParameter() async throws {
        let captured: SendableBox<URLRequest?> = .init(nil)
        MockURLProtocol.handler = { request in
            captured.set(request)
            return (Self.ok(for: request), Data(Fixtures.cocaCola.utf8))
        }
        _ = try await service.fetch(barcode: "5449000000996")
        let query = captured.value?.url?.query ?? ""
        XCTAssertTrue(query.contains("fields="), "Expected fields= query parameter, got: \(query)")
        XCTAssertTrue(query.contains("nutriments"))
    }

    // MARK: - fetch: failure modes

    func test_fetch_throwsNotFound_whenStatusZero() async {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.notFound.utf8))
        }
        await XCTAssertThrowsErrorAsync(try await service.fetch(barcode: "5449000000996")) { error in
            XCTAssertEqual(error as? OpenFoodFactsService.LookupError, .notFound)
        }
    }

    func test_fetch_throwsNotFound_on404() async {
        MockURLProtocol.handler = { request in
            (Self.response(for: request, status: 404), Data())
        }
        await XCTAssertThrowsErrorAsync(try await service.fetch(barcode: "5449000000996")) { error in
            XCTAssertEqual(error as? OpenFoodFactsService.LookupError, .notFound)
        }
    }

    func test_fetch_throwsRateLimited_on429() async {
        MockURLProtocol.handler = { request in
            (Self.response(for: request, status: 429), Data())
        }
        await XCTAssertThrowsErrorAsync(try await service.fetch(barcode: "5449000000996")) { error in
            XCTAssertEqual(error as? OpenFoodFactsService.LookupError, .rateLimited)
        }
    }

    func test_fetch_throwsRequestFailed_onOther5xx() async {
        MockURLProtocol.handler = { request in
            (Self.response(for: request, status: 500), Data())
        }
        await XCTAssertThrowsErrorAsync(try await service.fetch(barcode: "5449000000996")) { error in
            guard case .requestFailed(let status)? = error as? OpenFoodFactsService.LookupError else {
                XCTFail("Expected requestFailed, got \(error)")
                return
            }
            XCTAssertEqual(status, 500)
        }
    }

    /// Repeated 502s must surface `.serviceUnavailable` rather than the
    /// raw `requestFailed(502)` — the UI uses the distinct case to
    /// steer the user toward the photo fallback. The fact that the
    /// case changes from `.requestFailed(502)` to `.serviceUnavailable`
    /// implicitly proves the retry loop ran (a single-attempt path
    /// would surface `.requestFailed(502)` on the first failure).
    func test_fetch_throwsServiceUnavailable_afterRepeated502() async {
        let counter = AttemptCounter()
        MockURLProtocol.handler = { request in
            counter.bump()
            return (Self.response(for: request, status: 502), Data())
        }
        await XCTAssertThrowsErrorAsync(try await service.fetch(barcode: "5449000000996")) { error in
            XCTAssertEqual(error as? OpenFoodFactsService.LookupError, .serviceUnavailable)
        }
        XCTAssertGreaterThanOrEqual(counter.value, 2, "Expected at least one retry after the first 502")
    }

    /// A 502 followed by a 200 must succeed — proves the retry loop
    /// keeps the user out of the error path when OFF self-recovers.
    func test_fetch_recoversFromTransient502() async throws {
        let counter = AttemptCounter()
        MockURLProtocol.handler = { request in
            let attemptIndex = counter.bump()
            if attemptIndex == 0 {
                return (Self.response(for: request, status: 502), Data())
            }
            return (Self.ok(for: request), Data(Fixtures.cocaCola.utf8))
        }
        let product = try await service.fetch(barcode: "5449000000996")
        XCTAssertEqual(product.name, "Coca-Cola")
    }

    func test_search_timeout_retriesAndReportsServiceUnavailable() async {
        // A slow OFF isn't the user being offline.
        let counter = AttemptCounter()
        MockURLProtocol.handler = { _ in
            counter.bump()
            throw URLError(.timedOut)
        }
        await XCTAssertThrowsErrorAsync(try await service.search(query: "oats")) { error in
            XCTAssertEqual(error as? OpenFoodFactsService.LookupError, .serviceUnavailable)
        }
        XCTAssertGreaterThanOrEqual(counter.value, 2)
    }

    func test_search_noConnection_reportsNetworkUnavailable() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await XCTAssertThrowsErrorAsync(try await service.search(query: "oats")) { error in
            XCTAssertEqual(error as? OpenFoodFactsService.LookupError, .networkUnavailable)
        }
    }

    func test_fetch_throwsInvalidBarcode_whenBarcodeIsGarbage() async {
        await XCTAssertThrowsErrorAsync(try await service.fetch(barcode: "not-a-barcode")) { error in
            XCTAssertEqual(error as? OpenFoodFactsService.LookupError, .invalidBarcode)
        }
    }

    // MARK: - Cache integration

    func test_fetch_writesThroughToCache() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.cocaCola.utf8))
        }
        _ = try await service.fetch(barcode: "5449000000996")
        let cached = await cache.read(barcode: "5449000000996")
        XCTAssertEqual(cached?.name, "Coca-Cola")
    }

    func test_fetch_returnsCachedEntry_withoutNetwork() async throws {
        let cached = ScannedProduct(
            barcode: "5449000000996",
            name: "Cached Cola",
            brand: nil, imageURL: nil,
            servingSizeText: nil, servingGrams: nil, packageGrams: 330,
            per100g: .init(calories: 1, proteinG: 0, carbsG: 0, fatG: 0, fiberG: nil, sugarsG: nil),
            nutriScore: nil, novaGroup: nil,
            fetchedAt: Date()
        )
        await cache.write(cached)

        let callCount = SendableBox<Int>(0)
        MockURLProtocol.handler = { request in
            callCount.set(callCount.value + 1)
            return (Self.ok(for: request), Data(Fixtures.cocaCola.utf8))
        }

        let result = try await service.fetch(barcode: "5449000000996")
        XCTAssertEqual(result.name, "Cached Cola")
        XCTAssertEqual(callCount.value, 0, "Cache hit must not touch network")
    }

    func test_remember_packageReadProduct_isServedOnRescanWithoutNetwork() async throws {
        var read = ScannedProduct(
            barcode: "7394376616228", name: "Barista", brand: "Oatly", imageURL: nil,
            servingSizeText: nil, servingGrams: 250, packageGrams: 1000,
            per100g: .init(calories: 59, proteinG: 1, carbsG: 6.6, fatG: 3, fiberG: nil, sugarsG: nil),
            nutriScore: nil, novaGroup: nil, fetchedAt: Date()
        )
        read.readFromPackage = true
        let callCount = SendableBox<Int>(0)
        MockURLProtocol.handler = { request in
            callCount.set(callCount.value + 1)
            return (Self.ok(for: request), Data(Fixtures.notFound.utf8))
        }

        await service.remember(read)
        let rescanned = try await service.fetch(barcode: "7394376616228")

        XCTAssertEqual(rescanned.name, "Barista")
        XCTAssertEqual(rescanned.readFromPackage, true)
        XCTAssertEqual(callCount.value, 0)
    }

    func test_remember_syntheticBarcode_isNotCached() async {
        let read = ScannedProduct(
            barcode: "ai:\(UUID().uuidString)", name: "Unlabelled bar", brand: nil, imageURL: nil,
            servingSizeText: nil, servingGrams: nil, packageGrams: nil,
            per100g: .zero, nutriScore: nil, novaGroup: nil, fetchedAt: Date()
        )
        await service.remember(read)
        let recent = await cache.recent(limit: 5)
        XCTAssertTrue(recent.isEmpty)
    }

    // MARK: - Package weight from printed quantity

    func test_packageGrams_readsPlainWeight() {
        XCTAssertEqual(OpenFoodFactsService.packageGrams(fromQuantity: "130 g"), 130)
        XCTAssertEqual(OpenFoodFactsService.packageGrams(fromQuantity: "130g ℮"), 130)
    }

    func test_packageGrams_convertsKilogramsAndLitres() {
        XCTAssertEqual(OpenFoodFactsService.packageGrams(fromQuantity: "0,5 kg"), 500)
        XCTAssertEqual(OpenFoodFactsService.packageGrams(fromQuantity: "33 cl"), 330)
        XCTAssertEqual(OpenFoodFactsService.packageGrams(fromQuantity: "1.5 L"), 1500)
    }

    func test_packageGrams_multipliesMultipacks() {
        XCTAssertEqual(OpenFoodFactsService.packageGrams(fromQuantity: "6 x 33 cl"), 1980)
    }

    func test_packageGrams_returnsNil_whenNoUnit() {
        XCTAssertNil(OpenFoodFactsService.packageGrams(fromQuantity: "1 bag"))
        XCTAssertNil(OpenFoodFactsService.packageGrams(fromQuantity: ""))
    }

    func test_fetch_fallsBackToPrintedQuantity_whenProductQuantityMissing() async throws {
        let body = #"{"status":1,"product":{"product_name":"Ferrari Hallon","quantity":"130 g","serving_quantity":5.6,"nutriments":{"energy-kcal_100g":340}}}"#
        MockURLProtocol.handler = { request in (Self.ok(for: request), Data(body.utf8)) }
        let product = try await service.fetch(barcode: "5449000000996")
        XCTAssertEqual(product.packageGrams, 130)
        XCTAssertEqual(product.servingGrams, 5.6)
    }

    // MARK: - Stale-while-revalidate

    func test_fetch_returnsStaleCachedEntry_andRefreshesInBackground() async throws {
        // Write a cached entry whose fetchedAt is well past the
        // staleAfter threshold so the SWR branch trips.
        let stale = ScannedProduct(
            barcode: "5449000000996",
            name: "Stale Cola",
            brand: nil, imageURL: nil,
            servingSizeText: nil, servingGrams: nil, packageGrams: nil,
            per100g: .init(calories: 1, proteinG: 0, carbsG: 0, fatG: 0, fiberG: nil, sugarsG: nil),
            nutriScore: nil, novaGroup: nil,
            fetchedAt: Date().addingTimeInterval(-OpenFoodFactsService.staleAfter - 60)
        )
        await cache.write(stale)

        let callCount = SendableBox<Int>(0)
        MockURLProtocol.handler = { request in
            callCount.set(callCount.value + 1)
            return (Self.ok(for: request), Data(Fixtures.cocaCola.utf8))
        }

        let result = try await service.fetch(barcode: "5449000000996")
        XCTAssertEqual(result.name, "Stale Cola", "Foreground call must return the stale cached entry instantly")

        // Poll for the background refresh rather than sleeping a fixed
        // time — a shared CI runner can blow well past any fixed budget.
        let deadline = Date().addingTimeInterval(10)
        var refreshed = await cache.read(barcode: "5449000000996")
        while refreshed?.name != "Coca-Cola", Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
            refreshed = await cache.read(barcode: "5449000000996")
        }
        XCTAssertEqual(callCount.value, 1, "Stale hit should trigger exactly one background refresh")
        XCTAssertEqual(refreshed?.name, "Coca-Cola", "Background refresh must overwrite the cached entry")
    }

    func test_needsPackageWeightRefresh_freshEntryWithoutWeight_isFalse() {
        let fresh = ScannedProduct(
            barcode: "1", name: "x", brand: nil, imageURL: nil,
            servingSizeText: nil, servingGrams: nil, packageGrams: nil,
            per100g: .zero, nutriScore: nil, novaGroup: nil,
            fetchedAt: Date()
        )
        XCTAssertFalse(OpenFoodFactsService.needsPackageWeightRefresh(fresh))
    }

    func test_needsPackageWeightRefresh_dayOldEntryWithoutWeight_isTrue() {
        let old = ScannedProduct(
            barcode: "1", name: "x", brand: nil, imageURL: nil,
            servingSizeText: nil, servingGrams: nil, packageGrams: nil,
            per100g: .zero, nutriScore: nil, novaGroup: nil,
            fetchedAt: Date().addingTimeInterval(-OpenFoodFactsService.missingPackageRefreshAfter - 1)
        )
        XCTAssertTrue(OpenFoodFactsService.needsPackageWeightRefresh(old))
    }

    func test_fetch_freshCachedEntryWithoutWeight_doesNotRefetch() async throws {
        await cache.write(ScannedProduct(
            barcode: "5449000000996", name: "Cached Cola", brand: nil, imageURL: nil,
            servingSizeText: nil, servingGrams: nil, packageGrams: nil,
            per100g: .zero, nutriScore: nil, novaGroup: nil, fetchedAt: Date()
        ))
        let callCount = SendableBox<Int>(0)
        MockURLProtocol.handler = { request in
            callCount.set(callCount.value + 1)
            return (Self.ok(for: request), Data(Fixtures.cocaCola.utf8))
        }

        _ = try await service.fetch(barcode: "5449000000996")
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(callCount.value, 0)
    }

    func test_isStale_returnsFalse_forFreshFetchedAt() {
        let fresh = ScannedProduct(
            barcode: "1", name: "x", brand: nil, imageURL: nil,
            servingSizeText: nil, servingGrams: nil, packageGrams: nil,
            per100g: .zero, nutriScore: nil, novaGroup: nil,
            fetchedAt: Date()
        )
        XCTAssertFalse(OpenFoodFactsService.isStale(fresh))
    }

    func test_isStale_returnsTrue_pastTheStaleThreshold() {
        let old = ScannedProduct(
            barcode: "1", name: "x", brand: nil, imageURL: nil,
            servingSizeText: nil, servingGrams: nil, packageGrams: nil,
            per100g: .zero, nutriScore: nil, novaGroup: nil,
            fetchedAt: Date().addingTimeInterval(-OpenFoodFactsService.staleAfter - 1)
        )
        XCTAssertTrue(OpenFoodFactsService.isStale(old))
    }

    // MARK: - recent()

    func test_recent_returnsCacheEntries_withoutNetwork() async throws {
        let callCount = SendableBox<Int>(0)
        MockURLProtocol.handler = { request in
            callCount.set(callCount.value + 1)
            return (Self.ok(for: request), Data(Fixtures.cocaCola.utf8))
        }

        let coke = ScannedProduct(
            barcode: "5449000000996",
            name: "Coca-Cola", brand: nil, imageURL: nil,
            servingSizeText: nil, servingGrams: nil, packageGrams: nil,
            per100g: .zero, nutriScore: nil, novaGroup: nil,
            fetchedAt: Date()
        )
        await cache.write(coke)

        let recent = await service.recent(limit: 5)
        XCTAssertEqual(recent.map(\.barcode), ["5449000000996"])
        XCTAssertEqual(callCount.value, 0)
    }

    // MARK: - Helpers

    private static func ok(for request: URLRequest) -> HTTPURLResponse {
        response(for: request, status: 200)
    }

    private static func response(for request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }
}

// MARK: - Fixtures

private enum Fixtures {

    static let cocaCola = """
    {
      "status": 1,
      "code": "5449000000996",
      "product": {
        "product_name": "Coca-Cola",
        "brands": "Coca-Cola",
        "image_front_small_url": "https://example.com/coke.jpg",
        "serving_size": "330 ml",
        "serving_quantity": 330,
        "product_quantity": 330,
        "nutriscore_grade": "e",
        "nova_group": 4,
        "nutriments": {
          "energy-kcal_100g": 42,
          "proteins_100g": 0,
          "carbohydrates_100g": 10.6,
          "fat_100g": 0,
          "fiber_100g": 0,
          "sugars_100g": 10.6
        }
      }
    }
    """

    static let brandOnly = """
    {
      "status": 1,
      "code": "1111111111111",
      "product": {
        "brands": "Generic Brand",
        "nutriments": {
          "energy-kcal_100g": 200,
          "proteins_100g": 10,
          "carbohydrates_100g": 20,
          "fat_100g": 5
        }
      }
    }
    """

    static let nameless = """
    {
      "status": 1,
      "code": "1111111111111",
      "product": {
        "nutriments": {
          "energy-kcal_100g": 150
        }
      }
    }
    """

    static let stringyNumerics = """
    {
      "status": 1,
      "code": "2222222222222",
      "product": {
        "product_name": "Stringy",
        "serving_quantity": "250",
        "nova_group": "3",
        "nutriments": {
          "energy-kcal_100g": "88",
          "proteins_100g": "3.5",
          "carbohydrates_100g": "12",
          "fat_100g": "1"
        }
      }
    }
    """

    static let unreadableNumerics = """
    {
      "status": 1,
      "code": "9999999999999",
      "product": {
        "product_name": "Messy record",
        "serving_quantity": "",
        "nova_group": "unknown",
        "nutriments": {
          "energy-kcal_100g": " 120 ",
          "proteins_100g": "1,5",
          "carbohydrates_100g": "nan",
          "fat_100g": "n/a"
        }
      }
    }
    """

    static let searchWithBadFat = """
    {
      "products": [
        {
          "code": "1000000000001",
          "product_name": "Good oats",
          "nutriments": { "energy-kcal_100g": 370, "fat_100g": 7 }
        },
        {
          "code": "1000000000002",
          "product_name": "Odd oats",
          "nutriments": { "energy-kcal_100g": 360, "fat_100g": "n/a" }
        }
      ]
    }
    """

    static let kilojoulesOnly = """
    {
      "status": 1,
      "code": "4444444444444",
      "product": {
        "product_name": "kJ-only product",
        "nutriments": {
          "energy_100g": 1000,
          "proteins_100g": 10,
          "carbohydrates_100g": 20,
          "fat_100g": 5
        }
      }
    }
    """

    static let kilojoulesTypedAsKcal = """
    {
      "status": 1,
      "code": "6666666666666",
      "product": {
        "product_name": "Typed as kcal",
        "nutriments": {
          "energy_100g": 1000,
          "energy_unit": "kcal",
          "proteins_100g": 10,
          "carbohydrates_100g": 20,
          "fat_100g": 5
        }
      }
    }
    """

    static let zeroServingQuantity = """
    {
      "status": 1,
      "code": "5555555555555",
      "product": {
        "product_name": "Zero-serving product",
        "serving_quantity": 0,
        "product_quantity": 0,
        "nutriments": {
          "energy-kcal_100g": 200,
          "proteins_100g": 10,
          "carbohydrates_100g": 20,
          "fat_100g": 5
        }
      }
    }
    """

    static let sparseNutriments = """
    {
      "status": 1,
      "code": "3333333333333",
      "product": {
        "product_name": "Sparse",
        "nutriments": {
          "energy-kcal_100g": 100
        }
      }
    }
    """

    static let malformedNutriments = """
    {
      "status": 1,
      "code": "9999999999999",
      "product": {
        "product_name": "Malformed",
        "nova_group": 1e30,
        "nutriments": {
          "energy-kcal_100g": "nan",
          "proteins_100g": "inf",
          "carbohydrates_100g": "12",
          "fat_100g": "1e30",
          "fiber_100g": -4
        }
      }
    }
    """

    static let onlyMalformedNutriments = """
    {
      "status": 1,
      "code": "9999999999998",
      "product": {
        "product_name": "Garbage",
        "nutriments": {
          "energy-kcal_100g": "nan",
          "proteins_100g": "-inf"
        }
      }
    }
    """

    static let water = """
    {
      "status": 1,
      "code": "7777777777777",
      "product": {
        "product_name": "Still water",
        "nutriments": {
          "energy-kcal_100g": 0,
          "proteins_100g": 0,
          "carbohydrates_100g": 0,
          "fat_100g": 0
        }
      }
    }
    """

    static let noNutriments = """
    {
      "status": 1,
      "code": "8888888888888",
      "product": {
        "product_name": "Unlabelled",
        "nutriments": {}
      }
    }
    """

    static let notFound = """
    {
      "status": 0,
      "status_verbose": "product not found"
    }
    """
}

// MARK: - URLProtocol mock

final class MockURLProtocol: URLProtocol {

    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() { handler = nil }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Thread-safe attempt counter used by retry tests. MockURLProtocol's
/// handler is `@Sendable` and called synchronously from a background
/// loader queue, so plain Int captures aren't safe.
final class AttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    /// Returns the 0-indexed attempt number before incrementing.
    @discardableResult
    func bump() -> Int {
        lock.lock(); defer { lock.unlock() }
        let n = count
        count += 1
        return n
    }
    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }
}

// MARK: - Async-throwing assertion helper

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error but expression succeeded", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

// MARK: - Tiny sendable box for capturing values from mock closures

final class SendableBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { self._value = value }
    var value: T {
        lock.lock(); defer { lock.unlock() }
        return _value
    }
    func set(_ newValue: T) {
        lock.lock(); defer { lock.unlock() }
        _value = newValue
    }
}
