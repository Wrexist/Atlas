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
            pricePer100g: item.price?.scaled(by: 100 / item.grams),
            isDrink: scan.insight.kind == .drink ? true : nil
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
            fetchedAt: now,
            readFromPackage: true,
            isDrink: scan.insight.kind == .drink
        )
    }

    /// A database product with the gaps the scanner could fill: many
    /// Open Food Facts records lack a serving, a net weight or any
    /// nutrition at all, which hides the Serving and Whole-pack shortcuts
    /// or would log 0 kcal. Known values are never overwritten — the
    /// database's label data beats an estimate.
    static func product(_ product: ScannedProduct, fillingFrom scan: MealScannerService.SmartScan) -> ScannedProduct {
        let package = scan.package
        var nutriments = product.hasNutrition ? product.per100g : scan.items.first.map(Self.per100g(of:)) ?? product.per100g
        nutriments.micros = (nutriments.micros ?? Micronutrients())
            .filling(from: scan.items.first?.per100g?.micros).nonEmpty
        // A database record with no product name is titled with its brand
        // or "Unknown product"; Atlas AI's identification reads better.
        let identified = product.nameMissing == true ? scan.items.first : nil
        return ScannedProduct(
            barcode: product.barcode,
            name: identified?.name ?? product.name,
            brand: product.brand ?? identified?.brand,
            imageURL: product.imageURL,
            servingSizeText: product.servingGrams == nil ? (package?.servingLabel ?? product.servingSizeText) : product.servingSizeText,
            servingGrams: product.servingGrams ?? package?.servingGrams,
            packageGrams: product.packageGrams ?? package?.totalGrams,
            per100g: nutriments,
            nutriScore: product.nutriScore,
            novaGroup: product.novaGroup,
            fetchedAt: product.fetchedAt,
            nutritionMissing: !product.hasNutrition && scan.items.isEmpty,
            readFromPackage: product.readFromPackage,
            isDrink: product.isDrink == true || scan.insight.kind == .drink,
            nameMissing: identified == nil ? product.nameMissing : false
        )
    }

    /// A barcode product saved to My Foods, so it can be found and
    /// re-logged from the library without the barcode or the network.
    static func customFood(from product: ScannedProduct, pricePer100g: FoodPriceEstimate?, id: UUID = UUID()) -> CustomFood {
        let serving = product.oneServingGrams
        return CustomFood(
            id: id,
            name: product.name,
            brand: product.brand,
            per100g: product.per100g,
            servingGrams: serving,
            servingLabel: product.servingSizeText
                ?? (product.servingGrams == nil && serving != nil
                    ? String(localized: "1 package", comment: "Serving label for a custom food whose serving is the whole package.")
                    : nil),
            pricePer100g: pricePer100g,
            imageURL: product.imageURL,
            isDrink: product.isDrink,
            barcode: product.barcode.allSatisfy(\.isNumber) ? product.barcode : nil
        )
    }

    /// The user's own food for a scanned barcode, newest first, so a
    /// product they saved or corrected wins over the database record.
    static func myFood(forBarcode barcode: String, in foods: [CustomFood]) -> CustomFood? {
        foods.filter { $0.barcode == barcode }.max { $0.updatedAt < $1.updatedAt }
    }

    /// A barcode product with the nutrition the user typed in for one
    /// portion, as a My Foods entry under that barcode. Reuses `existing`'s
    /// id so a second correction replaces the first. Nil when the portion
    /// has no weight to scale from.
    static func correctedFood(
        _ product: ScannedProduct, portionGrams: Double, typed: LoggableMeal, existing: CustomFood?
    ) -> CustomFood? {
        guard portionGrams.isFinite, portionGrams > 0 else { return nil }
        let scale = 100 / portionGrams
        var food = customFood(from: product, pricePer100g: existing?.pricePer100g, id: existing?.id ?? UUID())
        food.per100g = ScannedProduct.Nutriments(
            calories: (Double(typed.calories) * scale).rounded(),
            proteinG: (Double(typed.proteinG) * scale * 10).rounded() / 10,
            carbsG: (Double(typed.carbsG) * scale * 10).rounded() / 10,
            fatG: (Double(typed.fatG) * scale * 10).rounded() / 10,
            fiberG: nil,
            sugarsG: nil
        )
        return food
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
            fiberG: n.fiberG.map(r), sugarsG: n.sugarsG.map(r), micros: n.micros
        )
    }
}
