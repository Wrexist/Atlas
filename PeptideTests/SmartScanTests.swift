import XCTest
import UIKit
@testable import Peptide

/// The smart scan path: `food-scan` request routing, decoding and
/// plausibility, the legacy fallback, and the mapping into library and
/// barcode-review shapes.
final class SmartScanTests: XCTestCase {

    private var session: URLSession!
    private var service: MealScannerService!
    private let endpoint = URL(string: "https://test-proxy.peptidesai.com/api/meal-scan")!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        service = MealScannerService(session: session, endpoint: endpoint, proxySecret: "test-shared-secret")
    }

    override func tearDown() {
        MockURLProtocol.reset()
        session = nil
        service = nil
        super.tearDown()
    }

    // MARK: - Service

    func test_smartScan_postsToFoodScanRoute_andDecodesItems() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/food-scan")
            XCTAssertEqual(try Self.body(of: request)["mode"] as? String, "photo")
            return (Self.response(request, 200), Data(SmartFixtures.meal.utf8))
        }
        let scan = try await service.smartScan(image: tinyImage())

        XCTAssertEqual(scan.insight.kind, .meal)
        XCTAssertEqual(scan.insight.tips, ["Frying oil isn't visible."])
        XCTAssertEqual(scan.items.count, 1, "the implausible second row is dropped")
        let pasta = try XCTUnwrap(scan.items.first)
        XCTAssertEqual(pasta.calories, 395, "158 kcal/100 g × 250 g")
        XCTAssertEqual(pasta.per100g?.fiberG, 1.8)
        XCTAssertEqual(pasta.portionOptions?.map(\.label), ["Half plate"])
        XCTAssertEqual(pasta.price?.currency, "SEK")
    }

    func test_smartScan_fallsBackToLegacyRoute_whenFoodScanIsMissing() async throws {
        MockURLProtocol.handler = { request in
            if request.url?.path == "/api/food-scan" {
                return (Self.response(request, 404), Data())
            }
            return (Self.response(request, 200), Data(SmartFixtures.legacyItems.utf8))
        }
        let scan = try await service.smartScan(image: tinyImage())

        XCTAssertEqual(scan.items.map(\.name), ["Banana"])
        XCTAssertNil(scan.items.first?.price)
    }

    func test_smartScan_notFood_throwsNoFoodDetected() async {
        MockURLProtocol.handler = { request in
            (Self.response(request, 200), Data(SmartFixtures.notFood.utf8))
        }
        do {
            _ = try await service.smartScan(image: tinyImage())
            XCTFail("Expected noFoodDetected")
        } catch MealScannerService.ScanError.noFoodDetected {
        } catch {
            XCTFail("Expected noFoodDetected, got \(error)")
        }
    }

    func test_smartScan_declinedImage_throwsDeclined() async {
        MockURLProtocol.handler = { request in
            (Self.response(request, 422), Data(#"{"error":{"code":"refused"}}"#.utf8))
        }
        do {
            _ = try await service.smartScan(image: tinyImage())
            XCTFail("Expected declined")
        } catch MealScannerService.ScanError.declined {
        } catch {
            XCTFail("Expected declined, got \(error)")
        }
    }

    func test_describeProduct_sendsProductFacts() async throws {
        MockURLProtocol.handler = { request in
            let body = try Self.body(of: request)
            XCTAssertEqual(body["mode"] as? String, "product")
            let product = try XCTUnwrap(body["product"] as? [String: String])
            XCTAssertEqual(product["query"], "oatly barista 1 l")
            XCTAssertNil(product["brand"], "empty fields are not sent")
            return (Self.response(request, 200), Data(SmartFixtures.product.utf8))
        }
        let scan = try await service.describeProduct(.init(query: "oatly barista 1 l"))

        XCTAssertEqual(scan.package?.totalGrams, 1000)
        XCTAssertEqual(scan.items.first?.brand, "Oatly")
    }

    func test_smartScan_sendsUserCorrections() async throws {
        let fix = ScanCorrection(seen: "Spaghetti", seenGrams: 250, loggedAs: "Fullkornspasta",
                                 grams: 180, brand: nil, date: Date())
        MockURLProtocol.handler = { request in
            let sent = try XCTUnwrap(try Self.body(of: request)["corrections"] as? [[String: Any]])
            XCTAssertEqual(sent.first?["logged_as"] as? String, "Fullkornspasta")
            XCTAssertEqual(sent.first?["seen_grams"] as? Double, 250)
            XCTAssertNil(sent.first?["brand"])
            return (Self.response(request, 200), Data(SmartFixtures.meal.utf8))
        }
        _ = try await service.smartScan(image: tinyImage(), corrections: [fix])
    }

    func test_followUpQuestion_attachesToItsItem_andDropsBadAnswers() throws {
        let scan = try service.parseSmartScan(from: Data(SmartFixtures.meal.utf8))
        let question = try XCTUnwrap(scan.items.first?.question)
        XCTAssertEqual(question.question, "Tossed in oil?")
        XCTAssertEqual(question.answers.map(\.label), ["No", "Yes"], "duplicate and implausible answers dropped")
    }

    func test_answeringQuestion_swapsValues_keepsUserPortion() throws {
        let scan = try service.parseSmartScan(from: Data(SmartFixtures.meal.utf8))
        var item = EditableFoodItem(from: try XCTUnwrap(scan.items.first))
        item.grams = 125
        item.answer(1)
        XCTAssertEqual(item.grams, 130, "half the plate, plus the oil's share")
        XCTAssertEqual(item.calories, 247)
        item.answer(0)
        XCTAssertEqual(item.grams, 125)

        item.answer(1)
        item.correctNutrition(LoggableMeal(calories: 100, proteinG: 1, carbsG: 1, fatG: 1))
        XCTAssertNil(item.openQuestion, "a manual edit retires the question")
        item.resetNutrition()
        XCTAssertEqual(item.selectedAnswer, 0)
    }

    // MARK: - Correction memory

    @MainActor
    func test_correctionMemory_keepsRenamesAndBigPortionChanges_only() {
        let memory = ScanCorrectionMemory(defaults: freshDefaults())
        memory.record(seen: "spaghetti", seenGrams: 250, loggedAs: "Spaghetti", grams: 240, brand: nil)
        XCTAssertTrue(memory.corrections.isEmpty, "same name, 4% off is not a correction")

        memory.record(seen: "spaghetti", seenGrams: 250, loggedAs: "Spaghetti", grams: 180, brand: nil)
        memory.record(seen: "oat drink", seenGrams: 200, loggedAs: "Oatly Barista", grams: 200, brand: "Oatly")
        XCTAssertEqual(memory.corrections.map(\.loggedAs), ["Oatly Barista", "Spaghetti"], "newest first")
    }

    @MainActor
    func test_correctionMemory_replacesSameFood_persists_andErases() {
        let defaults = freshDefaults()
        let memory = ScanCorrectionMemory(defaults: defaults)
        memory.record(seen: "Spaghetti", seenGrams: 250, loggedAs: "Pasta", grams: 250, brand: nil)
        memory.record(seen: "spaghetti ", seenGrams: 250, loggedAs: "Fullkornspasta", grams: 180, brand: nil)

        let reloaded = ScanCorrectionMemory(defaults: defaults)
        XCTAssertEqual(reloaded.corrections.map(\.loggedAs), ["Fullkornspasta"])

        reloaded.eraseAll()
        XCTAssertTrue(ScanCorrectionMemory(defaults: defaults).corrections.isEmpty)
    }

    @MainActor
    func test_correctionMemory_capsStoredAndSent() {
        let memory = ScanCorrectionMemory(defaults: freshDefaults())
        for index in 0..<(ScanCorrectionMemory.maxStored + 5) {
            memory.record(seen: "food \(index)", seenGrams: 100, loggedAs: "mine \(index)", grams: 100, brand: nil)
        }
        XCTAssertEqual(memory.corrections.count, ScanCorrectionMemory.maxStored)
        XCTAssertEqual(memory.recent.count, ScanCorrectionMemory.maxSent)
        XCTAssertEqual(memory.recent.first?.loggedAs, "mine \(ScanCorrectionMemory.maxStored + 4)")
    }

    // MARK: - Mapping

    func test_customFoodFromScan_usesPackageServing_andPricePer100g() throws {
        let scan = try service.parseSmartScan(from: Data(SmartFixtures.product.utf8))
        let food = try XCTUnwrap(SmartFoodLogic.customFood(from: scan))

        XCTAssertEqual(food.name, "Barista Oat Drink")
        XCTAssertEqual(food.servingGrams, 250)
        XCTAssertEqual(food.servingLabel, "1 glass")
        // 22–26 SEK for the 1000 g carton → 2.2–2.6 per 100 g.
        XCTAssertEqual(food.pricePer100g?.low ?? 0, 2.2, accuracy: 0.001)
        XCTAssertEqual(food.typicalPrice?.high ?? 0, 6.5, accuracy: 0.001, "one 250 g serving")
    }

    func test_productFillingFromScan_neverOverwritesDatabaseValues() throws {
        let scan = try service.parseSmartScan(from: Data(SmartFixtures.product.utf8))
        let known = ScannedProduct(barcode: "7394376616228", name: "Barista", brand: "Oatly", imageURL: nil,
                                   servingSizeText: "1 cup", servingGrams: 200, packageGrams: nil,
                                   per100g: .zero, nutriScore: nil, novaGroup: nil, fetchedAt: Date())
        let filled = SmartFoodLogic.product(known, fillingFrom: scan)

        XCTAssertEqual(filled.servingGrams, 200)
        XCTAssertEqual(filled.servingSizeText, "1 cup")
        XCTAssertEqual(filled.packageGrams, 1000, "the missing net weight is filled")
    }

    func test_packagePhoto_becomesReviewableProduct_underScannedBarcode() throws {
        let scan = try service.parseSmartScan(from: Data(SmartFixtures.product.utf8))
        let product = try XCTUnwrap(SmartFoodLogic.product(from: scan, barcode: "7394376616228"))

        XCTAssertEqual(product.barcode, "7394376616228")
        XCTAssertEqual(product.defaultPortion, .servings(1))
        XCTAssertEqual(product.loggable(for: .wholePackage)?.calories, 590)
    }

    func test_priceTotal_refusesToMixCurrencies() {
        let sek = FoodPriceEstimate(low: 10, high: 20, currency: "SEK", basis: .store)
        let eur = FoodPriceEstimate(low: 1, high: 2, currency: "EUR", basis: .store)
        XCTAssertEqual(FoodPriceEstimate.total([sek, sek])?.high, 40)
        XCTAssertNil(FoodPriceEstimate.total([sek, eur]))
        XCTAssertFalse(FoodPriceEstimate(low: 5, high: 1, currency: "SEK", basis: .store).isPlausible)
    }

    func test_editableItem_scalesPriceWithPortion() throws {
        let scan = try service.parseSmartScan(from: Data(SmartFixtures.meal.utf8))
        var item = EditableFoodItem(from: try XCTUnwrap(scan.items.first))
        item.grams = 125
        XCTAssertEqual(item.price?.low ?? 0, 10, accuracy: 0.001, "half the plate, half the price")
        XCTAssertEqual(item.component.per100g.fiberG, 1.8, "fibre now reaches the diary")
    }

    // MARK: - Helpers

    private func freshDefaults() -> UserDefaults {
        let suite = "SmartScanTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    private func tinyImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    private static func response(_ request: URLRequest, _ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"])!
    }

    /// URLSession hands the body to URLProtocol as a stream.
    private static func body(of request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
        }
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private enum SmartFixtures {
    static let meal = """
    {"model":"claude-opus-5-5","result":{
      "kind":"meal","title":"Spaghetti","summary":"A plate of spaghetti.","tips":["Frying oil isn't visible.", ""],
      "package":null,
      "items":[
        {"name":"Spaghetti","brand":null,"portion_label":"1 plate","grams":250,
         "portion_options":[{"label":"Half plate","grams":125}],
         "per_100g":{"calories":158,"protein_g":5.8,"carbs_g":31,"fat_g":0.9,"fiber_g":1.8,"sugars_g":0.6},
         "confidence":0.9,"price":{"low":20,"high":30,"currency":"SEK","basis":"homemade"}},
        {"name":"Mystery","brand":null,"portion_label":"1","grams":100,"portion_options":[],
         "per_100g":{"calories":4000,"protein_g":1,"carbs_g":1,"fat_g":1,"fiber_g":0,"sugars_g":0},
         "confidence":0.5,"price":null}
      ],
      "questions":[
        {"item_index":1,"question":"Mystery?","options":[]},
        {"item_index":0,"question":"Tossed in oil?","options":[
          {"label":"No","grams":250,"per_100g":{"calories":158,"protein_g":5.8,"carbs_g":31,"fat_g":0.9,"fiber_g":1.8,"sugars_g":0.6}},
          {"label":"Yes","grams":260,"per_100g":{"calories":190,"protein_g":5.6,"carbs_g":29.8,"fat_g":4.7,"fiber_g":1.7,"sugars_g":0.6}},
          {"label":"yes","grams":260,"per_100g":{"calories":190,"protein_g":5.6,"carbs_g":29.8,"fat_g":4.7,"fiber_g":1.7,"sugars_g":0.6}},
          {"label":"Lard","grams":260,"per_100g":{"calories":1900,"protein_g":0,"carbs_g":0,"fat_g":100,"fiber_g":0,"sugars_g":0}}
        ]}
      ]}}
    """

    static let product = """
    {"model":"claude-opus-5-5","result":{
      "kind":"packaged_product","title":"Oatly Barista","summary":"Oat drink for coffee.","tips":[],
      "package":{"total_grams":1000,"serving_grams":250,"serving_label":"1 glass"},
      "items":[
        {"name":"Barista Oat Drink","brand":"Oatly","portion_label":"1 carton","grams":1000,
         "portion_options":[{"label":"1 glass","grams":250},{"label":"Splash in coffee","grams":30}],
         "per_100g":{"calories":59,"protein_g":1.1,"carbs_g":6.6,"fat_g":3.0,"fiber_g":0.8,"sugars_g":3.4},
         "confidence":0.95,"price":{"low":22,"high":26,"currency":"SEK","basis":"store"}}
      ]}}
    """

    static let notFood = """
    {"model":"claude-opus-5-5","result":{
      "kind":"not_food","title":"Book","summary":"This is a book.","tips":[],"package":null,"items":[]}}
    """

    static let legacyItems = """
    {"content":[{"type":"text","text":"{\\"meal_name\\":null,\\"items\\":[{\\"name\\":\\"Banana\\",\\"quantity_label\\":\\"1 banana\\",\\"grams\\":120,\\"calories\\":105,\\"protein_g\\":1,\\"carbs_g\\":27,\\"fat_g\\":0,\\"confidence\\":0.9}]}"}]}
    """
}
