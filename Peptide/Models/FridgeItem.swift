import SwiftUI

/// Where an item is kept at home.
enum FridgePlace: String, Codable, CodingKeyRepresentable, CaseIterable, Identifiable, Sendable {
    case fridge, freezer, pantry

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .fridge:  "Fridge"
        case .freezer: "Freezer"
        case .pantry:  "Cupboard"
        }
    }

    var icon: String {
        switch self {
        case .fridge:  "refrigerator.fill"
        case .freezer: "snowflake"
        case .pantry:  "cabinet.fill"
        }
    }
}

/// A product the user has had at home: what it is, not how many are left.
/// Saved the first time it goes in and kept after it runs out, so buying
/// it again is a search and one tap.
struct FridgeProduct: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var brand: String?
    var barcode: String?
    /// The recipe library's ingredient key this product counts as, so
    /// recipes and the weekly shopping list know it is at home.
    var pantryKey: String?
    /// Printed or typed amount, e.g. "1 l" or "500 g".
    var amount: String?
    var place: FridgePlace = .fridge
    /// Days it kept, from the day it went in, the last time it was kept in
    /// each place; seeds the use-by date on the next re-add there.
    var shelfDaysByPlace: [FridgePlace: Int]?
    /// Saved before shelf life was kept per place: taken to be how long it
    /// keeps in `place`.
    var shelfDays: Int?
    var per100g: ScannedProduct.Nutriments?
    /// Open Food Facts packshot, when it came from a barcode.
    var imageURL: URL?
    /// True when a cut-out photo of it is stored on this device.
    var hasPhoto = false
    var lastAddedAt: Date?

    /// How long it kept in `place` last time, if it has been kept there.
    func shelfLife(in place: FridgePlace) -> Int? {
        shelfDaysByPlace?[place] ?? (place == self.place ? shelfDays : nil)
    }

    /// Remembers how long it kept in `place`, folding in a shelf life
    /// saved before they were kept per place.
    mutating func learnShelfLife(_ days: Int, in place: FridgePlace) {
        var learned = shelfDaysByPlace ?? [:]
        if let shelfDays, learned[self.place] == nil { learned[self.place] = shelfDays }
        learned[place] = days
        shelfDaysByPlace = learned
        shelfDays = nil
    }

    var displayName: String {
        guard let brand, !brand.isEmpty, !name.localizedCaseInsensitiveContains(brand) else { return name }
        return "\(brand) \(name)"
    }
}

/// One thing in the fridge right now.
struct FridgeItem: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var productID: UUID
    var count = 1
    var place: FridgePlace
    /// Start of the use-by day; nil when it doesn't spoil or nobody knows.
    var expiresOn: Date?
    var addedAt: Date
}
