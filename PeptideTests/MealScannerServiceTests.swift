import XCTest
import UIKit
@testable import Peptide

final class MealScannerServiceTests: XCTestCase {

    private var session: URLSession!
    private var service: MealScannerService!
    private let endpoint = URL(string: "https://test-proxy.peptidesai.com/api/meal-scan")!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)

        service = MealScannerService(
            session: session,
            endpoint: endpoint,
            proxySecret: "test-shared-secret"
        )
    }

    override func tearDown() {
        MockURLProtocol.reset()
        session = nil
        service = nil
        super.tearDown()
    }

    private func tinyImage() -> UIImage {
        // 4×4 px solid red image — easily JPEG-compresses to a few
        // hundred bytes, well under the 5 MB cap so `compress` doesn't
        // throw mid-test.
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        return renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    // MARK: - Proxy configuration

    func test_analyze_throwsProxyNotConfigured_whenEndpointMissing() async {
        service = MealScannerService(session: session, endpoint: nil, proxySecret: "x")
        await XCTAssertThrowsErrorAsync(try await service.analyze(image: tinyImage())) { error in
            XCTAssertTrue(error is MealScannerService.ScanError)
            if case .proxyNotConfigured = error as? MealScannerService.ScanError {} else {
                XCTFail("Expected .proxyNotConfigured, got \(error)")
            }
        }
    }

    func test_analyze_throwsProxyNotConfigured_whenSecretMissing() async {
        service = MealScannerService(session: session, endpoint: endpoint, proxySecret: nil)
        await XCTAssertThrowsErrorAsync(try await service.analyze(image: tinyImage())) { error in
            if case .proxyNotConfigured = error as? MealScannerService.ScanError {} else {
                XCTFail("Expected .proxyNotConfigured, got \(error)")
            }
        }
    }

    func test_analyze_throwsProxyNotConfigured_whenSecretIsEmpty() async {
        service = MealScannerService(session: session, endpoint: endpoint, proxySecret: "")
        await XCTAssertThrowsErrorAsync(try await service.analyze(image: tinyImage())) { error in
            if case .proxyNotConfigured = error as? MealScannerService.ScanError {} else {
                XCTFail("Expected .proxyNotConfigured, got \(error)")
            }
        }
    }

    // MARK: - Happy path

    func test_analyze_decodesWellFormedResponse() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.cleanResponse.utf8))
        }
        let estimate = try await service.analyze(image: tinyImage())
        XCTAssertEqual(estimate.mealName, "Chicken caesar salad")
        XCTAssertEqual(estimate.calories, 420)
        XCTAssertEqual(estimate.proteinG, 32)
        XCTAssertEqual(estimate.carbsG, 18)
        XCTAssertEqual(estimate.fatG, 22)
        XCTAssertEqual(estimate.confidence, 0.85, accuracy: 0.001)
    }

    func test_analyze_sendsSharedSecretHeader() async throws {
        let captured = SendableBox<URLRequest?>(nil)
        MockURLProtocol.handler = { request in
            captured.set(request)
            return (Self.ok(for: request), Data(Fixtures.cleanResponse.utf8))
        }
        _ = try await service.analyze(image: tinyImage())
        XCTAssertEqual(captured.value?.value(forHTTPHeaderField: "X-Peptide-Proxy"), "test-shared-secret")
    }

    func test_analyze_sendsJSONContentType() async throws {
        let captured = SendableBox<URLRequest?>(nil)
        MockURLProtocol.handler = { request in
            captured.set(request)
            return (Self.ok(for: request), Data(Fixtures.cleanResponse.utf8))
        }
        _ = try await service.analyze(image: tinyImage())
        XCTAssertEqual(captured.value?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func test_analyze_postsToConfiguredEndpoint() async throws {
        let captured = SendableBox<URLRequest?>(nil)
        MockURLProtocol.handler = { request in
            captured.set(request)
            return (Self.ok(for: request), Data(Fixtures.cleanResponse.utf8))
        }
        _ = try await service.analyze(image: tinyImage())
        XCTAssertEqual(captured.value?.url, endpoint)
        XCTAssertEqual(captured.value?.httpMethod, "POST")
    }

    // MARK: - Stripping code fences

    func test_analyze_stripsMarkdownCodeFences() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.fencedResponse.utf8))
        }
        let estimate = try await service.analyze(image: tinyImage())
        XCTAssertEqual(estimate.mealName, "Avocado toast")
    }

    // MARK: - Implausible / prompt-injected responses

    func test_analyze_rejectsImplausibleCalories() async {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.absurdMacros.utf8))
        }
        await XCTAssertThrowsErrorAsync(try await service.analyze(image: tinyImage())) { error in
            if case .implausibleResult = error as? MealScannerService.ScanError {} else {
                XCTFail("Expected .implausibleResult, got \(error)")
            }
        }
    }

    func test_analyze_rejectsNegativeMacros() async {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.negativeMacros.utf8))
        }
        await XCTAssertThrowsErrorAsync(try await service.analyze(image: tinyImage())) { error in
            if case .implausibleResult = error as? MealScannerService.ScanError {} else {
                XCTFail("Expected .implausibleResult, got \(error)")
            }
        }
    }

    func test_analyze_acceptsZeroMacrosFromNonFoodImage() async throws {
        // The prompt instructs Claude to return all-zeros when the photo
        // isn't food. That's a valid response and must NOT trip the
        // implausible-result clamp.
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.unknownNonFood.utf8))
        }
        let estimate = try await service.analyze(image: tinyImage())
        XCTAssertEqual(estimate.mealName, "unknown")
        XCTAssertEqual(estimate.calories, 0)
        XCTAssertEqual(estimate.confidence, 0)
    }

    // MARK: - HTTP failures

    func test_analyze_throwsRequestFailedOnNon2xx() async {
        MockURLProtocol.handler = { request in
            (Self.response(for: request, status: 500), Data())
        }
        await XCTAssertThrowsErrorAsync(try await service.analyze(image: tinyImage())) { error in
            if case .requestFailed(let message) = error as? MealScannerService.ScanError {
                XCTAssertTrue(message.contains("500"))
            } else {
                XCTFail("Expected .requestFailed, got \(error)")
            }
        }
    }

    func test_analyze_throwsUnauthorisedOn401() async {
        MockURLProtocol.handler = { request in
            (Self.response(for: request, status: 401), Data())
        }
        await XCTAssertThrowsErrorAsync(try await service.analyze(image: tinyImage())) { error in
            guard case .unauthorised = error as? MealScannerService.ScanError else {
                XCTFail("Expected .unauthorised, got \(error)")
                return
            }
            // Must not leak the upstream body (which can carry the
            // masked Anthropic key fingerprint). The user-facing
            // description is generated client-side; assert it does NOT
            // contain anything that would suggest body echoing.
            let description = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertFalse(description.lowercased().contains("anthropic"))
            XCTAssertFalse(description.contains("401"))
        }
    }

    // MARK: - Malformed responses

    func test_analyze_throwsInvalidResponseOnNonAnthropicEnvelope() async {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(#"{"foo":"bar"}"#.utf8))
        }
        await XCTAssertThrowsErrorAsync(try await service.analyze(image: tinyImage())) { error in
            if case .invalidResponse = error as? MealScannerService.ScanError {} else {
                XCTFail("Expected .invalidResponse, got \(error)")
            }
        }
    }

    func test_analyze_throwsParseFailureOnBadJSONInText() async {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.junkTextContent.utf8))
        }
        await XCTAssertThrowsErrorAsync(try await service.analyze(image: tinyImage())) { error in
            if case .parseFailure = error as? MealScannerService.ScanError {} else {
                XCTFail("Expected .parseFailure, got \(error)")
            }
        }
    }

    // MARK: - Settings resolution

    func test_urlSetting_returnsNilForMissingKey() {
        XCTAssertNil(MealScannerService.urlSetting(forKey: "DEFINITELY_NOT_SET_KEY_\(UUID().uuidString)"))
    }

    func test_stringSetting_returnsNilForMissingKey() {
        XCTAssertNil(MealScannerService.stringSetting(forKey: "DEFINITELY_NOT_SET_KEY_\(UUID().uuidString)"))
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

    static let cleanResponse = """
    {
      "id": "msg_xxx",
      "type": "message",
      "role": "assistant",
      "content": [
        {
          "type": "text",
          "text": "{\\"meal_name\\":\\"Chicken caesar salad\\",\\"calories\\":420,\\"protein_g\\":32,\\"carbs_g\\":18,\\"fat_g\\":22,\\"confidence\\":0.85}"
        }
      ]
    }
    """

    static let fencedResponse = """
    {
      "content": [
        {
          "type": "text",
          "text": "```json\\n{\\"meal_name\\":\\"Avocado toast\\",\\"calories\\":280,\\"protein_g\\":7,\\"carbs_g\\":28,\\"fat_g\\":15,\\"confidence\\":0.7}\\n```"
        }
      ]
    }
    """

    static let absurdMacros = """
    {
      "content": [
        {
          "type": "text",
          "text": "{\\"meal_name\\":\\"injection\\",\\"calories\\":99999,\\"protein_g\\":5000,\\"carbs_g\\":5000,\\"fat_g\\":5000,\\"confidence\\":0.5}"
        }
      ]
    }
    """

    static let negativeMacros = """
    {
      "content": [
        {
          "type": "text",
          "text": "{\\"meal_name\\":\\"weird\\",\\"calories\\":-200,\\"protein_g\\":10,\\"carbs_g\\":10,\\"fat_g\\":10,\\"confidence\\":0.5}"
        }
      ]
    }
    """

    static let unknownNonFood = """
    {
      "content": [
        {
          "type": "text",
          "text": "{\\"meal_name\\":\\"unknown\\",\\"calories\\":0,\\"protein_g\\":0,\\"carbs_g\\":0,\\"fat_g\\":0,\\"confidence\\":0}"
        }
      ]
    }
    """

    static let junkTextContent = """
    {
      "content": [
        { "type": "text", "text": "I think this is salad? not sure though." }
      ]
    }
    """
}

// MARK: - Async-throwing assertion helper (file-private duplicate of the
// one in OpenFoodFactsServiceTests — XCTAssert is sync and SwiftTest is
// out of scope for this commit).

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
