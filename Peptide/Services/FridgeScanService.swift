import UIKit

/// Reads a photo of a fridge, a shelf or a shopping haul through the
/// proxy's `fridge-scan` route: every product in it, with where it sat in
/// the photo so `FridgeLiftEngine` can cut it out.
enum FridgeScanService {

    struct Found: Identifiable, Sendable {
        let id = UUID()
        let name: String
        let brand: String?
        let amount: String?
        let count: Int
        let place: FridgePlace
        let shelfDays: Int?
        /// A date legible on the pack, at the start of its day.
        let printedExpiry: Date?
        let pantryKey: String?
        /// Where it sat in the photo: 0…1, top-left origin.
        let box: CGRect
        let per100g: ScannedProduct.Nutriments?
    }

    /// One photo of a whole fridge spends one of the week's free scans.
    @MainActor
    static func scan(_ photo: UIImage, pantryKeys: [String]) async throws -> [Found] {
        let payload: [String: Any] = [
            "image": try MealScannerService.shared.uploadJPEG(photo).base64EncodedString(),
            "locale": MealScannerService.localeIdentifier,
            "pantry_keys": pantryKeys,
        ]
        let data = try await MealScannerService.shared.post(payload, toSiblingRoute: "fridge-scan", metered: true)
        return try parse(data, pantryKeys: Set(pantryKeys), calendar: .current)
    }

    // MARK: - Parsing

    private struct Response: Decodable {
        let result: Result
    }

    private struct Result: Decodable {
        let isGroceries: Bool
        let items: [Item]

        enum CodingKeys: String, CodingKey {
            case items
            case isGroceries = "is_groceries"
        }
    }

    private struct Item: Decodable {
        struct Box: Decodable {
            let x, y, width, height: Double
        }

        let name: String
        let brand: String?
        let amount: String?
        let count: Int
        let place: String
        let shelfDays: Int?
        let printedExpiry: String?
        let pantryKey: String?
        let box: Box
        let kcal100g: Double?
        let protein100g: Double?
        let carbs100g: Double?
        let fat100g: Double?

        enum CodingKeys: String, CodingKey {
            case name, brand, amount, count, place, box
            case shelfDays = "shelf_days"
            case printedExpiry = "printed_expiry"
            case pantryKey = "pantry_key"
            case kcal100g = "kcal_100g"
            case protein100g = "protein_100g"
            case carbs100g = "carbs_100g"
            case fat100g = "fat_100g"
        }
    }

    /// The groceries in a proxy response. Keys outside the library are
    /// dropped and boxes clamped to the photo; a photo with nothing in it
    /// throws `noFoodDetected`.
    static func parse(_ data: Data, pantryKeys: Set<String>, calendar: Calendar) throws -> [Found] {
        let result = try JSONDecoder().decode(Response.self, from: data).result
        let found = result.items.compactMap { found(from: $0, pantryKeys: pantryKeys, calendar: calendar) }
        guard result.isGroceries, !found.isEmpty else { throw MealScannerService.ScanError.noFoodDetected }
        return found
    }

    private static func found(from item: Item, pantryKeys: Set<String>, calendar: Calendar) -> Found? {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let box = CGRect(x: item.box.x, y: item.box.y, width: item.box.width, height: item.box.height)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !name.isEmpty, !box.isNull, box.width > 0.01, box.height > 0.01 else { return nil }
        return Found(
            name: name,
            brand: item.brand?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            amount: item.amount?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            count: min(max(1, item.count), 99),
            place: FridgePlace(rawValue: item.place) ?? .fridge,
            shelfDays: item.shelfDays.map { min(max(0, $0), 730) },
            printedExpiry: item.printedExpiry.flatMap { day(from: $0, calendar: calendar) },
            pantryKey: item.pantryKey.flatMap { pantryKeys.contains($0) ? $0 : nil },
            box: box,
            per100g: nutriments(item)
        )
    }

    private static func nutriments(_ item: Item) -> ScannedProduct.Nutriments? {
        guard let kcal = item.kcal100g else { return nil }
        return ScannedProduct.Nutriments(
            calories: max(0, kcal),
            proteinG: max(0, item.protein100g ?? 0),
            carbsG: max(0, item.carbs100g ?? 0),
            fatG: max(0, item.fat100g ?? 0),
            fiberG: nil,
            sugarsG: nil
        )
    }

    /// The model writes ISO dates, which are Gregorian whatever calendar
    /// the phone uses; only the time zone comes from `calendar`.
    static func day(from text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
