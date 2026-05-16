import Foundation

/// Looks up packaged-food barcodes against the Open Food Facts public
/// database and returns the result as a normalized `ScannedProduct`.
///
/// Open Food Facts is free and unauthenticated, but does require a
/// descriptive User-Agent — anonymous clients are rate-limited. Results
/// are written through `BarcodeProductCache` so repeat scans (and
/// offline reads) are instant.
///
/// Pattern matches `MealScannerService`: a `Sendable` final class with
/// a shared singleton, an injectable `URLSession` for tests, and an
/// error enum the UI maps to user-visible copy.
final class OpenFoodFactsService: Sendable {

    static let shared = OpenFoodFactsService()

    private let session: URLSession
    private let cache: BarcodeProductCache
    private let baseURL: URL
    private let userAgent: String

    /// Entries older than this trigger a background refresh on the next
    /// read while still returning the cached value immediately. OFF
    /// product entries are amended slowly by volunteer editors, so a
    /// weekly check is plenty to stay current without thrashing.
    static let staleAfter: TimeInterval = 60 * 60 * 24 * 7

    /// `fields=` trims the response from ~80 KB to ~3 KB by only asking
    /// for the keys we actually map. Listed once here so the wire shape
    /// and the decoder stay in sync.
    private static let requestedFields = [
        "product_name",
        "brands",
        "image_front_small_url",
        "serving_size",
        "serving_quantity",
        "product_quantity",
        "nutriments",
        "nutriscore_grade",
        "nova_group",
    ].joined(separator: ",")

    private static let defaultBaseURL = URL.staticHTTPS("https://world.openfoodfacts.org/api/v2/product/")
    private static let defaultSearchURL = URL.staticHTTPS("https://world.openfoodfacts.org/cgi/search.pl")

    private let searchURL: URL

    /// OFF's documented ceiling for `/cgi/search.pl` is 10 requests per
    /// minute per IP. The food-library UI debounces at 500 ms and only
    /// fires once the user pauses, but a heavy typist can still squeeze
    /// past that, so the in-memory query cache below is the real
    /// safety net.
    static let searchMaxPageSize: Int = 25

    /// Minimum query length we'll hit OFF for. Shared with the UI
    /// layer so both sides agree on what counts as "too short to
    /// search".
    static let minimumSearchQueryLength: Int = 2

    /// In-memory search-cache TTL. 10 minutes absorbs a user typing
    /// the same word twice in one session without inflating memory,
    /// and short enough that re-opening the library after editing
    /// favorites sees fresh ranking.
    static let searchCacheTTL: TimeInterval = 10 * 60

    /// Hard cap on cached queries. ~64 × ~5 KB each ≈ 320 KB upper
    /// bound. Pathological tap-typing can't grow the cache past this.
    static let searchCacheMaxEntries: Int = 64

    /// Local sliding-window rate limit, one below OFF's documented
    /// 10/min ceiling for safety. Cache hits bypass the limiter.
    static let searchRateLimitMaxRequests: Int = 8
    static let searchRateLimitWindowSeconds: TimeInterval = 60

    init(
        session: URLSession = .shared,
        cache: BarcodeProductCache = .shared,
        baseURL: URL = OpenFoodFactsService.defaultBaseURL,
        searchURL: URL = OpenFoodFactsService.defaultSearchURL,
        userAgent: String = "Atlas/1.0 (https://peptidesai.com)"
    ) {
        self.session = session
        self.cache = cache
        self.baseURL = baseURL
        self.searchURL = searchURL
        self.userAgent = userAgent
    }

