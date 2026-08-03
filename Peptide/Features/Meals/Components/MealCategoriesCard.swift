import SwiftUI

/// Per-meal-category breakdown card shown under the macro rings on
/// the Lifestyle tab. Four rows (Breakfast / Lunch / Dinner / Snack)
/// each with the category's calorie total + a thin progress bar
/// scaled to the day's biggest meal. An optional "Other" row
/// surfaces calories logged before MealEntry existed (or via flows
/// that haven't been upgraded yet) so the rings and the breakdown
/// always reconcile.
///
/// Tapping a row drills into a (future) per-meal detail sheet — for
/// v1 it's a static read-out so users see where today's calories
/// went without leaving the tab.
struct MealCategoriesCard: View {
    let breakdown: LifestyleDataLogic.CategoryBreakdown

    private var maxCalories: Int {
        max(
            breakdown.breakfast.calories,
            breakdown.lunch.calories,
            breakdown.dinner.calories,
            breakdown.snack.calories,
            breakdown.other.calories,
            1     // floor so a fully-empty day doesn't divide by zero
        )
    }

    private var totalCalories: Int { breakdown.totalCalories }

    var body: some View {
        GlassCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                header
                rows
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Meals today")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.accentLight.opacity(0.85))
                Text("\(totalCalories) kcal logged")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
    }

    private var rows: some View {
        VStack(spacing: Spacing.sm) {
            ForEach(Array(breakdown.orderedRows.enumerated()), id: \.offset) { _, row in
                rowView(category: row.0, totals: row.1)
            }
        }
    }

    private func rowView(
        category: MealCategory?,
        totals: LifestyleDataLogic.CategoryTotals
    ) -> some View {
        let label = category?.displayName ?? "Other"
        let icon  = category?.icon       ?? "ellipsis.circle.fill"
        let tint  = category?.tint       ?? AppColor.textSecondary

        return HStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label)
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer(minLength: 0)
                    Text("\(totals.calories) kcal")
                        .font(AppFont.scaled(13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(totals.calories == 0 ? AppColor.textSecondary : AppColor.textPrimary)
                        .contentTransition(.numericText())
                }
                progressBar(width: barWidth(for: totals.calories), tint: tint)
                if totals.entryCount > 0 {
                    Text(macroLine(for: totals))
                        .font(AppFont.scaled(11))
                        .foregroundStyle(AppColor.textSecondary)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.rowAccessibilityLabel(label: label, totals: totals))
    }

    private func progressBar(width fraction: Double, tint: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.7))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(tint.opacity(0.85))
                    .frame(width: max(2, proxy.size.width * fraction))
            }
        }
        .frame(height: 6)
    }

    private func barWidth(for calories: Int) -> Double {
        guard maxCalories > 0 else { return 0 }
        return min(1.0, Double(calories) / Double(maxCalories))
    }

    private func macroLine(for totals: LifestyleDataLogic.CategoryTotals) -> String {
        let entries = totals.entryCount == 1 ? "1 item" : "\(totals.entryCount) items"
        return "\(entries) · \(totals.proteinG)P · \(totals.carbsG)C · \(totals.fatG)F"
    }

    private static func rowAccessibilityLabel(
        label: String,
        totals: LifestyleDataLogic.CategoryTotals
    ) -> String {
        if totals.entryCount == 0 {
            return String(
                localized: "\(label), no entries",
                comment: "VoiceOver: empty meal-category row on the breakdown card."
            )
        }
        let items = totals.entryCount == 1
            ? String(localized: "1 item", comment: "Singular form for the per-meal entry count.")
            : String(localized: "\(totals.entryCount) items", comment: "Plural form for the per-meal entry count.")
        let kcal = String(
            localized: "\(totals.calories) kilocalories",
            comment: "VoiceOver readout of total calories in a meal category."
        )
        let protein = String(
            localized: "\(totals.proteinG) grams protein",
            comment: "VoiceOver readout of protein grams in a meal category."
        )
        let carbs = String(
            localized: "\(totals.carbsG) grams carbs",
            comment: "VoiceOver readout of carb grams in a meal category."
        )
        let fat = String(
            localized: "\(totals.fatG) grams fat",
            comment: "VoiceOver readout of fat grams in a meal category."
        )
        return "\(label), \(items), \(kcal), \(protein), \(carbs), \(fat)."
    }
}
