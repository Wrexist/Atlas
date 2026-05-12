import Foundation
import UIKit

/// Sends a meal photo to the PeptideX proxy (which holds the
/// Anthropic key server-side) and parses the JSON-only response into a
/// `MealEstimate`. The proxy URL is read from `MEAL_SCANNER_ENDPOINT`
/// in `Info.plist` (or the same env var on the scheme); a shared
/// client secret comes from `MEAL_SCANNER_SHARED_SECRET`.
///
/// Direct calls to `api.anthropic.com` are intentionally not supported
/// — embedding an Anthropic key in the shipping binary is unsafe
/// because anyone unzipping the IPA can recover it. The build will
/// fail loudly at runtime if the proxy endpoint isn't configured.
final class MealScannerService: Sendable {
    static let shared = MealScannerService()

    private let session: URLSession = .shared
    private let model = "claude-sonnet-4-6"

    /// Proxy URL is read from `MEAL_SCANNER_ENDPOINT` (Info.plist or
    /// scheme env). The proxy is mandatory — see the file-header
    /// comment for why.
    private var endpoint: URL? {
        Self.urlSetting(forKey: "MEAL_SCANNER_ENDPOINT")
    }

    /// Shared client secret sent as `x-peptide-key`. The proxy rejects
    /// requests that don't carry it, which raises the bar significantly
    /// against URL-leak abuse (someone has to recover both pieces).
    /// Read from `MEAL_SCANNER_SHARED_SECRET` (Info.plist or scheme env).
    private var sharedSecret: String? {
        Self.stringSetting(forKey: "MEAL_SCANNER_SHARED_SECRET")
    }

    enum ScanError: Error, LocalizedError {
        case proxyNotConfigured
        case imageTooLarge
        case requestFailed(String)
        case invalidResponse
        case parseFailure

        var errorDescription: String? {
            switch self {
            case .proxyNotConfigured:   "Meal scanner isn't configured for this build. Set MEAL_SCANNER_ENDPOINT and MEAL_SCANNER_SHARED_SECRET in Secrets.xcconfig and rebuild."
            case .imageTooLarge:        "Photo is too large to upload. Try a smaller image."
            case .requestFailed(let m): m
            case .invalidResponse:      "The scanner returned an unexpected response."
            case .parseFailure:         "Couldn't read the meal estimate from the scanner."
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

    /// Compresses + base64-encodes the image, posts it to the proxy,
    /// then parses the JSON the model is instructed to return.
    func analyze(image: UIImage) async throws -> MealEstimate {
        guard let endpoint, let sharedSecret, !sharedSecret.isEmpty else {
            throw ScanError.proxyNotConfigured
        }

        let bytes = try compress(image)
        let base64 = bytes.base64EncodedString()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sharedSecret, forHTTPHeaderField: "x-peptide-key")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: requestPayload(base64: base64),
            options: []
        )

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ScanError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            // Surface only the status code — never echo the upstream
            // response body, which can include the request id and key
            // fingerprint on auth failures.
            throw ScanError.requestFailed("Meal scanner returned HTTP \(http.statusCode).")
        }

        return try parseEstimate(from: data)
    }

    // MARK: - Internals

    /// Generic `Info.plist` + env-var reader. Used for both the proxy
    /// URL and the shared secret. Env wins for simulator workflows so
    /// devs don't need to rebuild after rotating credentials.
    private static func stringSetting(forKey key: String) -> String? {
        if let bundleValue = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            let trimmed = bundleValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let envValue = ProcessInfo.processInfo.environment[key] {
            let trimmed = envValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func urlSetting(forKey key: String) -> URL? {
        guard let raw = stringSetting(forKey: key), let url = URL(string: raw) else {
            return nil
        }
        return url
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
