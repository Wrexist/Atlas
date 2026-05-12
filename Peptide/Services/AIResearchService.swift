import Foundation

/// Chat-style research assistant. Sends RAG-augmented prompts to the
/// PeptideX server proxy (which holds the Anthropic key); the iOS
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
        case requestFailed(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .proxyNotConfigured:   "AI research isn't configured for this build. Set AI_RESEARCH_ENDPOINT and AI_RESEARCH_SECRET in Secrets.xcconfig and rebuild."
            case .requestFailed(let m): m
            case .invalidResponse:      "The assistant returned an unexpected response."
            }
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
            throw ChatError.proxyNotConfigured
        }

        let context = ragContext(for: prompt, history: history, in: database)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(proxySecret, forHTTPHeaderField: "X-Peptide-Proxy")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: payload(history: history, newPrompt: prompt, ragContext: context),
            options: []
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            // Don't echo upstream body — Anthropic auth-failure responses
            // include masked-key fingerprints that the user shouldn't see.
            throw ChatError.requestFailed("AI research returned HTTP \(http.statusCode).")
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
            let needles = [peptide.name.lowercased(), peptide.abbreviation.lowercased()]
            if needles.contains(where: { !$0.isEmpty && recentText.contains($0) }) {
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

    private func payload(
        history: [Turn],
        newPrompt: String,
        ragContext: String?
    ) -> [String: Any] {
        var messages: [[String: Any]] = history.map { turn in
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
            "You are PeptideX's research assistant — a careful, citation-friendly explainer of peptide science.",
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
        guard
            let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = envelope["content"] as? [[String: Any]],
            let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String
        else {
            throw ChatError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