    enum LookupError: Error, LocalizedError, Equatable {
        case invalidBarcode
        case notFound
        case rateLimited
        /// Local sliding-window throttle blocked the call before it
        /// hit the network. Distinct from `.rateLimited` (which is a
        /// 429 from OFF itself) so the UI can show "catch your breath"
        /// copy instead of "OFF is busy".
        case throttledLocally(secondsToRetry: Int)
        case networkUnavailable
        case requestFailed(status: Int)
        /// Retries against OFF's gateway have been exhausted on
        /// transient 5xx errors (502/503/504) or repeated transport
        /// failures. Surfaced as its own case so the error UI can
        /// nudge the user toward the photo fallback instead of just
        /// repeating "try again".
        case serviceUnavailable
        case decodeFailure

        // Wrapped in `String(localized:)` so each case's copy gets
        // picked up by Xcode's string-catalog extractor and matched
        // against `Localizable.xcstrings`. SwiftUI `Text(...)` would
        // auto-localize for us, but error messages get surfaced via
        // `errorDescription` (a plain `String?`), bypassing that path.
        var errorDescription: String? {
            switch self {
            case .invalidBarcode:
                String(localized: "That barcode doesn't look right. Try scanning again.")
            case .notFound:
                String(localized: "We couldn't find that product. Try a photo instead?")
            case .rateLimited:
                String(localized: "Open Food Facts is busy right now. Try again in a minute.")
            case .throttledLocally(let seconds):
                String(
                    localized: "Catch your breath — searching too fast. Try again in \(seconds)s.",
                    comment: "Local rate-limiter hit. Seconds is the time until the next slot opens."
                )
            case .networkUnavailable:
                String(localized: "You're offline. We'll use cached results when available.")
            case .requestFailed(let status):
                String(
                    localized: "Lookup failed (status \(status)). Please try again.",
                    comment: "Status code is an HTTP code or -1 for transport errors."
                )
            case .serviceUnavailable:
                String(localized: "Open Food Facts is briefly unavailable. Try again in a moment, or snap a photo of the label instead.")
            case .decodeFailure:
                String(localized: "We got an unexpected response from the food database.")
            }
        }
    }

    /// HTTP statuses we treat as transient OFF-gateway/availability
    /// failures and retry with backoff. 500 is excluded because it
    /// usually indicates a request-side problem (malformed query,
    /// missing field) where retrying won't change the outcome — the
    /// existing `.requestFailed` path lets the user surface that to
    /// support. 502/503/504 are the codes OFF emits when its edge or
    /// upstream is briefly overloaded; observed in the wild around
    /// peak hours and self-resolving within seconds. `-1` is the
    /// sentinel emitted by `performLookup` for URLSession transport
    /// errors (timeout, dropped connection) — those are at least as
    /// retryable as a 502.
    private static let retryableStatuses: Set<Int> = [-1, 502, 503, 504]

    /// Backoff schedule between retry attempts. Three attempts total
    /// (initial + two retries) with a worst-case added wait of ~1.2s,
    /// which keeps the perceived latency in "slow scan" territory
    /// rather than "stuck".
    private static let retryBackoffs: [Duration] = [
        .milliseconds(300),
        .milliseconds(900),
    ]

