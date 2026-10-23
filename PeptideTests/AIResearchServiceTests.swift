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

    func test_reply_maxTokensStop_marksAnswerTruncated() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.truncatedReply.utf8))
        }
        let text = try await service.reply(history: [], newUserPrompt: "hi", in: [])
        XCTAssertTrue(text.hasPrefix("BPC-157 has been studied in"))
        XCTAssertTrue(text.hasSuffix(AIResearchService.truncationNote))
    }

    func test_reply_endTurnStop_isNotMarkedTruncated() async throws {
        MockURLProtocol.handler = { request in
            (Self.ok(for: request), Data(Fixtures.helloReply.utf8))
        }
        let text = try await service.reply(history: [], newUserPrompt: "hi", in: [])
        XCTAssertFalse(text.contains(AIResearchService.truncationNote))
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

    func test_reply_evenLengthHistoryPastCap_firstMessageIsUser() async throws {
        let captured = SendableBox<URLRequest?>(nil)
        MockURLProtocol.handler = { request in
            captured.set(request)
            return (Self.ok(for: request), Data(Fixtures.helloReply.utf8))
        }
        let history = (0..<40).map { i in
            AIResearchService.Turn(role: i.isMultiple(of: 2) ? .user : .assistant, content: "Turn \(i)")
        }
        _ = try await service.reply(history: history, newUserPrompt: "Next question", in: [])
        let body = try Self.decodeBody(captured.value)
        let messages = body["messages"] as? [[String: Any]] ?? []
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertLessThanOrEqual(messages.count, 40)
    }

    /// The proxy prepends the persona and safety rules; repeating them
    /// client-side only spent the route's system budget.
    func test_reply_noMentionedCompound_sendsNoSystem() async throws {
        let captured = SendableBox<URLRequest?>(nil)
        MockURLProtocol.handler = { request in
            captured.set(request)
            return (Self.ok(for: request), Data(Fixtures.helloReply.utf8))
        }
        _ = try await service.reply(history: [], newUserPrompt: "hi", in: [])
        let body = try Self.decodeBody(captured.value)
        XCTAssertNil(body["system"])
    }

    func test_reply_withCoachBrief_appendsSummaryToSystemPrompt() async throws {
        let captured = SendableBox<URLRequest?>(nil)
        MockURLProtocol.handler = { request in
            captured.set(request)
            return (Self.ok(for: request), Data(Fixtures.helloReply.utf8))
        }
        let brief = "Days with food logged: 5 of 7."
        _ = try await service.reply(history: [], newUserPrompt: "How was my week?", in: [], coachBrief: brief)
        let system = try Self.decodeBody(captured.value)["system"] as? String ?? ""
        XCTAssertTrue(system.contains("Nutrition coach mode"))
        XCTAssertTrue(system.contains(brief))
    }

    func test_reply_withoutCoachBrief_staysInResearchMode() async throws {
        let captured = SendableBox<URLRequest?>(nil)
        MockURLProtocol.handler = { request in
            captured.set(request)
            return (Self.ok(for: request), Data(Fixtures.helloReply.utf8))
        }
        _ = try await service.reply(history: [], newUserPrompt: "hi", in: [])
        let system = try Self.decodeBody(captured.value)["system"] as? String ?? ""
        XCTAssertFalse(system.contains("Nutrition coach mode"))
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

    func test_reply_verboseEntries_systemStaysWithinProxyCap() async throws {
        let captured = SendableBox<URLRequest?>(nil)
        MockURLProtocol.handler = { request in
            captured.set(request)
            return (Self.ok(for: request), Data(Fixtures.helloReply.utf8))
        }
        let verbose = String(repeating: "Long research prose. ", count: 150)
        let peptides = (0..<4).map { i in
            Peptide(
                id: UUID(),
                name: "Verbose\(i)",
                abbreviation: "VB\(i)",
                category: .recovery,
                description: verbose,
                benefits: [],
                dosageRange: "200–500 mcg/day",
                frequency: "Daily",
                halfLife: "≈ 4 hours",
                adminRoute: "Subcutaneous",
                researchLinks: [],
                imageSystemName: "pills.fill",
                mechanism: verbose,
                contraindications: ["Active malignancy"]
            )
        }
        _ = try await service.reply(history: [], newUserPrompt: "Compare VB0 VB1 VB2 VB3", in: peptides)
        let body = try Self.decodeBody(captured.value)
        let system = body["system"] as? String ?? ""
        XCTAssertLessThanOrEqual(system.utf16.count, AIResearchService.systemCharacterBudget)
        XCTAssertTrue(system.contains("Verbose1"), "Clipped fields should leave room for a second compound")
        XCTAssertTrue(system.hasSuffix("Active malignancy"), "Entries are kept whole or not at all")
    }

    // MARK: - Error presentation

    func test_chatError_dailyLimit_isNotRetryableAndSaysSo() {
        let error = AIResearchService.ChatError.dailyLimitReached
        XCTAssertFalse(error.isRetryable)
        XCTAssertEqual(error.alertTitle, String(localized: "Daily limit reached"))
    }

    func test_chatError_rejectedBuild_isNotRetryable() {
        XCTAssertFalse(AIResearchService.ChatError.unauthorised.isRetryable)
        XCTAssertFalse(AIResearchService.ChatError.proxyNotConfigured.isRetryable)
        XCTAssertFalse(AIResearchService.ChatError.questionTooLong.isRetryable)
    }

    func test_chatError_transientFailures_areRetryable() {
        for error in [AIResearchService.ChatError.offline, .rateLimited, .serviceUnavailable, .invalidResponse] {
            XCTAssertTrue(error.isRetryable, "\(error)")
            XCTAssertEqual(error.alertTitle, String(localized: "Couldn't reach the assistant"), "\(error)")
        }
    }

    // MARK: - HTTP failures

    func test_reply_unmappedStatus_throwsServiceUnavailable() async {
        MockURLProtocol.handler = { request in
            (Self.response(for: request, status: 500), Data())
        }
        await XCTAssertThrowsErrorAsyncResearch(try await service.reply(history: [], newUserPrompt: "hi", in: [])) { error in
            guard case .serviceUnavailable = error as? AIResearchService.ChatError else {
                return XCTFail("Expected .serviceUnavailable, got \(error)")
            }
            XCTAssertFalse(error.localizedDescription.contains("500"))
        }
    }

    /// A pasted question over the proxy's body cap (413) or a malformed
    /// body (400) gets copy the user can act on.
    func test_reply_oversizedOrMalformedBody_throwsQuestionTooLong() async {
        for status in [400, 413] {
            MockURLProtocol.handler = { request in
                (Self.response(for: request, status: status), Data())
            }
            await XCTAssertThrowsErrorAsyncResearch(try await service.reply(history: [], newUserPrompt: "hi", in: [])) { error in
                guard case .questionTooLong = error as? AIResearchService.ChatError else {
                    return XCTFail("Expected .questionTooLong for HTTP \(status), got \(error)")
                }
            }
        }
    }

    /// The proxy's Pro gate (403 `pro_required`) asks for Pro instead
    /// of claiming the assistant is down, and Retry can't fix it.
    func test_reply_proGateRefusal_throwsProRequired() async {
        MockURLProtocol.handler = { request in
            (Self.response(for: request, status: 403), Data(#"{"error":{"code":"pro_required"}}"#.utf8))
        }
        await XCTAssertThrowsErrorAsyncResearch(try await service.reply(history: [], newUserPrompt: "hi", in: [])) { error in
            guard case .proRequired = error as? AIResearchService.ChatError else {
                return XCTFail("Expected .proRequired, got \(error)")
            }
            XCTAssertFalse(AIResearchService.ChatError.proRequired.isRetryable)
        }
    }

    /// The gateway codes that get the friendlier message.
    func test_reply_throwsServiceUnavailableOnGatewayErrors() async {
        for status in [502, 503, 504] {
            MockURLProtocol.handler = { request in
                (Self.response(for: request, status: status), Data())
            }
            await XCTAssertThrowsErrorAsyncResearch(try await service.reply(history: [], newUserPrompt: "hi", in: [])) { error in
                guard case .serviceUnavailable = error as? AIResearchService.ChatError else {
                    return XCTFail("Expected .serviceUnavailable for HTTP \(status), got \(error)")
                }
            }
        }
    }

    /// The chat view reads `replyStream`, so it must surface the same
    /// typed errors as `reply` rather than a bare status code.
    func test_replyStream_rateLimited_throwsRateLimited() async {
        MockURLProtocol.handler = { request in
            (Self.response(for: request, status: 429), Data())
        }
        do {
            for try await _ in service.replyStream(history: [], newUserPrompt: "hi", in: []) {}
            XCTFail("Expected .rateLimited but the stream finished")
        } catch {
            guard case .rateLimited = error as? AIResearchService.ChatError else {
                return XCTFail("Expected .rateLimited, got \(error)")
            }
        }
    }

    func test_reply_dailyQuota429_throwsDailyLimitReached() async {
        MockURLProtocol.handler = { request in
            (Self.response(for: request, status: 429), Data(#"{"error":{"message":"Daily limit reached","code":"daily_quota"}}"#.utf8))
        }
        await XCTAssertThrowsErrorAsyncResearch(try await service.reply(history: [], newUserPrompt: "hi", in: [])) { error in
            guard case .dailyLimitReached = error as? AIResearchService.ChatError else {
                return XCTFail("Expected .dailyLimitReached, got \(error)")
            }
        }
    }

    /// The chat view uses `replyStream`, so the daily quota has to be told
    /// apart on the streaming path too, not only on `reply`.
    func test_replyStream_dailyQuota429_throwsDailyLimitReached() async {
        MockURLProtocol.handler = { request in
            (Self.response(for: request, status: 429), Data(#"{"error":{"message":"Daily limit reached","code":"daily_quota"}}"#.utf8))
        }
        do {
            for try await _ in service.replyStream(history: [], newUserPrompt: "hi", in: []) {}
            XCTFail("Expected .dailyLimitReached, got a completed stream")
        } catch {
            guard case .dailyLimitReached = error as? AIResearchService.ChatError else {
                return XCTFail("Expected .dailyLimitReached, got \(error)")
            }
        }
    }

    func test_reply_perMinute429_throwsRateLimited() async {
        MockURLProtocol.handler = { request in
            (Self.response(for: request, status: 429), Data(#"{"error":{"message":"Too many requests","code":"rate_limited"}}"#.utf8))
        }
        await XCTAssertThrowsErrorAsyncResearch(try await service.reply(history: [], newUserPrompt: "hi", in: [])) { error in
            guard case .rateLimited = error as? AIResearchService.ChatError else {
                return XCTFail("Expected .rateLimited, got \(error)")
            }
        }
    }

    func test_reply_throwsUnauthorisedOn401() async {
        MockURLProtocol.handler = { request in
            (Self.response(for: request, status: 401), Data())
        }
        await XCTAssertThrowsErrorAsyncResearch(try await service.reply(history: [], newUserPrompt: "hi", in: [])) { error in
            guard case .unauthorised = error as? AIResearchService.ChatError else {
                XCTFail("Expected .unauthorised, got \(error)")
                return
            }
            let description = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertFalse(description.lowercased().contains("anthropic"))
            XCTAssertFalse(description.contains("401"))
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

    static let truncatedReply = """
    {
      "content": [
        { "type": "text", "text": "BPC-157 has been studied in" }
      ],
      "stop_reason": "max_tokens"
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
