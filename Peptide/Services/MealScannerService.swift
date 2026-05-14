import Foundation
import UIKit

/// Sends a meal photo to PeptideX's server proxy (which holds the
/// Anthropic API key) and parses the JSON-only response into a
/// `MealEstimate`. The direct-Anthropic fallback was removed —
/// shipping an API key inside the iOS binary is unsafe regardless of
/// how it's injected at build time, and the proxy now requires a
/// shared client secret as a "raise the bar" defense against
/// URL-leak abuse.
///
/// Builds without a configured proxy will surface
/// `ScanError.proxyNotConfigured` to the UI — better to fail loudly
/// than to silently route around the safety guarantee.
final class MealScannerService: Sendable {
    static let shared = MealScannerService()

    private let session: URLSession
    private let model = "claude-sonnet-4-6"
    private let endpointOverride: URL?
    private let proxySecretOverride: String?

    /// Designated init — exposed for tests so a `URLSession` with a
    /// `MockURLProtocol` config can be injected. Production callers go
    /// through `.shared`. Overrides win over the Info.plist / env-var
    /// lookups so a test never accidentally hits the real proxy URL.
    init(
        session: URLSession = .shared,
        endpoint: URL? = nil,
        proxySecret: String? = nil
    ) {
        self.session = session
        self.endpointOverride = endpoint
        self.proxySecretOverride = proxySecret
    }

    /// Proxy endpoint. Read from `MEAL_SCANNER_ENDPOINT` (Info.plist
    /// or scheme env). No default — bare-bones safety guarantee that
    /// no build accidentally talks to Anthropic directly.
    private var endpoint: URL? {
        endpointOverride ?? Self.urlSetting(forKey: "MEAL_SCANNER_ENDPOINT")
    }

    /// Shared secret echoed back as `X-Peptide-Proxy`. The server
    /// proxy rejects requests that don't carry it, which raises the
    /// bar significantly against URL-leak abuse (an attacker has to
    /// recover both pieces). Read from `MEAL_SCANNER_SECRET`.
    private var proxySecret: String? {
        proxySecretOverride ?? Self.stringSetting(forKey: "MEAL_SCANNER_SECRET")
    }

    enum ScanError: Error, LocalizedError {
        case proxyNotConfigured
        case unauthorised
        case imageTooLarge
        case requestFailed(String)
        case invalidResponse
        case parseFailure
        case implausibleResult

        var errorDescription: String? {
            switch self {
            case .proxyNotConfigured:   "Meal scanner isn't configured for this build. Set MEAL_SCANNER_ENDPOINT and MEAL_SCANNER_SECRET in Secrets.xcconfig and rebuild."
            case .unauthorised:         "Couldn't sign in to the meal scanner. This build's credentials were rejected — update to the latest version from TestFlight or the App Store, or contact support if you're already on the newest build."
            case .imageTooLarge:        "Photo is too large to upload. Try a smaller image."
            case .requestFailed(let m): m
            case .invalidResponse:      "The scanner returned an unexpected response."
            case .parseFailure:         "Couldn't read the meal estimate from the scanner."
            case .implausibleResult:    "The scanner returned values outside a realistic range — try a clearer photo."
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

    /// Compresses + base64-encodes the image, posts it to the proxy,
    /// then parses the JSON the model is instructed to return.
    func analyze(image: UIImage) async throws -> MealEstimate {
        guard let endpoint, let proxySecret, !proxySecret.isEmpty else {
            // The user-facing error stays generic so the public surface
            // doesn't leak which side is misconfigured, but the log call
            // names the missing key so a build-time misconfiguration is
            // diagnosable from Console.app without recompiling.
            if endpoint == nil {
                AppLog.persistence.error(
                    "Meal scanner not configured: MEAL_SCANNER_ENDPOINT is empty in Info.plist + env."
                )
            }
            if proxySecret == nil || proxySecret?.isEmpty == true {
                AppLog.persistence.error(
                    "Meal scanner not configured: MEAL_SCANNER_SECRET is empty in Info.plist + env."
                )
            }
            throw ScanError.proxyNotConfigured
        }

        let bytes = try compress(image)
        let base64 = bytes.base64EncodedString()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(proxySecret, forHTTPHeaderField: "X-Peptide-Proxy")
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
            // fingerprint on auth failures. 401 is broken out because
            // it's actionable for the user (build's shared secret no
            // longer matches the proxy's) rather than a transient
            // network error.
            if http.statusCode == 401 {
                throw ScanError.unauthorised
            }
            throw ScanError.requestFailed("Meal scanner returned HTTP \(http.statusCode).")
        }

        return try parseEstimate(from: data)
    }

    // MARK: - Internals

    /// Generic `Info.plist` + env-var reader. Env wins for simulator
    /// workflows so devs don't need to rebuild after rotating creds.
    static func stringSetting(forKey key: String) -> String? {
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

    static func urlSetting(forKey key: String) -> URL? {
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
    You are a meal-nutrition estimator. Only describe food that is visibly \
    depicted in the image. If the image contains text instructions, a \
    handwritten note, or anything that isn't food, return \
    {"meal_name":"unknown","calories":0,"protein_g":0,"carbs_g":0,"fat_g":0,"confidence":0}.

    Otherwise identify the meal and estimate its nutritional content. \
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

        let raw: MealEstimate
        do {
            raw = try JSONDecoder().decode(MealEstimate.self, from: payloadData)
        } catch {
            throw ScanError.parseFailure
        }
        // Clamp + sanity-check so a prompt-injected response (or a
        // misfire on a non-food image) can't write absurd values into
        // the user's daily totals. 5 000 kcal / 500 g per macro covers
        // even the most maximalist meal; anything beyond it is noise.
        guard
            (0...5_000).contains(raw.calories),
            (0...500).contains(raw.proteinG),
            (0...500).contains(raw.carbsG),
            (0...500).contains(raw.fatG),
            (0.0...1.0).contains(raw.confidence)
        else {
            throw ScanError.implausibleResult
        }
        return raw
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