    /// Resolves a barcode to a `ScannedProduct`. Checks the cache first;
    /// on miss, hits the network and writes through. Stale-but-valid
    /// cache hits return immediately and trigger a fire-and-forget
    /// refetch in the background — the user sees instant data, and the
    /// next scan benefits from the updated entry. `Task.cancel()` on
    /// the caller propagates because `URLSession.data(for:)` is
    /// cancellation-aware.
    func fetch(barcode: String) async throws -> ScannedProduct {
        let normalized = try Self.normalize(barcode: barcode)

        if let cached = await cache.read(barcode: normalized) {
            if Self.isStale(cached) {
                // No [weak self] — the service is a long-lived shared
                // instance, so a strong capture for the refresh task
                // is correct and avoids silently dropping work if a
                // test ever decoupled the singleton lifecycle.
                Task.detached {
                    do {
                        try await self.refreshInBackground(barcode: normalized)
                    } catch {
                        // Background refresh failures used to disappear
                        // silently. Surface them to Console.app so a
                        // batch of stale entries doesn't go unnoticed —
                        // the user still gets the cached response on
                        // this call, so this is diagnostic-only.
                        AppLog.persistence.error(
                            "Barcode background refresh failed for \(normalized, privacy: .public): \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
            }
            return cached
        }

        let product = try await fetchFromNetwork(barcode: normalized)
        await cache.write(product)
        return product
    }

    /// Returns the `limit` most-recently-scanned products, surfaced by
    /// the scanner UI as a one-tap re-log row. Pure cache read — never
    /// hits the network.
    func recent(limit: Int = 5) async -> [ScannedProduct] {
        await cache.recent(limit: limit)
    }

    /// Free-text search against Open Food Facts. Returns the top
    /// `pageSize` products (capped at `searchMaxPageSize`) matching the
    /// query, normalised to the same `ScannedProduct` shape barcode
    /// lookups produce.
    ///
    /// `/cgi/search.pl` is the only OFF endpoint that supports
    /// full-text product-name search today — v2 search is barcode/
    /// taxonomy-only and `search-a-licious` is still beta. The endpoint
    /// is rate-limited to 10 req/min/IP, so callers should debounce
    /// keystrokes (the food library uses 500 ms) and rely on the
    /// in-memory query cache for repeats.
    ///
    /// Throws `LookupError.notFound` on empty results so the caller can
    /// branch the empty state the same way it does for a missed barcode.
    func search(query: String, pageSize: Int = 20) async throws -> [ScannedProduct] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumSearchQueryLength else { return [] }

        if let hit = await Self.searchCache.read(query: trimmed) {
            return hit
        }

        // Local sliding-window throttle. Cache hits already returned
        // above, so we only spend budget on calls that would actually
        // round-trip. A 429 from OFF itself still maps to
        // `.rateLimited` further down — these are distinct failure
        // modes so the UI copy can differ.
        let requestedAt = Date()
        switch await Self.searchRateLimiter.requestSlot(now: requestedAt) {
        case .allowed:
            break
        case .denied(let secondsToRetry):
            throw LookupError.throttledLocally(secondsToRetry: secondsToRetry)
        }

        let cappedPageSize = max(1, min(pageSize, Self.searchMaxPageSize))
        var components = URLComponents(url: searchURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "search_terms", value: trimmed),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: String(cappedPageSize)),
            URLQueryItem(name: "fields", value: Self.searchRequestedFields),
            URLQueryItem(name: "sort_by", value: "unique_scans_n"),
        ]
        // Search has no barcode, so `.invalidBarcode` would be a
        // misleading user-visible message. `.requestFailed` reads as
        // "something went wrong on our side, try again" — the right
        // shape for a URL-assembly failure on a text search.
        guard let url = components?.url else { throw LookupError.requestFailed(status: -1) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where Self.isNetworkUnavailable(urlError) {
            throw LookupError.networkUnavailable
        } catch {
            throw LookupError.requestFailed(status: -1)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LookupError.requestFailed(status: -1)
        }
        switch http.statusCode {
        case 200..<300:
            break
        case 429:
            // Telemetry: surface 429s to Console.app so we can spot
            // abuse patterns. Includes the query so a problematic
            // pattern (super-short queries, weird unicode) is
            // diagnosable from the logs alone.
            AppLog.persistence.error(
                "OFF rate-limited (429) for query: \(trimmed, privacy: .public)"
            )
            throw LookupError.rateLimited
        default:
            throw LookupError.requestFailed(status: http.statusCode)
        }

        let envelope: SearchEnvelope
        do {
            envelope = try Self.decoder.decode(SearchEnvelope.self, from: data)
        } catch {
            throw LookupError.decodeFailure
        }

        let fetchedAt = Date()
        let products: [ScannedProduct] = envelope.products.compactMap { raw in
            guard let id = raw.code?.trimmingCharacters(in: .whitespaces).nilIfEmpty
                    ?? raw.id?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            else { return nil }
            return raw.toScannedProduct(barcode: id, fetchedAt: fetchedAt)
        }

        await Self.searchCache.write(query: trimmed, results: products)
        return products
    }

    /// Trims the search response from ~80 KB to ~5 KB for a typical
    /// 20-result page. Identical to the product-lookup field list with
    /// `code` and `id` added so the mapper can resolve a stable
    /// identifier for results that lack a scannable barcode.
    private static let searchRequestedFields = ([
        "code",
        "_id",
    ] + requestedFields.split(separator: ",").map(String.init))
        .joined(separator: ",")

    /// Process-lifetime query cache. Settings live as named constants
    /// at the top of the type so a future tweak only requires
    /// touching one place.
    private static let searchCache = SearchQueryCache(
        ttl: searchCacheTTL,
        maxEntries: searchCacheMaxEntries
    )

    /// Sliding-window throttle in front of `cgi/search.pl`. Consulted
    /// *after* the cache hit check so cached repeats never spend
    /// budget. See the top-of-type constants for the rationale on
    /// the chosen window.
    static let searchRateLimiter = OFFRateLimiter(
        maxRequests: searchRateLimitMaxRequests,
        windowSeconds: searchRateLimitWindowSeconds
    )

    static func isStale(_ product: ScannedProduct) -> Bool {
        Date().timeIntervalSince(product.fetchedAt) > staleAfter
    }

    private func refreshInBackground(barcode: String) async throws {
        let fresh = try await fetchFromNetwork(barcode: barcode)
        await cache.write(fresh)
    }

    // MARK: - Internals

    private func fetchFromNetwork(barcode: String) async throws -> ScannedProduct {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("\(barcode).json"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "fields", value: Self.requestedFields)]
        guard let url = components?.url else { throw LookupError.invalidBarcode }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        // Retry transient OFF-gateway errors (502/503/504) before
        // surfacing failure. Anything non-retryable (404, 429, decode,
        // genuine offline) propagates on the first attempt.
        let maxAttempts = Self.retryBackoffs.count + 1
        for attempt in 0..<maxAttempts {
            if attempt > 0 {
                try await Task.sleep(for: Self.retryBackoffs[attempt - 1])
            }
            do {
                return try await performLookup(request: request, barcode: barcode)
            } catch let error as LookupError {
                if case .requestFailed(let status) = error,
                   Self.retryableStatuses.contains(status) {
                    if attempt == maxAttempts - 1 {
                        AppLog.persistence.error(
                            "OFF \(status, privacy: .public) for \(barcode, privacy: .public): retries exhausted"
                        )
                        throw LookupError.serviceUnavailable
                    }
                    continue
                }
                throw error
            }
        }
        // Compiler can't see that the loop always returns or throws.
        throw LookupError.serviceUnavailable
    }

