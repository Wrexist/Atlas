#if DEBUG
import SwiftUI

/// Screenshot runs only. A simulator has no camera and no Vision instance
/// masks, so this draws a table of plates, hands the scan flow its
/// cut-outs, and keeps one table on the day so every table screen can be
/// captured.
@MainActor
enum TableScanFixture {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--table-scan-fixture")
            && UserDefaults.standard.bool(forKey: "com.peptidesai.app.screenshotMode.enabled")
    }

    private struct Dish {
        let name: String
        let kind: DishKind
        let calories: Int
        let protein: Int
        /// Where it sits in the photo, 0…1.
        let frame: CGRect
        let food: Color
        let toppings: [Color]
    }

    private static let photoSize = CGSize(width: 1200, height: 1500)

    private static let dishes: [Dish] = [
        Dish(name: "Tonkotsu ramen", kind: .food, calories: 640, protein: 32,
             frame: CGRect(x: 0.06, y: 0.08, width: 0.46, height: 0.368),
             food: AppColor.warning, toppings: [AppColor.success, AppColor.destructive, AppColor.textPrimary]),
        Dish(name: "Chicken karaage", kind: .food, calories: 520, protein: 38,
             frame: CGRect(x: 0.55, y: 0.12, width: 0.38, height: 0.304),
             food: AppColor.accentLight, toppings: [AppColor.success, AppColor.warning]),
        Dish(name: "Gyoza", kind: .food, calories: 310, protein: 14,
             frame: CGRect(x: 0.1, y: 0.55, width: 0.36, height: 0.288),
             food: AppColor.surfaceSecondary, toppings: [AppColor.warning, AppColor.success]),
        Dish(name: "Iced matcha latte", kind: .drink, calories: 180, protein: 6,
             frame: CGRect(x: 0.6, y: 0.58, width: 0.26, height: 0.208),
             food: AppColor.success, toppings: [AppColor.textPrimary]),
    ]

    // MARK: - Scan flow

    static var photo: UIImage {
        UIGraphicsImageRenderer(size: photoSize).image { context in
            UIColor(AppColor.surfaceSecondary).setFill()
            context.fill(CGRect(origin: .zero, size: photoSize))
            for dish in dishes {
                let rect = CGRect(
                    x: dish.frame.minX * photoSize.width, y: dish.frame.minY * photoSize.height,
                    width: dish.frame.width * photoSize.width, height: dish.frame.height * photoSize.height
                )
                plate(dish, rim: false).draw(in: rect)
            }
        }
    }

    static func reviewDishes() -> [ReviewDish] {
        dishes.map { dish in
            var review = ReviewDish(.init(id: UUID(), sticker: plate(dish, rim: true), frame: dish.frame))
            review.kind = dish.kind
            review.reading = .read(reading(dish))
            return review
        }
    }

    // MARK: - A kept table

    /// Keeps one dinner table today, unless one is already on file.
    static func seedTable(in dataStore: DataStore) async {
        let store = TableMomentStore.shared
        guard store.moments(on: Date()).isEmpty else { return }
        let date = Date()
        let kept = dishes.map { dish in
            TableMomentStore.Draft.Dish(
                entry: reading(dish).entry(id: UUID(), name: dish.name, date: date, category: .dinner),
                kind: dish.kind,
                sticker: plate(dish, rim: true)
            )
        }
        await store.keep(.init(date: date, category: .dinner, dishes: kept), in: dataStore)
        store.clearProgress()
        if var moment = store.moments.first {
            moment.note = "Friday dinner with the team, the ramen was unreal."
            moment.dishes[0].rating = 5
            moment.dishes[0].isFavorite = true
            store.update(moment)
        }
    }

    // MARK: - Drawing

    private static func reading(_ dish: Dish) -> TableDishReader.Reading {
        TableDishReader.reading(
            insight: ScanInsight(kind: dish.kind == .drink ? .drink : .meal, title: dish.name, summary: "", tips: []),
            items: [MealScannerService.ScannedFoodItem(
                name: dish.name, quantityLabel: "1 serving", grams: 300,
                calories: dish.calories, proteinG: dish.protein, carbsG: 40, fatG: 15, confidence: 0.9
            )]
        )
    }

    /// A plate seen from above: a white die-cut rim when it's a cut-out,
    /// the plate, the food, and a few toppings in fixed spots.
    private static func plate(_ dish: Dish, rim: Bool) -> UIImage {
        let side: CGFloat = 480
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let cg = context.cgContext
            func disc(_ inset: CGFloat, _ color: Color) {
                UIColor(color).setFill()
                cg.fillEllipse(in: CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2))
            }
            if rim { disc(0, AppColor.onAccent) }
            disc(rim ? 14 : 0, AppColor.textTertiary)
            disc(rim ? 30 : 16, AppColor.onAccent)
            disc(side * 0.2, dish.food)
            let spots: [CGPoint] = [
                CGPoint(x: 0.38, y: 0.36), CGPoint(x: 0.6, y: 0.4), CGPoint(x: 0.45, y: 0.6),
                CGPoint(x: 0.62, y: 0.62), CGPoint(x: 0.5, y: 0.47),
            ]
            for (index, spot) in spots.enumerated() {
                UIColor(dish.toppings[index % dish.toppings.count]).setFill()
                let radius = side * (index.isMultiple(of: 2) ? 0.07 : 0.05)
                cg.fillEllipse(in: CGRect(x: spot.x * side - radius, y: spot.y * side - radius,
                                          width: radius * 2, height: radius * 2))
            }
        }
    }
}
#endif
