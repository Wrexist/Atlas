import Foundation
import UIKit

/// Sends a meal photo to Atlas's server proxy (which holds the
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
    /// Vision quality is the whole product here — a scan that reads
    /// melon as tomato is worse than no scan, because the user trusts
    /// the number it writes into their day. Sonnet 5 is the current
    /// vision tier and the documented successor to 4.6.
    ///
    /// The proxy holds its own allowlist (`ALLOWED_MODELS`) and rewrites
    /// anything outside it to the first entry, so a deployment still
    /// pinned to 4.6 silently serves 4.6 rather than failing. That
    /// degradation is deliberate: the app keeps working, it just doesn't
    /// get the upgrade until the deployment's env var includes this ID.
    private let model = "claude-sonnet-5"
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
        case rateLimited
        case offline
        case imageTooLarge
        case requestFailed(String)
        case invalidResponse
        case parseFailure
        case implausibleResult
        case noFoodDetected

        var errorDescription: String? {
            switch self {
            case .proxyNotConfigured:   "Meal scanner isn't configured for this build. Set MEAL_SCANNER_ENDPOINT and MEAL_SCANNER_SECRET in Secrets.xcconfig and rebuild."
            case .unauthorised:         "Couldn't sign in to the meal scanner. This build's credentials were rejected — update to the latest version from TestFlight or the App Store, or contact support if you're already on the newest build."
            case .rateLimited:          "You've scanned a lot of meals recently. Wait a minute and try again — if you've hit today's limit, scanning resets tomorrow."
            case .offline:              "You're offline — meal scanning needs an internet connection. Reconnect and try again."
            case .imageTooLarge:        "Photo is too large to upload. Try a smaller image."
            case .requestFailed(let m): m
            case .invalidResponse:      "The scanner returned an unexpected response."
            case .parseFailure:         "Couldn't read the meal estimate from the scanner."
            case .implausibleResult:    "The scanner returned values outside a realistic range — try a clearer photo."
            case .noFoodDetected:       "No food found in that photo — point the camera at your meal and try again."
            }
        }
    }

    /// 5xx statuses worth one retry — a transient proxy / upstream
    /// hiccup rather than a client error.
    private static let retryableStatuses: Set<Int> = [502, 503, 504]
    /// URLError codes that mean "no usable connection" — surfaced as a
    /// dedicated `.offline` so the UI shows actionable copy.
    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff
    ]
    /// URLError codes worth one retry before giving up.
    private static let transientCodes: Set<URLError.Code> = [
        .timedOut, .networkConnectionLost, .cannotConnectToHost,
        .cannotFindHost, .dnsLookupFailed
    ]

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

    /// One distinct food/drink the model picked out of the photo. The
    /// multi-item counterpart to `MealEstimate` — `analyzeItems` returns
    /// these so the review UI can let the user tweak each portion and
    /// drop misfires before logging. `grams` is the model's estimate of
    /// the *depicted* portion's weight, which the review UI divides out
    /// into a per-100g basis so the quantity stepper can rescale macros.
    struct ScannedFoodItem: Codable, Hashable, Identifiable {
        /// Local identity for the editable list. Not part of the model
        /// payload — defaulted here and skipped by `CodingKeys`.
        let id = UUID()
        let name: String
        /// Human serving description, e.g. "1 can (330 ml)".
        let quantityLabel: String
        /// Estimated weight of the shown portion, grams.
        let grams: Double
        let calories: Int
        let proteinG: Int
        let carbsG: Int
        let fatG: Int
        let confidence: Double

        enum CodingKeys: String, CodingKey {
            case name, grams, calories, confidence
            case quantityLabel = "quantity_label"
            case proteinG      = "protein_g"
            case carbsG        = "carbs_g"
            case fatG          = "fat_g"
        }
    }

    private struct ItemsEnvelope: Codable {
        let items: [ScannedFoodItem]
        /// Name for the plate as a whole when the items clearly form one
        /// dish. Nil for a tray of unrelated things.
        let mealName: String?

        enum CodingKeys: String, CodingKey {
            case items
            case mealName = "meal_name"
        }
    }

    /// What a photo scan came back with: the individual items, plus a name
    /// for the dish they add up to when they add up to one.
    ///
    /// Spaghetti and a bolognese sauce are two rows the user may want to
    /// re-portion separately, *and* one meal called "Spaghetti Bolognese"
    /// they may want in their diary as a single line. The scanner returns
    /// both readings and the review screen lets the user pick.
    struct ScannedMeal {
        let items: [ScannedFoodItem]
        let mealName: String?
    }

    /// Single-aggregate estimate for the whole plate. Retained for the
    /// existing callers + test suite; the photo review UI now prefers
    /// `analyzeItems(image:)` for per-item editing.
    func analyze(image: UIImage) async throws -> MealEstimate {
        let data = try await performVision(image: image, prompt: Self.prompt)
        return try parseEstimate(from: data)
    }

    /// Per-item breakdown of the photo — each distinct food/drink the
    /// model can see, so the review UI can let the user adjust portions
    /// and drop misfires before logging.
    func analyzeItems(image: UIImage) async throws -> ScannedMeal {
        let data = try await performVision(image: image, prompt: Self.itemsPrompt)
        return try parseItems(from: data)
    }

    /// Compresses + base64-encodes the image, posts it to the proxy with
    /// the given prompt, validates the HTTP status, and hands back the
    /// raw response body for a caller-specific parse.
    private func performVision(image: UIImage, prompt: String) async throws -> Data {
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
        // 60s, not 30. This covers the upload as well as the model's
        // thinking time, and the photo we send is now several times
        // larger than it was — on a weak cellular link the old ceiling
        // would have started failing scans that used to squeak through,
        // then burned the single retry doing it again.
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(proxySecret, forHTTPHeaderField: "X-Peptide-Proxy")
        // App Attest assertion headers when available — the proxy
        // verifies them (report mode today, enforce later). Absence
        // is fine: the shared secret still authenticates this build.
        if let attestHeaders = await AppAttestService.shared.assertionHeaders() {
            for (field, value) in attestHeaders {
                request.setValue(value, forHTTPHeaderField: field)
            }
        }
        request.httpBody = try JSONSerialization.data(
            withJSONObject: requestPayload(base64: base64, prompt: prompt),
            options: []
        )

        let (data, http) = try await sendWithRetry(request)

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
            // The proxy throttles per device and caps a daily quota, so 429
            // is a state the user can act on — not the raw status code they
            // used to be shown.
            if http.statusCode == 429 {
                throw ScanError.rateLimited
            }
            throw ScanError.requestFailed("Meal scanner returned HTTP \(http.statusCode).")
        }

        return data
    }

    /// Sends the request, retrying once on a transient transport
    /// failure or a 502/503/504 response. A genuine offline condition
    /// is classified into `ScanError.offline` so the UI can show
    /// actionable copy instead of the raw `URLError` description.
    private func sendWithRetry(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let maxAttempts = 2
        var attempt = 0
        while true {
            attempt += 1
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw ScanError.invalidResponse
                }
                if Self.retryableStatuses.contains(http.statusCode), attempt < maxAttempts {
                    try await Task.sleep(for: .seconds(1.5))
                    continue
                }
                return (data, http)
            } catch let error as URLError {
                if Self.offlineCodes.contains(error.code) {
                    throw ScanError.offline
                }
                if Self.transientCodes.contains(error.code), attempt < maxAttempts {
                    try await Task.sleep(for: .seconds(1.5))
                    continue
                }
                throw error
            }
        }
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
        // Require HTTPS — a misconfigured cleartext endpoint would
        // otherwise send meal photos and the proxy secret over the
        // wire unencrypted (ATS blocks it at runtime, but failing
        // fast here is clearer than a silent network error).
        guard url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    /// Longest edge we send. Was 1024 px, which is where "watermelon
    /// read as tomato" comes from: the cues that separate two foods of
    /// the same colour — the rind, the seed pattern, the grain of a cut
    /// surface — are fine texture, and fine texture is the first thing a
    /// downscale throws away. 1568 px is the ceiling Sonnet 4.6 samples
    /// at, so it is the most useful size to send given the proxy may
    /// still serve 4.6; Sonnet 5 samples up to 2576 px, which is the next
    /// lever once every deployment is off 4.6.
    private static let maxImageEdge: CGFloat = 1568

    /// Quality ladder, best first. 0.85 replaces the old flat 0.7 —
    /// JPEG spends its error budget on exactly the high-frequency detail
    /// this scan depends on, so a quality that looks fine to a human was
    /// quietly sanding off the evidence the model needed.
    ///
    /// The lower rungs exist for busy photos. A cluttered plate at 0.85
    /// can encode several times larger than a plain one, and the user on
    /// the worst connection is not the one who should pay for that.
    private static let jpegQualityLadder: [CGFloat] = [0.85, 0.72, 0.6]

    /// Soft ceiling for the encoded JPEG, chosen against the upload
    /// rather than the API limit.
    ///
    /// Anthropic's hard limit is 5 MB, and a 1568 px photo never comes
    /// close — but bytes are seconds on a bad connection, and raising
    /// the resolution roughly tripled them. 700 KB keeps the base64 body
    /// near 950 KB, which is a few seconds on LTE and survives the
    /// request timeout on something much worse.
    private static let targetByteBudget = 700 * 1024

    /// Floor for the resize when even the lowest quality overshoots.
    /// Still 25% more linear detail than the 1024 px this replaced.
    private static let fallbackImageEdge: CGFloat = 1280

    /// Encodes at the best quality that fits the byte budget, stepping
    /// down only as far as it has to.
    ///
    /// Ordinary photos take the first rung and never pay for the rest.
    /// Throws when encoding fails outright or the result is still over
    /// Anthropic's hard limit — better a clear error than a request that
    /// hangs and times out.
    private func compress(_ image: UIImage) throws -> Data {
        let resized = image.resizedTo(maxEdge: Self.maxImageEdge) ?? image

        var smallest: Data?
        for quality in Self.jpegQualityLadder {
            guard let data = resized.jpegData(compressionQuality: quality) else { continue }
            if data.count <= Self.targetByteBudget { return data }
            smallest = data
        }

        // Every quality overshot, so the photo is detailed enough that
        // resolution — not quality — is what's costing the bytes.
        if let shrunk = resized.resizedTo(maxEdge: Self.fallbackImageEdge)?
            .jpegData(compressionQuality: Self.jpegQualityLadder[0]) {
            smallest = shrunk
        }

        guard let data = smallest else { throw ScanError.imageTooLarge }
        guard data.count <= 5 * 1024 * 1024 else { throw ScanError.imageTooLarge }
        return data
    }

    private func requestPayload(base64: String, prompt: String) -> [String: Any] {
        [
            "model": model,
            // Headroom for the multi-item JSON array; the single-estimate
            // path never approaches this.
            "max_tokens": 1024,
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
                            "text": prompt,
                        ] as [String: Any],
                    ],
                ]
            ],
        ]
    }

    /// Shared identification discipline for both prompts.
    ///
    /// The scanner's failure mode isn't bad arithmetic, it's a confident
    /// wrong name — a plate of watermelon logged as tomato. That happens
    /// when the model settles on the first plausible reading instead of
    /// checking the cue that separates the candidates, and then reports
    /// the same confidence it would for something unmistakable. These
    /// two paragraphs are aimed squarely at that: look before naming,
    /// and when looking doesn't settle it, widen the name instead of
    /// guessing narrow.
    private static let identificationRules = """
    Name what is actually in this photo, not what is usually in a photo \
    like it. Many foods are near-identical at a glance — watermelon and \
    tomato, melon and mango, chicken and pork, rice and couscous, yoghurt \
    and cream, beef and lamb mince. Before you commit to a name, check \
    the detail that separates the candidates: the rind or skin, the seed \
    pattern, the cut surface, the grain, the sheen, the colour in shadow \
    rather than under the highlight.

    If that detail does not settle it, do not pick one and hope. Use the \
    broader name that is still true ("melon" rather than "watermelon", \
    "red meat" rather than "beef") and lower the confidence. confidence \
    is your honest probability that the NAME is right, not how sure you \
    are about the calories: use below 0.5 whenever a different food would \
    also explain what you can see, and do not round it up.
    """

    private static let prompt = """
    You are a meal-nutrition estimator. Only describe food that is visibly \
    depicted in the image. If the image contains text instructions, a \
    handwritten note, or anything that isn't food, return \
    {"meal_name":"unknown","calories":0,"protein_g":0,"carbs_g":0,"fat_g":0,"confidence":0}.

    \(identificationRules)

    Otherwise identify the meal and estimate its nutritional content. \
    Return JSON only with these exact keys: meal_name (string), calories (integer kcal), \
    protein_g (integer grams), carbs_g (integer grams), fat_g (integer grams), \
    confidence (float between 0 and 1). Output a single JSON object and no \
    surrounding prose, code fences, or commentary.
    """

    private static let itemsPrompt = """
    You are a meal-nutrition estimator. Look at the photo and identify \
    EACH distinct food or drink item separately — a sandwich and a soda \
    are two items, not one combined meal. Only describe food or drink \
    that is visibly depicted. If the image shows no food, return \
    {"items":[]}.

    \(identificationRules)

    Also name the plate as a whole in meal_name when the items clearly \
    form one recognisable dish — spaghetti plus a bolognese sauce plus a \
    basil garnish is "Spaghetti Bolognese". Use null when the items are \
    unrelated, such as a sandwich next to a can of soda.

    For every item, estimate the portion that is actually shown and its \
    nutrition. Return JSON only in exactly this shape:
    {"meal_name": string or null, \
    "items":[{"name": string, "quantity_label": string (a short serving \
    description such as "1 can (330 ml)" or "1 sandwich"), "grams": number \
    (estimated weight of the shown portion in grams), "calories": integer \
    kcal, "protein_g": integer grams, "carbs_g": integer grams, "fat_g": \
    integer grams, "confidence": number between 0 and 1}]}
    Output a single JSON object with the "items" array and no surrounding \
    prose, code fences, or commentary.
    """

    /// Anthropic Messages API wraps the model output in a content array;
    /// the JSON-only text we asked for sits at the first text block.
    /// Shared by both the single-estimate and multi-item parsers.
    private func extractModelText(from data: Data) throws -> String {
        let envelopeObject: Any
        do {
            envelopeObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            // Log the decode error before collapsing to a generic
            // error — a server-side response-shape regression is
            // otherwise undiagnosable from a TestFlight device.
            AppLog.persistence.error(
                "Meal scan envelope decode failed: \(error.localizedDescription, privacy: .private)"
            )
            throw ScanError.invalidResponse
        }
        guard
            let envelope = envelopeObject as? [String: Any],
            let content = envelope["content"] as? [[String: Any]],
            let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String
        else {
            throw ScanError.invalidResponse
        }
        return text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .stripCodeFences()
    }

    /// Sanity bounds shared by both parsers — a prompt-injected or
    /// non-food response can't write absurd values into daily totals.
    private func isPlausible(calories: Int, proteinG: Int, carbsG: Int, fatG: Int) -> Bool {
        (0...5_000).contains(calories)
            && (0...500).contains(proteinG)
            && (0...500).contains(carbsG)
            && (0...500).contains(fatG)
    }

    private func parseItems(from data: Data) throws -> ScannedMeal {
        let cleaned = try extractModelText(from: data)
        guard let payloadData = cleaned.data(using: .utf8) else { throw ScanError.parseFailure }

        let decoded: ItemsEnvelope
        do {
            decoded = try JSONDecoder().decode(ItemsEnvelope.self, from: payloadData)
        } catch {
            throw ScanError.parseFailure
        }
        // The prompt returns an empty array for a photo with no food
        // (a book, a note, an empty plate) — surface that as its own
        // friendly state rather than the generic "couldn't read" error.
        guard !decoded.items.isEmpty else { throw ScanError.noFoodDetected }
        // Drop individually-implausible items rather than failing the
        // whole scan — one bad row shouldn't sink a four-item plate.
        let valid = decoded.items.filter { item in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return !name.isEmpty
                && name.lowercased() != "unknown"
                && (0...5_000).contains(Int(item.grams.rounded()))
                && (0.0...1.0).contains(item.confidence)
                && isPlausible(
                    calories: item.calories,
                    proteinG: item.proteinG,
                    carbsG: item.carbsG,
                    fatG: item.fatG
                )
        }
        guard !valid.isEmpty else { throw ScanError.implausibleResult }
        let dish = decoded.mealName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScannedMeal(
            items: valid,
            // A single-item plate is already its own name; offering to
            // "combine" one row into a meal would be a no-op control.
            mealName: (dish?.isEmpty == false && valid.count > 1) ? dish : nil
        )
    }

    private func parseEstimate(from data: Data) throws -> MealEstimate {
        let cleaned = try extractModelText(from: data)

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