    /// Single round-trip against OFF. Extracted so the retry loop in
    /// `fetchFromNetwork(barcode:)` can call it once per attempt
    /// without duplicating decode / status-mapping logic.
    private func performLookup(request: URLRequest, barcode: String) async throws -> ScannedProduct {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .notConnectedToInternet
                                            || urlError.code == .dataNotAllowed {
            // Genuinely offline. The error card hints that cached
            // results still work, so the user knows what to expect.
            throw LookupError.networkUnavailable
        } catch {
            // Timeouts and other transport errors are re-triable — the
            // server is probably reachable, just slow or transiently
            // unhappy. requestFailed exposes the "Try again" path.
            throw LookupError.requestFailed(status: -1)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LookupError.requestFailed(status: -1)
        }
        switch http.statusCode {
        case 200..<300:                  break
        case 404:                        throw LookupError.notFound
        case 429:                        throw LookupError.rateLimited
        default:                         throw LookupError.requestFailed(status: http.statusCode)
        }

        let envelope: APIEnvelope
        do {
            envelope = try Self.decoder.decode(APIEnvelope.self, from: data)
        } catch {
            throw LookupError.decodeFailure
        }

        guard envelope.status == 1, let raw = envelope.product else {
            throw LookupError.notFound
        }

        return raw.toScannedProduct(barcode: barcode, fetchedAt: Date())
    }

