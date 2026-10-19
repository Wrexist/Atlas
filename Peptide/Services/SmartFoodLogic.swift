import Foundation

/// Turns a smart scan into the app's existing food shapes, so a photo,
/// a barcode or a typed name all land in the same review and library
/// flows the rest of the app already uses.
enum SmartFoodLogic {

    /// The first described food as a library entry, ready for the editor.
    /// One serving is the package's own serving when known, else the
    /// amount the scanner saw; price is normalised to per 100 g.
    static func customFood(from scan: MealScannerService.SmartScan, id: UUID = UUID()) -> CustomFood? {
        guard let item = scan.items.first else { return nil }
        let servingGrams = scan.package?.servingGrams ?? item.grams
        let servingLabel = scan.package?.servingLabel ?? item.quantityLabel
        return CustomFood(
            id: id,
            name: item.name,
            brand: item.brand,
            per100g: rounded(per100g(of: item)),
            servingGrams: servingGrams > 0 ? servingGrams.rounded() : nil,
            servingLabel: servingLabel.nilIfEmpty,
            pricePer100g: item.price?.scaled(by: 100 / item.grams)
        )
    }

    /// A package photo read by the scanner, as the `ScannedProduct` the
    /// barcode review screen already knows how to portion and log. The
    /// scanned barcode is kept so history and re-scans line up with it.
    static func product(from scan: MealScannerService.SmartScan, barcode: String, now: Date = Date()) -> ScannedProduct? {
        guard let item = scan.items.first else { return nil }
        return ScannedProduct(
            barcode: barcode,
            name: item.name,
            brand: item.brand,
            imageURL: nil,
            servingSizeText: scan.package?.servingLabel ?? item.quantityLabel.nilIfEmpty,
            servingGrams: scan.package?.servingGrams ?? item.grams,
            packageGrams: scan.package?.totalGrams,
            per100g: per100g(of: item),
            nutriScore: nil,
            novaGroup: nil,
            fetchedAt: now
        )
    }

    /// A database product with the gaps the scanner could fill: many
    /// Open Food Facts records lack a serving or a net weight, which hides
    /// the Serving and Whole-pack shortcuts. Known values are never
    /// overwritten — the database's label data beats an estimate.
    static func product(_ product: ScannedProduct, fillingFrom scan: MealScannerService.SmartScan) -> ScannedProduct {
        guard let package = scan.package else { return product }
        let servingGrams = product.servingGrams ?? package.servingGrams
        return ScannedProduct(
            barcode: product.barcode,
            name: product.name,
            brand: product.brand,
            imageURL: product.imageURL,
            servingSizeText: product.servingGrams == nil ? (package.servingLabel ?? product.servingSizeText) : product.servingSizeText,
            servingGrams: servingGrams,
            packageGrams: product.packageGrams ?? package.totalGrams,
            per100g: product.per100g,
            nutriScore: product.nutriScore,
            novaGroup: product.novaGroup,
            fetchedAt: product.fetchedAt
        )
    }

    /// A barcode product saved to My Foods, so it can be found and
    /// re-logged from the library without the barcode or the network.
    static func customFood(from product: ScannedProduct, pricePer100g: FoodPriceEstimate?) -> CustomFood {
        CustomFood(
            name: product.name,
            brand: product.brand,
            per100g: product.per100g,
            servingGrams: product.servingGrams ?? product.packageGrams,
            servingLabel: product.servingSizeText
                ?? (product.servingGrams == nil && product.packageGrams != nil ? "1 package" : nil),
            pricePer100g: pricePer100g
        )
    }

    /// Exact smart-scan values when present; else derived from the rounded
    /// totals of the depicted amount (legacy route).
    static func per100g(of item: MealScannerService.ScannedFoodItem) -> ScannedProduct.Nutriments {
        if let exact = item.per100g { return exact }
        let basis = item.grams > 0 ? item.grams : 100
        return ScannedProduct.Nutriments(
            calories: Double(item.calories) / basis * 100,
            proteinG: Double(item.proteinG) / basis * 100,
            carbsG: Double(item.carbsG) / basis * 100,
            fatG: Double(item.fatG) / basis * 100,
            fiberG: nil,
            sugarsG: nil
        )
    }

    /// One decimal is all a nutrition label carries; anything more is
    /// false precision that makes the editor read like a spreadsheet.
    private static func rounded(_ n: ScannedProduct.Nutriments) -> ScannedProduct.Nutriments {
        func r(_ value: Double) -> Double { (value * 10).rounded() / 10 }
        return ScannedProduct.Nutriments(
            calories: n.calories.rounded(), proteinG: r(n.proteinG), carbsG: r(n.carbsG), fatG: r(n.fatG),
            fiberG: n.fiberG.map(r), sugarsG: n.sugarsG.map(r)
        )
    }
}
