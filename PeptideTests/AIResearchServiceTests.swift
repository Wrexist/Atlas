import XCTest
@testable import Peptide

final class AIResearchServiceTests: XCTestCase {

    private var session: URLSession!
    private var service: AIResearchService!
    private let endpoint = URL(string: "https://test-proxy.peptidesai.com/api/ai-research")!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)

        service = AIResearchService(
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

    private func samplePeptide(name: String = "BPC-157", abbreviation: String = "BPC-157") -> Peptide {
        Peptide(
            id: UUID(),
            name: name,
            abbreviation: abbreviation,
            category: .recovery,
            description: "Pentadecapeptide derived from human gastric juice.",
            benefits: [],
            dosageRange: "200–500 mcg/day",
            frequency: "Daily",
            halfLife: "≈ 4 hours",
            adminRoute: "Subcutaneous",
            researchLinks: [],
            imageSystemName: "pills.fill",
            mechanism: "Stimulates angiogenesis and modulates growth factors.",
            contraindications: ["Active malignancy"]
        )
    }

    // MARK: - Proxy configuration

    func test_reply_throwsProxyNotConfigured_whenEndpointMissing() async {
        service = AIResearchService(session: session, endpoint: nil, proxySecret: "x")
        await XCTAssertThrowsErrorAsyncResearch(try await service.reply(history: [], newUserPrompt: "hi", in: [])) { error in
            if case .proxyNotConfigured = error as? AIResearchService.ChatError {} else {
                XCTFail("Expected .proxyNotConfigured, got \(error)")
            }
        }
    }

    func test_reply_throwsProxyNotConfigured_whenSecretMissing() async {
        service = AIResearchService(session: session, endpoint: endpoint, proxySecret: nil)
        await XCTAssertThrowsErrorAsyncResearch(try await service.reply(history: [], newUserPrompt: "hi", in: [])) { error in
            if case .proxyNotConfigured = error as? AIResearchService.ChatError {} else {
                XCTFail("Expected .proxyNotConfigured, got \(error)")
            }
        }
    }

    func test_reply_throwsProxyNotConfigured_whenSecretIsEmpty() async {
        service = AIResearchService(session: session, endpoint: endpoint, proxySecret: "")
        await XCTAssertThrowsErrorAsyncResearch(try await service.reply(history: [], newUserPrompt: "hi", in: [])) { error in
            if case .proxyNotConfigured = error as? AIResearchService.ChatError {} else {
                XCTFail("Expected .proxyNotConfigured, got \(error)")
            }
        }
    }

    // MARK: - Happy path

    func test_reply_returnsAssistantText() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.helloReply.utf8))
        }
        let text = try await service.reply(history: [], newUserPrompt: "hi", in: [])
        XCTAssertEqual(text, "Hello! How can I help with peptide research today?")
    }

    func test_reply_trimsTrailingWhitespace() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.whitespacePadded.utf8))
        }
        let text = try await service.reply(history: [], newUserPrompt: "hi", in: [])
        XCTAssertEqual(text, "Trimmed answer.")
    }

    // MARK: - Headers

    func test_reply_sendsSharedSecretHeader() async throws {
        let captured = SendableBox<URLRequest?>(nil)
        MockURLProtocol.handler = { request in
            captured.set(request)
            return (Self.ok(for: request), Data(Fixtures.helloReply.utf8))
        }
        _ = try await service.reply(history: [], newUserPrompt: "hi", in: [])
        XCTAssertEqual(captured.value?.value(forHTTPHeaderField: "X-Peptide-Proxy"), "test-shared-secret")
    }

    func test_reply_doesNotSendAnthropicVersionHeader() async throws {
        // The proxy adds anthropic-version server-side; the client
        // shouldn't try to forward it (would be redundant and could
        // mask a stale client if Anthropic ever requires a newer
        // version).
        let captured = SendableBox<URLRequest?>(nil)
        MockURLProtocol.handler = { request in
            captured.set(request)
            return (Self.ok(for: request), Data(Fixtures.helloReply.utf8))
        }
        _ = try await service.reply(history: [], newUserPrompt: "hi", in: [])
        XCTAssertNil(captured.value?.value(forHTTPHeaderField: "anthropic-version"))
    }

    // MARK: - Payload shape

    func test_reply_putsNewPromptInLastMessage() async throws {
        let captured = SendableBox<URLRequest?>(nil)
        MockURLProtocol.handler = { request in
            captured.set(request)
            return (Self.ok(for: request), Data(Fixtures.helloReply.utf8))
        }
        let history = [
            AIResearchService.Turn(role: .user, content: "First message"),
            AIResearchService.Turn(role: .assistant, content: "First reply"),
        ]
        _ = try await service.reply(history: history, newUserPrompt: "Second message", in: [])
        let body = try Self.decodeBody(captured.value)
        let messages = body["messages"] as? [[String: Any]] ?? []
        XCTAssertEqual(messages.count, 3, "Expected history.count + 1 for the new turn")
        XCTAssertEqual(messages.last?["role"] as? String, "user")
        XCTAssertEqual(messages.last?["content"] as? String, "Second message")
    }

    func test_reply_includesSystemPrompt() async throws {
        let captured = SendableBox<URLRequest?>(nil)
        MockURLProtocol.handler = { request in
            captured.set(request)
            return (Self.ok(for: request), Data(Fixtures.helloReply.utf8))
        }
        _ = try await service.reply(history: [], newUserPrompt: "hi", in: [])
        let body = try Self.decodeBody(captured.value)
        let system = body["system"] as? String ?? ""
        XCTAssertTrue(system.contains("research assistant"))
        XCTAssertTrue(system.contains("Never recommend"))  // the dose-advice guardrail
    }

    // MARK: - RAG

    func test_reply_injectsRagContext_whenPromptMentionsKnownPeptide() async throws {
        let captured = SendableBox<URLRequest?>(nil)
        MockURLProtocol.handler = { request in
            captured.set(request)
            return (Self.ok(for: request), Data(Fixtures.helloReply.utf8))
        }
        let database = [samplePeptide()]
        _ = try await service.reply(history: [], newUserPrompt: "what is BPC-157?", in: database)
        let body = try Self.decodeBody(captured.value)
        let system = body["system"] as? String ?? ""
        XCTAssertTrue(system.contains("BPC-157"), "RAG should inject peptide metadata when the abbreviation matches")
        XCTAssertTrue(system.contains("Subcutaneous"), "RAG should include adminRoute when present")
    }

    func test_reply_omitsRagContext_whenPromptMentionsNoKnownPeptide() async throws {
        let captured = SendableBox<URLRequest?>(nil)
        MockURLProtocol.handler = { request in
            captured.set(request)
            return (Self.ok(for: request), Data(Fixtures.helloReply.utf8))
        }
        let database = [samplePeptide()]
        _ = try await service.reply(history: [], newUserPrompt: "hello there", in: database)
        let body = try Self.decodeBody(captured.value)
        let system = body["system"] as? String ?? ""
        XCTAssertFalse(system.contains("Database context"))
    }

    func test_reply_capsRagContextAtFourPeptides() async throws {
        let captured = SendableBox<URLRequest?>(nil)
        MockURLProtocol.handler = { request in
            captured.set(request)
            return (Self.ok(for: request), Data(Fixtures.helloReply.utf8))
        }
        // Six matching peptides in the prompt — RAG should only inject
        // the first four to keep the system prompt under Claude's
        // input limits.
        let peptides = (0..<6).map { samplePeptide(name: "Test\($0)", abbreviation: "T\($0)") }
        let prompt = "Tell me about T0 T1 T2 T3 T4 T5"
        _ = try await service.reply(history: [], newUserPrompt: prompt, in: peptides)
        let body = try Self.decodeBody(captured.value)
        let system = body["system"] as? String ?? ""
        XCTAssertTrue(system.contains("T0"))
        XCTAssertTrue(system.contains("T3"))
        XCTAssertFalse(system.contains("T4"), "RAG should only include the first 4 matched peptides")
    }

    // MARK: - HTTP failures

    func test_reply_throwsRequestFailedOnNon2xx() async {
        MockURLProtocol.handler = { request in
            (Self.response(for: request, status: 502), Data())
        }
        await XCTAssertThrowsErrorAsyncResearch(try await service.reply(history: [], newUserPrompt: "hi", in: [])) { error in
            if case .requestFailed(let message) = error as? AIResearchService.ChatError {
                XCTAssertTrue(message.contains("502"))
            } else {
                XCTFail("Expected .requestFailed, got \(error)")
            }
        }
    }

    func test_reply_throwsInvalidResponseOnBadEnvelope() async {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(#"{"oops":true}"#.utf8))
        }
        await XCTAssertThrowsErrorAsyncResearch(try await service.reply(history: [], newUserPrompt: "hi", in: [])) { error in
            if case .invalidResponse = error as? AIResearchService.ChatError {} else {
                XCTFail("Expected .invalidResponse, got \(error)")
            }
        }
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

    private static func decodeBody(_ request: URLRequest?) throws -> [String: Any] {
        // URLSession swaps `httpBody` to `httpBodyStream` when the body
        // is set via Data, so read either way.
        let data: Data?
        if let body = request?.httpBody {
            data = body
        } else if let stream = request?.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            let chunkSize = 4096
            var buffer = [UInt8](repeating: 0, count: chunkSize)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: chunkSize)
                if read <= 0 { break }
                collected.append(buffer, count: read)
            }
            data = collected
        } else {
            data = nil
        }
        guard let data, let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "AIResearchServiceTests", code: -1)
        }
        return obj
    }
}

// MARK: - Fixtures

private enum Fixtures {

    static let helloReply = """
    {
      "id": "msg_xxx",
      "type": "message",
      "role": "assistant",
      "content": [
        { "type": "text", "text": "Hello! How can I help with peptide research today?" }
      ]
    }
    """

    static let whitespacePadded = """
    {
      "content": [
        { "type": "text", "text": "  \\n  Trimmed answer.  \\n  " }
      ]
    }
    """
}

private func XCTAssertThrowsErrorAsyncResearch<T>(
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