    /// Open Food Facts accepts EAN-13, EAN-8, UPC-A, UPC-E and ITF-14
    /// codes — all numeric, all between 8 and 14 characters. Whitespace
    /// is stripped because barcode SDKs sometimes pad short codes.
    static func normalize(barcode: String) throws -> String {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...14).contains(trimmed.count),
              trimmed.allSatisfy(\.isASCII),
              trimmed.allSatisfy(\.isNumber)
        else {
            throw LookupError.invalidBarcode
        }
        return trimmed
    }

    /// Shared decoder for the OFF response shapes. No date strategy
    /// configured because OFF's product payloads carry no dates we
    /// decode — `fetchedAt` is stamped client-side. Kept as a single
    /// instance so we don't pay the (small) allocation cost on every
    /// request.
    // JSONDecoder isn't Sendable but is thread-safe for read-only
    // decoding after configuration. nonisolated(unsafe) is the
    // documented escape hatch for Swift 6.
    nonisolated(unsafe) private static let decoder = JSONDecoder()

    /// Treat the standard "no path to the server" `URLError` codes as
    /// offline rather than as generic request failures. Airplane
    /// Mode, captive portals, mid-flight signal drop, and DNS-down
    /// all surface through these codes; the UI pivots into "showing
    /// cached results" mode rather than "lookup failed, try again".
    private static func isNetworkUnavailable(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet,
             .dataNotAllowed,
             .timedOut,
             .networkConnectionLost,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .callIsActive,
             .secureConnectionFailed:
            return true
        default:
            return false
        }
    }
}

// MARK: - Wire types

private extension OpenFoodFactsService {

    /// Top-level Open Food Facts response. `status` is 1 on hit, 0 on
    /// miss; we treat a 200 with `status == 0` as a 404 so the caller
    /// only branches once.
    struct APIEnvelope: Decodable {
        let status: Int
        let product: RawProduct?
    }

    /// Mirror of the OFF product subset we requested via `fields=`.
    /// Most nutrient keys contain hyphens, so the field names use
    /// `CodingKeys` to map. Every numeric is `Double?` because OFF
    /// occasionally serializes them as strings or omits them entirely
    /// for incomplete records.
    struct RawProduct: Decodable {
        /// Search-only — the barcode the product is indexed under.
        /// Absent on barcode-lookup responses where it's redundant.
        let code: String?
        /// Search-only fallback identifier for products without a
        /// scannable barcode. Decoded from OFF's `_id` field.
        let id: String?
        let productName: String?
        let brands: String?
        let imageFrontSmallURL: String?
        let servingSize: String?
        let servingQuantity: FlexibleDouble?
        let productQuantity: FlexibleDouble?
        let nutriments: RawNutriments?
        let nutriscoreGrade: String?
        let novaGroup: FlexibleInt?

        enum CodingKeys: String, CodingKey {
            case code               = "code"
            case id                 = "_id"
            case productName        = "product_name"
            case brands             = "brands"
            case imageFrontSmallURL = "image_front_small_url"
            case servingSize        = "serving_size"
            case servingQuantity    = "serving_quantity"
            case productQuantity    = "product_quantity"
            case nutriments         = "nutriments"
            case nutriscoreGrade    = "nutriscore_grade"
            case novaGroup          = "nova_group"
        }

        func toScannedProduct(barcode: String, fetchedAt: Date) -> ScannedProduct {
            let resolvedName = [productName, brands]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty })
                ?? "Unknown product"

