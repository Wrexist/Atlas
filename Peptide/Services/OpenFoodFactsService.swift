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

    private static let defaultBaseURL = URL(string: "https://world.openfoodfacts.org/api/v2/product/")!

    init(
        session: URLSession = .shared,
        cache: BarcodeProductCache = .shared,
        baseURL: URL = OpenFoodFactsService.defaultBaseURL,
        userAgent: String = "PeptideX/1.0 (https://peptidesai.com)"
    ) {
        self.session = session
        self.cache = cache
        self.baseURL = baseURL
        self.userAgent = userAgent
    }

    enum LookupError: Error, LocalizedError, Equatable {
        case invalidBarcode
        case notFound
        case rateLimited
        case networkUnavailable
        case requestFailed(status: Int)
        case decodeFailure

        var errorDescription: String? {
            switch self {
            case .invalidBarcode:        "That barcode doesn't look right. Try scanning again."
            case .notFound:              "We couldn't find that product. Try a photo instead?"
            case .rateLimited:           "Open Food Facts is busy right now. Try again in a minute."
            case .networkUnavailable:    "You're offline. We'll use cached results when available."
            case .requestFailed(let s):  "Lookup failed (status \(s)). Please try again."
            case .decodeFailure:         "We got an unexpected response from the food database."
            }
        }
    }

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
                    try? await self.refreshInBackground(barcode: normalized)
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

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()
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
                    .nonEmptyOrNil,
                imageURL: imageFrontSmallURL.flatMap { URL(string: $0) },
                servingSizeText: servingSize?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .nonEmptyOrNil,
                // OFF occasionally serializes 0 for unknown weights —
                // collapse to nil so `defaultPortion` correctly skips
                // the .servings branch and the "Add" button stays live.
                servingGrams: servingQuantity?.value.positiveOrNil,
                packageGrams: productQuantity?.value.positiveOrNil,
                per100g: per100,
                nutriScore: nutriscoreGrade?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .nonEmptyOrNil,
                novaGroup: novaGroup?.value,
                fetchedAt: fetchedAt
            )
        }
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

private extension String {
    var nonEmptyOrNil: String? { isEmpty ? nil : self }
}

private extension Double {
    /// Returns the value if it is finite and strictly positive, else nil.
    /// Used to filter sentinel zeros and NaNs that OFF sometimes emits
    /// for unknown weights and energies.
    var positiveOrNil: Double? {
        (isFinite && self > 0) ? self : nil
    }
}
