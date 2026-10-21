import XCTest
import UIKit
@testable import Peptide

/// `LabScanService` over the shared scanner transport: route, payload,
/// and how the route's answers become results or errors.
final class LabScanServiceTests: XCTestCase {

    private var session: URLSession!
    private var service: LabScanService!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        let transport = MealScannerService(
            session: session,
            endpoint: URL(string: "https://test-proxy.peptidesai.com/api/meal-scan")!,
            proxySecret: "test-shared-secret"
        )
        service = LabScanService(transport: transport)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        session = nil
        service = nil
        super.tearDown()
    }

    func test_scan_postsJpegPagesToLabScanRoute_andDecodesMarkers() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/lab-scan")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Peptide-Proxy"), "test-shared-secret")
            let images = try XCTUnwrap(try Self.body(of: request)["images"] as? [String])
            XCTAssertEqual(images.count, 2)
            XCTAssertTrue(images.allSatisfy { $0.hasPrefix("/9j/") }, "pages are sent as JPEG")
            return (Self.response(request, 200), Data(Self.report.utf8))
        }
        let scan = try await service.scan(pages: [tinyImage(), tinyImage()])

        XCTAssertEqual(scan.markers.map(\.name), ["S-Testosteron"])
        XCTAssertEqual(scan.collectedOn, "2026-09-14")
    }

    func test_scan_notALabReport_throws() async {
        MockURLProtocol.handler = { request in
            (Self.response(request, 200), Data(#"{"result":{"is_lab_report":false,"collected_on":null,"lab_name":null,"markers":[]}}"#.utf8))
        }
        await assertThrows(LabScanService.LabScanError.notALabReport) {
            _ = try await self.service.scan(pages: [self.tinyImage()])
        }
    }

    func test_scan_onlyNonNumericRows_throwsNothingReadable() async {
        let body = #"{"result":{"is_lab_report":true,"collected_on":null,"lab_name":null,"markers":[{"name":"HIV","value":null,"unit":"","reference_low":null,"reference_high":null,"reference_text":null,"collected_on":null}]}}"#
        MockURLProtocol.handler = { request in (Self.response(request, 200), Data(body.utf8)) }
        await assertThrows(LabScanService.LabScanError.nothingReadable) {
            _ = try await self.service.scan(pages: [self.tinyImage()])
        }
    }

    func test_scan_tooManyPages_throwsBeforeAnyRequest() async {
        MockURLProtocol.handler = { _ in
            XCTFail("no request expected")
            throw URLError(.badURL)
        }
        let pages = Array(repeating: tinyImage(), count: LabScanService.maxPages + 1)
        await assertThrows(LabScanService.LabScanError.tooManyPages) {
            _ = try await self.service.scan(pages: pages)
        }
    }

    func test_message_rewordsTransportErrorsForLabs() {
        XCTAssertFalse(LabScanService.message(for: MealScannerService.ScanError.rateLimited).contains("meal"))
        XCTAssertFalse(LabScanService.message(for: MealScannerService.ScanError.routeMissing).contains("HTTP"))
        XCTAssertEqual(
            LabScanService.message(for: LabScanService.LabScanError.notALabReport),
            LabScanService.LabScanError.notALabReport.errorDescription
        )
    }

    // MARK: - Helpers

    private func assertThrows(
        _ expected: LabScanService.LabScanError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as LabScanService.LabScanError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected \(expected), got \(error)", file: file, line: line)
        }
    }

    private static let report = """
    {"result":{"is_lab_report":true,"collected_on":"2026-09-14","lab_name":null,
      "markers":[{"name":"S-Testosteron","value":18.2,"unit":"nmol/L","reference_low":8.6,
                  "reference_high":29,"reference_text":"8.6–29","collected_on":null}]},
     "model":"claude-opus-5-5"}
    """

    private func tinyImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { ctx in
            UIColor.white.setFill()
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
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}
