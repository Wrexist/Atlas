import UIKit

/// Reads one cut-out dish from a table photo: what it is and what it
/// holds, through the same smart scan the single-meal photo uses.
///
/// Each dish goes up on its own so every sticker gets its own name and
/// numbers; one call for the whole table would come back as a list with
/// no way to say which line belongs to which plate.
enum TableDishReader {

    struct Reading: Hashable {
        /// What the scan called the dish — offered as a one-tap name.
        let name: String
        let kind: DishKind
        let items: [EditableFoodItem]

        var calories: Int { items.reduce(0) { $0 + $1.calories } }
        var proteinG: Int { items.reduce(0) { $0 + $1.proteinG } }
        var carbsG: Int { items.reduce(0) { $0 + $1.carbsG } }
        var fatG: Int { items.reduce(0) { $0 + $1.fatG } }

        /// The diary line for this dish. One line per plate: a bowl of
        /// ramen is what the user ate, not noodles + egg + broth.
        func entry(id: UUID, name: String, date: Date, category: MealCategory) -> MealEntry {
            MealEntry(
                id: id, date: date, category: category, name: name,
                calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG,
                source: .photo, components: items.map(\.component)
            )
        }
    }

    /// Steers the model toward one dish rather than a scene.
    static let hint = "One dish cut out of a photo of a shared table, on a plain background."

    @MainActor
    static func read(_ sticker: UIImage, myFoods: [CustomFood]) async throws -> Reading {
        let scan = try await MealScannerService.shared.smartScan(
            image: flattened(sticker),
            hint: hint,
            corrections: ScanCorrectionMemory.shared.recent
        )
        guard !scan.items.isEmpty else { throw MealScannerService.ScanError.noFoodDetected }
        let grounded = await FoodGrounding.ground(scan.items, myFoods: myFoods)
        return reading(insight: scan.insight, items: grounded)
    }

    /// One item names itself; several are a dish only the scan's title
    /// can name.
    static func reading(insight: ScanInsight, items: [MealScannerService.ScannedFoodItem]) -> Reading {
        let editable = items.map(EditableFoodItem.init(from:))
        let title = insight.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = editable.count > 1 && !title.isEmpty ? title : (editable.first?.name ?? title)
        return Reading(name: name, kind: insight.kind == .drink ? .drink : .food, items: editable)
    }

    /// The sticker on white with a margin. The scan travels as JPEG, which
    /// has no alpha: left transparent, the cut-out would arrive on black.
    static func flattened(_ sticker: UIImage) -> UIImage {
        let margin = max(sticker.size.width, sticker.size.height) * 0.08
        let canvas = CGSize(width: sticker.size.width + margin * 2, height: sticker.size.height + margin * 2)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = sticker.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            sticker.draw(at: CGPoint(x: margin, y: margin))
        }
    }
}
