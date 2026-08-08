import Foundation

/// What a barcode turned out to be when it wasn't food.
///
/// Open Food Facts covers groceries and nothing else, so scanning a
/// bottle of shampoo, a bag of dog food, or a pair of headphones used to
/// end at "we couldn't find that product" — a message that reads as
/// *the scan failed* when what actually happened is that the scan
/// worked perfectly and the item simply isn't a food.
struct BarcodeIdentity: Equatable, Sendable {
    let barcode: String
    let name: String
    let brand: String?
    let catalogue: Catalogue

    /// The Open Food Facts project runs four sibling catalogues on the
    /// same server software and the same API routes. Only the first one
    /// is food; the other three are exactly the gap this fills.
    enum Catalogue: String, CaseIterable, Sendable {
        case products = "world.openproductsfacts.org"
        case beauty   = "world.openbeautyfacts.org"
        case petFood  = "world.openpetfoodfacts.org"

        /// Attribution — these are volunteer-maintained open databases
        /// and the app says which one answered.
        var displayName: String {
            switch self {
            case .products: "Open Products Facts"
            case .beauty:   "Open Beauty Facts"
            case .petFood:  "Open Pet Food Facts"
            }
        }

        var icon: String {
            switch self {
            case .products: "shippingbox.fill"
            case .beauty:   "sparkles"
            case .petFood:  "pawprint.fill"
            }
        }

        /// Whether offering "scan the nutrition label" still makes sense.
        ///
        /// The general catalogue carries plenty of edible things the food
        /// catalogue simply hasn't indexed yet, so the label path stays
        /// useful there. Shampoo and dog food have no nutrition panel a
        /// human diary can use, and offering to read one is the kind of
        /// detail that tells a user the app didn't understand them.
        var mayStillBeEdible: Bool { self == .products }

        /// One line explaining why there's nothing to log. Pet food has
        /// nutrition on the label, but it is a dog's nutrition — logging
        /// it into a human's day would be worse than not logging at all.
        var reasonNotLoggable: String {
            switch self {
            case .products: "That's a general product, not a food, so there's nothing to add to your diary."
            case .beauty:   "That's a cosmetic or personal-care product, so there's nothing to add to your diary."
            case .petFood:  "That's pet food — its nutrition is for an animal, not for your diary."
            }
        }
    }

    /// "Brand — Name" when both are known, the name alone otherwise.
    var displayTitle: String {
        guard let brand, !brand.isEmpty, !name.localizedCaseInsensitiveContains(brand) else {
            return name
        }
        return "\(brand) \(name)"
    }
}

/// Last-resort identification for a barcode Open Food Facts doesn't
/// have: asks the three non-food sibling catalogues what the article is.
///
/// This never throws and never blocks logging. Every failure mode — a
/// miss, a timeout, an unexpected payload, a catalogue that's down —
/// resolves to `nil`, which leaves the caller showing exactly the screen
/// it showed before this existed. That is deliberate: it's a bonus on a
/// path the user already reached by failing, so it must not be able to
/// make that path worse.
///
/// Coverage is honestly partial. These catalogues are far smaller than
/// the food one, so plenty of barcodes will still come back unknown —
/// what changes is that the ones they *do* know now say so instead of
/// looking like a broken scanner.
final class BarcodeIdentityService: Sendable {

    static let shared = BarcodeIdentityService()

    private let session: URLSession
    private let userAgent: String

    /// Shorter than the food lookup's 15 s. The user is already looking
    /// at a "not found" card by the time this runs, so a slow answer is
    /// worth less than a quick nothing.
    private static let timeout: TimeInterval = 8

    init(
        session: URLSession = .shared,
        userAgent: String = "Atlas/1.0 (https://peptidesai.com)"
    ) {
        self.session = session
        self.userAgent = userAgent
    }

    /// Returns what the barcode is, or `nil` if none of the catalogues
    /// recognise it.
    ///
    /// The three lookups run concurrently — sequentially they'd stack
    /// three timeouts into a 24-second wait on the common case, which is
    /// a miss. When more than one answers, `Catalogue.allCases` order
    /// decides: the general catalogue first, then the more specific ones.
    func identify(barcode: String) async -> BarcodeIdentity? {
        guard let normalized = try? OpenFoodFactsService.normalize(barcode: barcode) else {
            return nil
        }

        let hits = await withTaskGroup(of: Optional<BarcodeIdentity>.self) { group in
            for catalogue in BarcodeIdentity.Catalogue.allCases {
                group.addTask { await self.lookup(barcode: normalized, in: catalogue) }
            }
            var found: [BarcodeIdentity] = []
            for await hit in group {
                if let hit { found.append(hit) }
            }
            return found
        }

        for catalogue in BarcodeIdentity.Catalogue.allCases {
            if let match = hits.first(where: { $0.catalogue == catalogue }) { return match }
        }
        return nil
    }

    // MARK: - Internals

    private func lookup(
        barcode: String,
        in catalogue: BarcodeIdentity.Catalogue
    ) async -> BarcodeIdentity? {
        guard let url = Self.url(barcode: barcode, host: catalogue.rawValue) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.timeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return nil
        }

        guard
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode),
            let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
            envelope.status == 1,
            let product = envelope.product,
            let name = product.productName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        else {
            return nil
        }

        return BarcodeIdentity(
            barcode: barcode,
            name: name,
            brand: product.brands?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty,
            catalogue: catalogue
        )
    }

    /// `fields=` keeps the response at a couple of hundred bytes — this
    /// only needs a name to show the user, never nutrition.
    private static func url(barcode: String, host: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/v2/product/\(barcode).json"
        components.queryItems = [URLQueryItem(name: "fields", value: "product_name,brands")]
        return components.url
    }

    /// Same envelope every Open *Facts* catalogue returns: `status` is 1
    /// on a hit, 0 on a miss, and the miss still arrives as HTTP 200.
    private struct Envelope: Decodable {
        let status: Int
        let product: Product?

        struct Product: Decodable {
            let productName: String?
            let brands: String?

            enum CodingKeys: String, CodingKey {
                case productName = "product_name"
                case brands      = "brands"
            }
        }
    }
}
