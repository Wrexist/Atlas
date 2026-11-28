import SwiftUI

/// The full nutrition label for one portion or one logged meal: energy,
/// each macro with what it is made of indented under it, then
/// cholesterol, sodium and potassium, then whichever vitamins and
/// minerals are known.
struct NutritionFactsCard: View {
    private typealias Engine = NutritionFactsEngine

    /// What the amounts describe, e.g. "150 g".
    let portionLabel: String?
    private let amounts: [Engine.Nutrient: Double]
    /// Values worked out rather than stated, shown with "≈".
    private let estimates: Set<Engine.Nutrient>

    @ScaledMetric(relativeTo: .subheadline) private var iconColumn: CGFloat = 20

    init(per100g: ScannedProduct.Nutriments, grams: Double, portionLabel: String?) {
        self.portionLabel = portionLabel
        amounts = Self.collect { Engine.amount($0, per100g: per100g, grams: grams) }
        estimates = Set(Engine.Nutrient.allCases.filter { Engine.isEstimate($0, in: per100g) })
    }

    /// A product's label for the portion being logged; a drink's portion
    /// reads in millilitres like its portion picker.
    init(product: ScannedProduct, grams: Double) {
        let label = product.isDrink == true
            ? "\(Int(grams.rounded())) ml"
            : Engine.formatted(grams, unit: .grams)
        self.init(per100g: product.per100g, grams: grams, portionLabel: label)
    }

    init(components: [MealFoodComponent]) {
        let grams = components.map(\.grams).reduce(0, +)
        portionLabel = grams.isFinite && grams > 0 ? Engine.formatted(grams, unit: .grams) : nil
        amounts = Self.collect { Engine.amount($0, in: components) }
        estimates = Set(Engine.Nutrient.allCases.filter { nutrient in
            components.contains { Engine.isEstimate(nutrient, in: $0.per100g) }
        })
    }

    private static func collect(_ amount: (Engine.Nutrient) -> Double?) -> [Engine.Nutrient: Double] {
        Engine.Nutrient.allCases.reduce(into: [:]) { result, nutrient in
            result[nutrient] = amount(nutrient)
        }
    }

    private var visibleGroups: [Engine.Group] {
        Engine.groups.filter { group in !group.hidesUnknown || group.parts.contains { amounts[$0] != nil } }
    }

    private var hasUnknown: Bool {
        visibleGroups.contains { group in
            !group.hidesUnknown && ([group.total].compactMap { $0 } + group.parts).contains { amounts[$0] == nil }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleGroups.enumerated()), id: \.offset) { index, group in
                    // The known vitamins and minerals continue the mineral rows
                    // above instead of opening a group of their own.
                    if index > 0 && !group.hidesUnknown {
                        Divider()
                            .overlay(AppColor.glassBorder)
                            .padding(.vertical, Spacing.sm)
                    }
                    groupView(group)
                        .padding(.top, index > 0 && group.hidesUnknown ? Spacing.sm : 0)
                }
            }
            if hasUnknown || !estimates.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    if !estimates.isEmpty {
                        Text("≈ Estimated: total fat minus saturated fat. Not on the label.")
                    }
                    if hasUnknown {
                        Text("A dash means the label or scan doesn't state it.")
                    }
                }
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.leading, iconColumn + Spacing.sm)
                .padding(.top, Spacing.xxs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text("Nutrition facts")
                .font(AppFont.scaled(20, weight: .bold, relativeTo: .title3))
                .foregroundStyle(AppColor.textPrimary)
            Spacer(minLength: 0)
            if let portionLabel {
                Text("Per \(portionLabel)")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func groupView(_ group: Engine.Group) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let total = group.total {
                row(total, style: .total)
            }
            ForEach(group.parts.filter { !group.hidesUnknown || amounts[$0] != nil }) { part in
                row(part, style: group.total == nil ? .standalone : .part)
            }
        }
    }

    private enum RowStyle { case total, part, standalone }

    private func row(_ nutrient: Engine.Nutrient, style: RowStyle) -> some View {
        let amount = amounts[nutrient]
        let emphasis: Font = style == .total ? AppFont.scaled(16, weight: .semibold, relativeTo: .subheadline) : AppFont.subheadline
        let ink = style == .part ? AppColor.textSecondary : AppColor.textPrimary
        return HStack(alignment: .center, spacing: Spacing.sm) {
            icon(for: nutrient)
                .frame(width: iconColumn, alignment: .center)
            Text(Self.title(nutrient))
                .font(emphasis)
                .foregroundStyle(ink)
                .padding(.leading, style == .part ? Spacing.md : 0)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.md)
            Text(verbatim: amount.map { (estimates.contains(nutrient) ? "≈ " : "") + Engine.formatted($0, unit: nutrient.unit) } ?? "–")
                .font(emphasis)
                .foregroundStyle(amount == nil ? AppColor.textTertiary : ink)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.title(nutrient)))
        .accessibilityValue(accessibilityValue(nutrient, amount: amount))
    }

    private func accessibilityValue(_ nutrient: Engine.Nutrient, amount: Double?) -> String {
        guard let amount else { return String(localized: "Not stated") }
        let value = Engine.formatted(amount, unit: nutrient.unit)
        return estimates.contains(nutrient) ? String(localized: "About \(value), estimated") : value
    }

    @ViewBuilder
    private func icon(for nutrient: Engine.Nutrient) -> some View {
        switch nutrient {
        case .energy:
            Image(systemName: "flame.fill")
                .font(AppFont.scaled(13, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(AppColor.macroCalories)
                .accessibilityHidden(true)
        case .carbs: MacroIcon(.carbs, size: 15, relativeTo: .subheadline).foregroundStyle(AppColor.macroCarbs)
        case .protein: MacroIcon(.protein, size: 15, relativeTo: .subheadline).foregroundStyle(AppColor.macroProtein)
        case .fat: MacroIcon(.fat, size: 15, relativeTo: .subheadline).foregroundStyle(AppColor.macroFat)
        default: Color.clear.frame(height: 1)
        }
    }

    private static func title(_ nutrient: Engine.Nutrient) -> LocalizedStringKey {
        switch nutrient {
        case .energy: "Energy"
        case .carbs: "Carbs"
        case .fiber: "Fiber"
        case .sugars: "Sugars"
        case .protein: "Protein"
        case .fat: "Fat"
        case .saturatedFat: "Saturated fat"
        case .unsaturatedFat: "Unsaturated fat"
        case .cholesterol: "Cholesterol"
        case .sodium: "Sodium"
        case .potassium: "Potassium"
        case .calcium: "Calcium"
        case .iron: "Iron"
        case .vitaminD: "Vitamin D"
        case .vitaminB12: "Vitamin B12"
        }
    }
}
