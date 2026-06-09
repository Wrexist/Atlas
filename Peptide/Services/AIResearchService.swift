import Foundation

/// Chat-style research assistant. Sends RAG-augmented prompts to the
/// Atlas server proxy (which holds the Anthropic key); the iOS
/// client never sees the API key. Endpoint + shared secret are
/// configured via `AI_RESEARCH_ENDPOINT` and `AI_RESEARCH_SECRET` —
/// same pattern as `MealScannerService`. The direct-Anthropic
/// fallback was removed; builds without a configured proxy throw
/// `ChatError.proxyNotConfigured` so the failure is visible.
///
/// RAG strategy: rather than ship a vector store, we substring-match
/// the user's question against the bundled peptide database (208
/// entries) and inject the matching peptides' description, half-life,
/// dosage range, mechanism, contraindications, and citations into the
/// system prompt. That gives Claude grounded context without us
/// having to pull in an embedding stack.
final class AIResearchService: Sendable {
    static let shared = AIResearchService()

    private let session: URLSession
    private let model = "claude-sonnet-4-6"
    private let endpointOverride: URL?
    private let proxySecretOverride: String?

    /// Designated init — see `MealScannerService.init` for the same
    /// pattern. Production goes through `.shared`; tests pass a
    /// `URLSession` configured with a `MockURLProtocol`.
    init(
        session: URLSession = .shared,
        endpoint: URL? = nil,
        proxySecret: String? = nil
    ) {
        self.session = session
        self.endpointOverride = endpoint
        self.proxySecretOverride = proxySecret
    }

    private var endpoint: URL? {
        endpointOverride ?? MealScannerService.urlSetting(forKey: "AI_RESEARCH_ENDPOINT")
    }

    private var proxySecret: String? {
        proxySecretOverride ?? MealScannerService.stringSetting(forKey: "AI_RESEARCH_SECRET")
    }

