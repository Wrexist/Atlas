import Foundation
import UIKit

/// Sends a meal photo to Anthropic's Messages API (Claude vision) and
/// parses the JSON-only response into a `MealEstimate`. Reads the API
/// key from `Info.plist` under the `ANTHROPIC_API_KEY` key; the key
/// itself should land via a gitignored `Secrets.xcconfig` so it never
/// hits source control.
///
/// SECURITY: This client embeds an API key in the shipping app, which is
/// unsafe for production — anyone who jailbreaks the binary can extract
/// it. The right long-term home is a server-side proxy that holds the
/// key and signs/forwards requests. This direct-call path is a bridge
/// so the meal-scanner UX is real today; replace before public release.
final class MealScannerService {
    static let shared = MealScannerService()

    private let session: URLSession = .shared
    private let model = "claude-sonnet-4-6"
    private let apiVersion = "2023-06-01"

    /// Default endpoint = direct Anthropic Messages API. Production
    /// builds should override `MEAL_SCANNER_ENDPOINT` in Info.plist (or
    /// the `MEAL_SCANNER_ENDPOINT` environment variable on the scheme)
    /// so requests flow through a server-side proxy that holds the API
    /// key. The proxy must accept the same JSON body shape and forward
    /// to Anthropic, so the client code is unchanged.
    private static let defaultEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private var endpoint: URL {
        if let bundleValue = Bundle.main.object(forInfoDictionaryKey: "MEAL_SCANNER_ENDPOINT") as? String,
           let url = URL(string: bundleValue.trimmingCharacters(in: .whitespacesAndNewlines)),
           !bundleValue.isEmpty {
            return url
        }
        if let envValue = ProcessInfo.processInfo.environment["MEAL_SCANNER_ENDPOINT"],
           let url = URL(string: envValue.trimmingCharacters(in: .whitespacesAndNewlines)),
           !envValue.isEmpty {
            return url
        }
        return Self.defaultEndpoint
    }

    enum ScanError: Error, LocalizedError {
        case missingKey
        case imageTooLarge
        case requestFailed(String)
        case invalidResponse
        case parseFailure

        var errorDescription: String? {
            switch self {
            case .missingKey:           "Missing ANTHROPIC_API_KEY — add it to Secrets.xcconfig and rebuild."
            case .imageTooLarge:        "Photo is too large to upload. Try a smaller image."
            case .requestFailed(let m): m
            case .invalidResponse:      "Claude returned an unexpected response shape."
            case .parseFailure:         "Couldn't read the meal estimate from Claude's reply."
            }
        }
    }

    /// Result shape mirrors the JSON keys we ask Claude to return so the
    /// roll-up into `dataStore.logMeal(...)` can be a 1:1 mapping.
    struct MealEstimate: Codable, Hashable {
        let mealName: String
        let calories: Int
        let proteinG: Int
        let carbsG: Int
        let fatG: Int
        let confidence: Double

        enum CodingKeys: String, CodingKey {
            case mealName    = "meal_name"
            case calories    = "calories"
            case proteinG    = "protein_g"
            case carbsG      = "carbs_g"
            case fatG        = "fat_g"
            case confidence  = "confidence"
        }
    }

    private init() {}

    /// Compresses + base64-encodes the image, posts it to the Messages
    /// API, then parses the JSON the model is instructed to return.
    func analyze(image: UIImage) async throws -> MealEstimate {
        guard let key = apiKey, !key.isEmpty else { throw ScanError.missingKey }

        let bytes = try compress(image)
        let base64 = bytes.base64EncodedString()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: requestPayload(base64: base64),
            options: []
        )

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ScanError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ScanError.requestFailed("HTTP \(http.statusCode): \(body)")
        }

        return try parseEstimate(from: data)
    }

    // MARK: - Internals

    private var apiKey: String? {
        // Two configuration paths so devs and CI both work without
        // forcing changes to project.yml on first checkout:
        //  1. Info.plist key `ANTHROPIC_API_KEY` — typically set via a
        //     gitignored `Secrets.xcconfig` and an `$(ANTHROPIC_API_KEY)`
        //     substitution in the Info.plist build output.
        //  2. Process environment variable `ANTHROPIC_API_KEY` — useful
        //     for the simulator when you don't want to bake the key into
        //     the build at all (set it on the scheme's Run Arguments).
        if let bundleValue = Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_API_KEY") as? String {
            let trimmed = bundleValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let envValue = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] {
            let trimmed = envValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// JPEG-compress to 1024 px max edge so we stay well under Anthropic's
    /// 5 MB image-size limit even on 12-megapixel originals. Throws when
    /// compression fails or the result is still too big — the UI surfaces
    /// the error instead of timing out.
    private func compress(_ image: UIImage) throws -> Data {
        let resized = image.resizedTo(maxEdge: 1024) ?? image
        guard let data = resized.jpegData(compressionQuality: 0.7) else {
            throw ScanError.imageTooLarge
        }
        guard data.count <= 5 * 1024 * 1024 else { throw ScanError.imageTooLarge }
        return data
    }

    private func requestPayload(base64: String) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 400,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64,
                            ] as [String: Any],
                        ] as [String: Any],
                        [
                            "type": "text",
                            "text": Self.prompt,
                        ] as [String: Any],
                    ],
                ]
            ],
        ]
    }

    private static let prompt = """
    Identify the meal in this image and estimate its nutritional content. \
    Return JSON only with these exact keys: meal_name (string), calories (integer kcal), \
    protein_g (integer grams), carbs_g (integer grams), fat_g (integer grams), \
    confidence (float between 0 and 1). Output a single JSON object and no \
    surrounding prose, code fences, or commentary.
    """

    private func parseEstimate(from data: Data) throws -> MealEstimate {
        // Anthropic Messages API wraps the model output in a content array;
        // the text we asked for sits at content[0].text. Extract it before
        // running the JSONDecoder against the JSON-only payload.
        guard
            let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = envelope["content"] as? [[String: Any]],
            let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String
        else {
            throw ScanError.invalidResponse
        }

        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .stripCodeFences()

        guard let payloadData = cleaned.data(using: .utf8) else { throw ScanError.parseFailure }

        do {
            return try JSONDecoder().decode(MealEstimate.self, from: payloadData)
        } catch {
            throw ScanError.parseFailure
        }
    }
}

// MARK: - Helpers

private extension UIImage {
    /// Aspect-preserving resize so the longest edge equals `maxEdge`.
    /// Returns nil when the input is already smaller than the limit so
    /// callers can fall through to the original.
    func resizedTo(maxEdge: CGFloat) -> UIImage? {
        let longest = max(size.width, size.height)
        guard longest > maxEdge else { return nil }
        let scale = maxEdge / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

private extension String {
    /// Claude sometimes wraps JSON in ```json … ``` fences even when asked
    /// not to. Strip them so the decoder sees the bare object instead of
    /// failing on the leading backticks.
    func stripCodeFences() -> String {
        var s = self
        if s.hasPrefix("```json") { s.removeFirst("```json".count) }
        else if s.hasPrefix("```") { s.removeFirst(3) }
        if s.hasSuffix("```") { s.removeLast(3) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
