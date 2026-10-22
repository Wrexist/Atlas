import SwiftUI

struct MealNutrientCoverage {
    let total: Double?
    let missing: Int
    static func derive(entries: [MealEntry], nutrient: KeyPath<MealFoodComponent, Double?>) -> Self {
        var values: [Double] = []
        var missing = 0
        for entry in entries {
            guard let foods = entry.components, !foods.isEmpty else { missing += 1; continue }
            for food in foods {
                if let value = food[keyPath: nutrient] { values.append(value) }
                else { missing += 1 }
            }
        }
        return Self(total: values.isEmpty ? nil : values.reduce(0, +), missing: missing)
    }
}

struct MealNutrientDetails: View {
    let components: [MealFoodComponent]
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            row("Fiber", value: MealFoodComponent.completeTotal(components.map(\.fiberG)))
            row("Total sugars", value: MealFoodComponent.completeTotal(components.map(\.sugarsG)))
            Text("Not available for every food.")
                .font(AppFont.caption2).foregroundStyle(AppColor.textSecondary)
        }
    }
    private func row(_ title: LocalizedStringKey, value: Double?) -> some View {
        LabeledContent(title, value: value.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) g" } ?? "Unavailable")
            .font(AppFont.callout)
    }
}

struct DailyMealNutrientsCard: View {
    let entries: [MealEntry]
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Fiber & sugar").font(AppFont.headline)
                row("Fiber", coverage: .derive(entries: entries, nutrient: \.fiberG))
                row("Total sugars", coverage: .derive(entries: entries, nutrient: \.sugarsG))
                Text("From foods with label data.")
                    .font(AppFont.caption2).foregroundStyle(AppColor.textSecondary)
            }
        }
    }
    private func row(_ title: LocalizedStringKey, coverage: MealNutrientCoverage) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            LabeledContent(title, value: coverage.total.map {
                "\($0.formatted(.number.precision(.fractionLength(0...1)))) g\(coverage.missing > 0 ? " · Partial" : "")"
            } ?? "Unavailable")
            if coverage.missing > 0 {
                Text("^[\(coverage.missing) item](inflect: true) without label data")
                    .font(AppFont.caption2).foregroundStyle(AppColor.textSecondary)
            }
        }
    }
}