    enum ChatError: Error, LocalizedError {
        case proxyNotConfigured
        case unauthorised
        case offline
        case rateLimited
        case serviceUnavailable
        case requestFailed(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .proxyNotConfigured:   "AI research isn't configured for this build. Set AI_RESEARCH_ENDPOINT and AI_RESEARCH_SECRET in Secrets.xcconfig and rebuild."
            case .unauthorised:         "Couldn't sign in to the research assistant. This build's credentials were rejected — update to the latest version from TestFlight or the App Store, or contact support if you're already on the newest build."
            case .offline:              "You're offline — the research assistant needs an internet connection. Reconnect and try again."
            case .rateLimited:          "You're sending questions faster than the assistant can answer. Wait a minute and try again."
            case .serviceUnavailable:   "The research assistant is temporarily offline. Try again in a few minutes."
            case .requestFailed(let m): m
            case .invalidResponse:      "The assistant returned an unexpected response."
            }
        }
    }

    /// Maps a transport-layer `URLError` to a typed `ChatError`:
    /// offline codes become `.offline` (actionable copy), transient
    /// connection failures become `.serviceUnavailable`; anything
    /// else is returned unchanged.
    private func mapTransport(_ error: Error) -> Error {
        guard let urlError = error as? URLError else { return error }
        switch urlError.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return ChatError.offline
        case .timedOut, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed:
            return ChatError.serviceUnavailable
        default:
            return error
        }
    }

    struct Turn: Identifiable, Hashable, Codable {
        enum Role: String, Codable { case user, assistant }
        let id: UUID
        let role: Role
        var content: String
        let createdAt: Date

        init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = Date()) {
            self.id = id
            self.role = role
            self.content = content
            self.createdAt = createdAt
        }
    }

    /// Streaming companion to `reply` — emits partial text chunks as
    /// they arrive from the proxy's SSE stream. The client appends
    /// each chunk to the in-progress assistant turn so the user sees
    /// tokens land in real time (audit AI Research P2). When the
    /// proxy hasn't been upgraded to SSE the buffered response is
    /// yielded as a single chunk, so the call site degrades cleanly.
    func replyStream(
        history: [Turn],
        newUserPrompt prompt: String,
        in database: [Peptide]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [self] in
                do {
                    try await streamReply(
                        history: history,
                        prompt: prompt,
                        database: database,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func streamReply(
        history: [Turn],
        prompt: String,
        database: [Peptide],
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        guard let endpoint, let proxySecret, !proxySecret.isEmpty else {
            throw ChatError.proxyNotConfigured
        }
        let context = ragContext(for: prompt, history: history, in: database)
        var body = payload(history: history, newPrompt: prompt, ragContext: context)
        body["stream"] = true

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(proxySecret, forHTTPHeaderField: "X-Peptide-Proxy")
        // App Attest assertion — see AppAttestService; absence falls
        // back to secret-only auth.
        if let attestHeaders = await AppAttestService.shared.assertionHeaders() {
            for (field, value) in attestHeaders {
                request.setValue(value, forHTTPHeaderField: field)
            }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw mapTransport(error)
        }
        guard let http = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw ChatError.unauthorised }
            throw ChatError.requestFailed("AI research returned HTTP \(http.statusCode).")
        }

        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if !contentType.contains("text/event-stream") {
            // Proxy didn't honor stream:true (older deploy). Buffer the body
            // and yield the full text as a single chunk so the caller still
            // sees the reply land — just without per-token animation.
            var buffer = Data()
            for try await byte in bytes { buffer.append(byte) }
            let text = try parseAssistantText(from: buffer)
            if !text.isEmpty { continuation.yield(text) }
            return
        }

        // Anthropic SSE: each event is "event: <name>\n" plus "data: <json>\n\n".
        // We only consume `data:` lines and parse the `content_block_delta`
        // events whose `delta.text` carries the streamed tokens.
        for try await line in bytes.lines {
            try Task.checkCancellation()
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { continue }
            let payloadString = String(trimmed.dropFirst("data:".count))
                .trimmingCharacters(in: .whitespaces)
            if payloadString.isEmpty || payloadString == "[DONE]" { continue }
            guard let data = payloadString.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let type = dict["type"] as? String
            if type == "content_block_delta",
               let delta = dict["delta"] as? [String: Any],
               let text = delta["text"] as? String,
               !text.isEmpty {
                continuation.yield(text)
            } else if type == "message_stop" {
                return
            } else if type == "error" {
                // Surface even when the upstream `error` event omits a
                // `message` string — otherwise the stream ends silently
                // and the view's empty-bubble cleanup leaves the user
                // staring at no answer + no error (audit AI Research
                // P2 follow-up).
                let err = dict["error"] as? [String: Any]
                let message = (err?["message"] as? String).map { $0.isEmpty ? nil : $0 } ?? nil
                throw ChatError.requestFailed(
                    message ?? "The research assistant returned an unspecified error."
                )
            }
        }
    }

    /// Sends `history` (conversation so far) plus the user's new
    /// `prompt` and returns the assistant's text. The system prompt
    /// is rebuilt each call so the RAG context reflects whatever the
    /// latest message mentions.
    func reply(
        history: [Turn],
        newUserPrompt prompt: String,
        in database: [Peptide]
    ) async throws -> String {
        guard let endpoint, let proxySecret, !proxySecret.isEmpty else {
            // Mirror MealScannerService: keep the public error generic but
            // log which side is missing so misconfigurations are
            // diagnosable from Console.app on a TestFlight device.
            if endpoint == nil {
                AppLog.persistence.error(
                    "AI research not configured: AI_RESEARCH_ENDPOINT is empty in Info.plist + env."
                )
            }
            if proxySecret == nil || proxySecret?.isEmpty == true {
                AppLog.persistence.error(
                    "AI research not configured: AI_RESEARCH_SECRET is empty in Info.plist + env."
                )
            }
            throw ChatError.proxyNotConfigured
        }

        let context = ragContext(for: prompt, history: history, in: database)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(proxySecret, forHTTPHeaderField: "X-Peptide-Proxy")
        // App Attest assertion — see AppAttestService; absence falls
        // back to secret-only auth.
        if let attestHeaders = await AppAttestService.shared.assertionHeaders() {
            for (field, value) in attestHeaders {
                request.setValue(value, forHTTPHeaderField: field)
            }
        }
        request.httpBody = try JSONSerialization.data(
            withJSONObject: payload(history: history, newPrompt: prompt, ragContext: context),
            options: []
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw mapTransport(error)
        }
        guard let http = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            // Don't echo upstream body — Anthropic auth-failure responses
            // include masked-key fingerprints that the user shouldn't see.
            // 401 is broken out from the generic requestFailed envelope so
            // the user sees an actionable message rather than a bare HTTP
            // status code.
            switch http.statusCode {
            case 401:                throw ChatError.unauthorised
            case 429:                throw ChatError.rateLimited
            case 502, 503, 504:      throw ChatError.serviceUnavailable
            default:                 throw ChatError.requestFailed("AI research returned HTTP \(http.statusCode).")
            }
        }

        return try parseAssistantText(from: data)
    }

    // MARK: - RAG

    /// Picks up to 4 peptides whose name or abbreviation appears in the
    /// recent transcript (case-insensitive substring match). Caps the
    /// injected context at 4 so the system prompt stays well under
    /// Claude's input limits even with verbose entries.
    private func ragContext(
        for prompt: String,
        history: [Turn],
        in database: [Peptide]
    ) -> String? {
        let recentText = ([prompt] + history.suffix(4).map(\.content))
            .joined(separator: " ")
            .lowercased()

        var picks: [Peptide] = []
        for peptide in database {
            if picks.count >= 4 { break }
            // Skip 1-2 character needles ("T3", "GH") that would
            // collide with common English substrings ("with", "the").
            // The short-abbreviation false positives polluted the
            // system prompt with irrelevant peptide data and burned
            // token budget. Names are usually long enough; abbreviations
            // shorter than 3 chars require an exact word-boundary match
            // via the recentText words.
            let name = peptide.name.lowercased()
            let abbr = peptide.abbreviation.lowercased()
            let matchesName = name.count >= 3 && recentText.contains(name)
            let matchesAbbr: Bool = {
                guard !abbr.isEmpty else { return false }
                if abbr.count >= 3 { return recentText.contains(abbr) }
                // Short abbreviation: require it to appear as a whole token.
                let tokens = recentText.split { !$0.isLetter && !$0.isNumber }
                return tokens.contains { $0.lowercased() == abbr }
            }()
            if matchesName || matchesAbbr {
                picks.append(peptide)
            }
        }
        guard !picks.isEmpty else { return nil }

        let snippets = picks.map { p -> String in
            var fields: [String] = [
                "Name: \(p.name) (\(p.abbreviation))",
                "Category: \(p.category.rawValue)",
            ]
            if !p.description.isEmpty { fields.append("Summary: \(p.description)") }
            if !p.dosageRange.isEmpty { fields.append("Dosage range: \(p.dosageRange)") }
            if !p.frequency.isEmpty   { fields.append("Frequency: \(p.frequency)") }
            if !p.halfLife.isEmpty    { fields.append("Half-life: \(p.halfLife)") }
            if !p.adminRoute.isEmpty  { fields.append("Admin route: \(p.adminRoute)") }
            if !p.mechanism.isEmpty   { fields.append("Mechanism: \(p.mechanism)") }
            if !p.contraindications.isEmpty {
                fields.append("Contraindications: \(p.contraindications.joined(separator: "; "))")
            }
            if !p.researchLinks.isEmpty {
                let cites = p.researchLinks.prefix(3).map { "[\($0.year)] \($0.title) — \($0.source)" }
                fields.append("Citations: \(cites.joined(separator: " | "))")
            }
            return fields.joined(separator: "\n")
        }
        return snippets.joined(separator: "\n\n---\n\n")
    }

    /// Server-side cap (`MAX_MESSAGES` in anthropic-proxy.js). The
    /// proxy hard-rejects requests above this, so we trim the oldest
    /// turns to keep the conversation alive past long research
    /// sessions. Set one below the server ceiling to leave headroom
    /// for the new user turn we always append below.
    private static let maxHistoryTurns: Int = 39

    private func payload(
        history: [Turn],
        newPrompt: String,
        ragContext: String?
    ) -> [String: Any] {
        // Drop the oldest turns once the conversation grows past the
        // server's per-request message cap. Without this trim, sessions
        // longer than ~20 user/assistant exchanges silently fail with
        // an opaque "Malformed request body" from the proxy.
        let trimmed = history.suffix(Self.maxHistoryTurns)
        var messages: [[String: Any]] = trimmed.map { turn in
            [
                "role": turn.role.rawValue,
                "content": turn.content,
            ] as [String: Any]
        }
        messages.append([
            "role": "user",
            "content": newPrompt,
        ] as [String: Any])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 800,
            "system": systemPrompt(ragContext: ragContext),
            "messages": messages,
        ]
        return body
    }

    private func systemPrompt(ragContext: String?) -> String {
        var lines: [String] = [
            "You are Atlas's research assistant — a careful, citation-friendly explainer of peptide science.",
            "",
            "Rules:",
            "• Never recommend, prescribe, or calculate doses. Refer the user to a qualified clinician for any dose decision.",
            "• When you cite a number from the references below, attribute it (e.g. 'per the Smith 2021 study').",
            "• If the user asks for medical advice, decline politely and remind them you're an educational reference.",
            "• Keep replies under ~250 words unless the user explicitly asks for depth.",
            "• If the database context doesn't cover the question, say so plainly rather than guessing.",
        ]
        if let ragContext, !ragContext.isEmpty {
            lines.append("")
            lines.append("Database context for the compounds the user mentioned:")
            lines.append(ragContext)
        }
        return lines.joined(separator: "\n")
    }

    private func parseAssistantText(from data: Data) throws -> String {
        let envelopeObject: Any
        do {
            envelopeObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            // Log before collapsing to a generic error so a server-side
            // response-shape regression is diagnosable from a device.
            AppLog.persistence.error(
                "AI research envelope decode failed: \(error.localizedDescription, privacy: .private)"
            )
            throw ChatError.invalidResponse
        }
        guard
            let envelope = envelopeObject as? [String: Any],
            let content = envelope["content"] as? [[String: Any]],
            let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String
        else {
            throw ChatError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