            let n = nutriments
            // Real OFF data sometimes reports calories as kJ only — fall
            // back through the energy_100g (kJ) field divided by 4.184.
            // Without this, kJ-only products would silently log 0 kcal.
            let kcal = n?.energyKcal100g?.value
            let kJ = n?.energy100g?.value
            let calories = kcal ?? kJ.map { $0 / 4.184 } ?? 0

            let per100 = ScannedProduct.Nutriments(
                calories: calories,
                proteinG: n?.proteins100g?.value ?? 0,
                carbsG:   n?.carbohydrates100g?.value ?? 0,
                fatG:     n?.fat100g?.value ?? 0,
                fiberG:   n?.fiber100g?.value,
                sugarsG:  n?.sugars100g?.value
            )

            return ScannedProduct(
                barcode: barcode,
                name: resolvedName,
                brand: brands?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty,
                imageURL: imageFrontSmallURL.flatMap { URL(string: $0) },
                servingSizeText: servingSize?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty,
                // OFF occasionally serializes 0 for unknown weights —
                // collapse to nil so `defaultPortion` correctly skips
                // the .servings branch and the "Add" button stays live.
                servingGrams: servingQuantity?.value.positiveOrNil,
                packageGrams: productQuantity?.value.positiveOrNil,
                per100g: per100,
                nutriScore: nutriscoreGrade?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty,
                novaGroup: novaGroup?.value,
                fetchedAt: fetchedAt
            )
        }
    }

    /// Search-endpoint response. `products` is the only field we need —
    /// `count`, `page`, etc. are dropped on decode. Each entry uses the
    /// same `RawProduct` shape as the product-lookup endpoint, with
    /// `code` and `_id` added so we can pick a stable identifier even
    /// when the result has no barcode.
    struct SearchEnvelope: Decodable {
        let products: [RawProduct]
    }

    struct RawNutriments: Decodable {
        let energyKcal100g: FlexibleDouble?
        let energy100g: FlexibleDouble?
        let proteins100g: FlexibleDouble?
        let carbohydrates100g: FlexibleDouble?
        let fat100g: FlexibleDouble?
        let fiber100g: FlexibleDouble?
        let sugars100g: FlexibleDouble?

        enum CodingKeys: String, CodingKey {
            case energyKcal100g     = "energy-kcal_100g"
            case energy100g         = "energy_100g"
            case proteins100g       = "proteins_100g"
            case carbohydrates100g  = "carbohydrates_100g"
            case fat100g            = "fat_100g"
            case fiber100g          = "fiber_100g"
            case sugars100g         = "sugars_100g"
        }
    }
}

/// Open Food Facts inconsistently serializes numeric fields as numbers
/// or as strings ("330" vs 330). These wrappers absorb the variance so
/// the rest of the codebase only deals with `Double` / `Int`.
private struct FlexibleDouble: Decodable {
    let value: Double
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) {
            value = d
        } else if let s = try? c.decode(String.self), let d = Double(s) {
            value = d
        } else {
            throw DecodingError.typeMismatch(
                Double.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected Double or numeric String")
            )
        }
    }
}

private struct FlexibleInt: Decodable {
    let value: Int
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) {
            value = i
        } else if let d = try? c.decode(Double.self) {
            value = Int(d)
        } else if let s = try? c.decode(String.self), let i = Int(s) {
            value = i
        } else {
            throw DecodingError.typeMismatch(
                Int.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected Int, Double, or numeric String")
            )
        }
    }
}

private extension Double {
    /// Returns the value if it is finite and strictly positive, else nil.
    /// Used to filter sentinel zeros and NaNs that OFF sometimes emits
    /// for unknown weights and energies.
    var positiveOrNil: Double? {
        (isFinite && self > 0) ? self : nil
    }
}

