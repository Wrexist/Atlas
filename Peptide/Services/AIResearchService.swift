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
            // Build-config detail belongs in the log, not in front of
            // customers; they only need to know the assistant is down.
            case .proxyNotConfigured:   String(localized: "The research assistant isn't available right now. Update Atlas or try again later.")
            case .unauthorised:         String(localized: "Couldn't sign in to the research assistant. This build's credentials were rejected — update to the latest version from TestFlight or the App Store, or contact support if you're already on the newest build.")
            case .offline:              String(localized: "You're offline — the research assistant needs an internet connection. Reconnect and try again.")
            case .rateLimited:          String(localized: "You're sending questions faster than the assistant can answer. Wait a minute and try again.")
            case .serviceUnavailable:   String(localized: "The research assistant is temporarily offline. Try again in a few minutes.")
            case .requestFailed(let m): m
            case .invalidResponse:      String(localized: "The assistant returned an unexpected response.")
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

    /// `reply` as a stream for the chat view, which reads it with
    /// `for try await` so Stop or a newer question cancels the request.
    /// The proxy answers with one buffered JSON reply, so the whole text
    /// arrives as a single chunk.
    func replyStream(
        history: [Turn],
        newUserPrompt prompt: String,
        in database: [Peptide]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [self] in
                do {
                    let text = try await reply(history: history, newUserPrompt: prompt, in: database)
                    if !text.isEmpty { continuation.yield(text) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
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
                AppLog.ai.error(
                    "AI research not configured: AI_RESEARCH_ENDPOINT is empty in Info.plist + env."
                )
            }
            if proxySecret == nil || proxySecret?.isEmpty == true {
                AppLog.ai.error(
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

    /// The proxy keeps only the first 4000 UTF-16 units of the client
    /// `system` (`raw.system.slice(0, 4000)` in anthropic-proxy.js), so
    /// anything past this is silently cut.
    static let systemCharacterBudget = 4000

    /// Per-field cap on the long prose fields, so one verbose entry can't
    /// crowd the other mentioned compounds out of the budget.
    private static let snippetFieldLimit = 400

    private static let ragContextHeader = "Database context for the compounds the user mentioned:"

    /// Picks up to 4 peptides whose name or abbreviation appears in the
    /// recent transcript (case-insensitive substring match), then keeps
    /// whole entries only while they fit the proxy's system budget.
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
            if !p.description.isEmpty { fields.append("Summary: \(Self.clipped(p.description, to: Self.snippetFieldLimit))") }
            if !p.dosageRange.isEmpty { fields.append("Dosage range: \(p.dosageRange)") }
            if !p.frequency.isEmpty   { fields.append("Frequency: \(p.frequency)") }
            if !p.halfLife.isEmpty    { fields.append("Half-life: \(p.halfLife)") }
            if !p.adminRoute.isEmpty  { fields.append("Admin route: \(p.adminRoute)") }
            if !p.mechanism.isEmpty   { fields.append("Mechanism: \(Self.clipped(p.mechanism, to: Self.snippetFieldLimit))") }
            if !p.contraindications.isEmpty {
                fields.append("Contraindications: \(p.contraindications.joined(separator: "; "))")
            }
            if !p.researchLinks.isEmpty {
                let cites = p.researchLinks.prefix(3).map { "[\($0.year)] \($0.title) — \($0.source)" }
                fields.append("Citations: \(cites.joined(separator: " | "))")
            }
            return fields.joined(separator: "\n")
        }

        let budget = Self.systemCharacterBudget - Self.ragContextHeader.utf16.count - 1
        var context = ""
        for snippet in snippets {
            let candidate = context.isEmpty ? snippet : context + "\n\n---\n\n" + snippet
            if candidate.utf16.count > budget { break }
            context = candidate
        }
        return context.isEmpty ? Self.clipped(snippets[0], to: budget) : context
    }

    /// `text` cut to at most `limit` UTF-16 units (the unit the proxy's
    /// slice counts), ending in an ellipsis when cut.
    private static func clipped(_ text: String, to limit: Int) -> String {
        guard text.utf16.count > limit else { return text }
        var result = ""
        var used = 0
        for character in text {
            let width = character.utf16.count
            if used + width > limit - 1 { break }
            used += width
            result.append(character)
        }
        return result + "…"
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
        // The Messages API needs the conversation to open on a user
        // turn, and an even-length suffix of an alternating history
        // starts on an assistant one.
        let trimmed = history
            .filter { !$0.content.isEmpty }
            .suffix(Self.maxHistoryTurns)
            .drop(while: { $0.role == .assistant })
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

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 800,
            "messages": messages,
        ]
        // The proxy prepends the authoritative persona and safety rules,
        // so the client sends only the grounding context.
        if let ragContext {
            body["system"] = Self.ragContextHeader + "\n" + ragContext
        }
        return body
    }

    private func parseAssistantText(from data: Data) throws -> String {
        let envelopeObject: Any
        do {
            envelopeObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            // Log before collapsing to a generic error so a server-side
            // response-shape regression is diagnosable from a device.
            AppLog.ai.error(
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