/// In-memory LRU cache for `search(query:)` results. Keyed by the
/// trimmed, lower-cased query so case-only repeats don't re-fetch. The
/// 10-minute TTL is short enough that a user re-opening the food
/// library after editing a custom food won't see stale rankings, and
/// long enough to coalesce keystroke-driven repeats inside a single
/// search session.
///
/// Bounded by `maxEntries` so a pathological typist (or a test harness
/// hammering the service) can't grow the cache without limit. Eviction
/// is by least-recently-written — search results don't track a last-
/// read timestamp because the read pattern is "consult once then
/// render".
actor SearchQueryCache {
    private struct CacheEntry {
        let results: [ScannedProduct]
        let writtenAt: Date
    }

    private let ttl: TimeInterval
    private let maxEntries: Int
    private var entries: [String: CacheEntry] = [:]
    private var insertionOrder: [String] = []

    init(ttl: TimeInterval, maxEntries: Int) {
        self.ttl = ttl
        self.maxEntries = max(1, maxEntries)
    }

    func read(query: String) -> [ScannedProduct]? {
        let key = Self.normalize(query)
        guard let entry = entries[key] else { return nil }
        if Date().timeIntervalSince(entry.writtenAt) > ttl {
            // Drop from both stores in lockstep — leaving the key in
            // `insertionOrder` would let a subsequent `write` produce
            // a duplicate entry there (the `entries[key] == nil` check
            // would pass and the key would be appended again).
            entries.removeValue(forKey: key)
            insertionOrder.removeAll { $0 == key }
            return nil
        }
        return entry.results
    }

    func write(query: String, results: [ScannedProduct]) {
        let key = Self.normalize(query)
        if entries[key] == nil {
            insertionOrder.append(key)
        }
        entries[key] = CacheEntry(results: results, writtenAt: Date())
        while insertionOrder.count > maxEntries {
            let oldest = insertionOrder.removeFirst()
            entries.removeValue(forKey: oldest)
        }
    }

    private static func normalize(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Sliding-window rate limiter. Keeps the timestamps of every call
/// that passed in the last `windowSeconds`; a request is allowed when
/// fewer than `maxRequests` of those are still in-window. Sliding (not
/// fixed) so a burst right before the window boundary doesn't get a
/// "free" second burst the moment the boundary crosses — protects the
/// downstream API from the worst pathological pattern.
///
/// The limiter pre-commits the slot on `.allowed` so two concurrent
/// callers can't both pass when only one slot remains. `.denied`
/// returns the wall-clock seconds until the oldest in-window
/// timestamp expires — the UI surfaces that as "try again in Ns".
actor OFFRateLimiter {

    enum Verdict: Equatable, Sendable {
        case allowed
        case denied(secondsToRetry: Int)
    }

    private let maxRequests: Int
    private let windowSeconds: TimeInterval
    private var timestamps: [Date] = []

    init(maxRequests: Int, windowSeconds: TimeInterval) {
        self.maxRequests = max(1, maxRequests)
        self.windowSeconds = max(0.001, windowSeconds)
    }

    func requestSlot(now: Date = Date()) -> Verdict {
        // Prune anything outside the sliding window first so the
        // count below is the live in-window total.
        let cutoff = now.addingTimeInterval(-windowSeconds)
        while let first = timestamps.first, first < cutoff {
            timestamps.removeFirst()
        }
        if timestamps.count < maxRequests {
            timestamps.append(now)
            return .allowed
        }
        // Caller has to wait until the oldest in-window timestamp
        // ages out. Ceil so the UI shows "try again in 1s" rather
        // than "0s" right at the edge.
        let secondsToRetry = max(1, Int(
            (timestamps[0].addingTimeInterval(windowSeconds).timeIntervalSince(now))
                .rounded(.up)
        ))
        return .denied(secondsToRetry: secondsToRetry)
    }

    /// Test-only: wipe state. Lets unit tests start each case with a
    /// clean window without standing up a fresh instance every time.
    func reset() {
        timestamps.removeAll()
    }
}
