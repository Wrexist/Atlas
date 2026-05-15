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
                    .font(.system(size: 11, weight: .semibold))
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
        let tint  = category.flatMap(Self.tint(for:)) ?? AppColor.textSecondary

        return HStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label)
                        .font(AppFont.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer(minLength: 0)
                    Text("\(totals.calories) kcal")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(totals.calories == 0 ? AppColor.textSecondary : AppColor.textPrimary)
                        .contentTransition(.numericText())
                }
                progressBar(width: barWidth(for: totals.calories), tint: tint)
                if totals.entryCount > 0 {
                    Text(macroLine(for: totals))
                        .font(.system(size: 11))
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

    /// Per-category accent — picked to read as warm-to-cool through
    /// the day. Breakfast = sunrise orange, dinner = dusk indigo.
    private static func tint(for category: MealCategory) -> Color {
        switch category {
        case .breakfast: Color(red: 1.0,  green: 0.62, blue: 0.30)
        case .lunch:     Color(red: 0.98, green: 0.78, blue: 0.20)
        case .dinner:    Color(red: 0.48, green: 0.50, blue: 0.92)
        case .snack:     Color(red: 0.36, green: 0.78, blue: 0.55)
        }
    }

    private static func rowAccessibilityLabel(
        label: String,
        totals: LifestyleDataLogic.CategoryTotals
    ) -> String {
        if totals.entryCount == 0 {
            return "\(label), no entries"
        }
        let items = totals.entryCount == 1 ? "1 item" : "\(totals.entryCount) items"
        return "\(label), \(items), \(totals.calories) kilocalories, " +
            "\(totals.proteinG) grams protein, \(totals.carbsG) grams carbs, \(totals.fatG) grams fat."
    }
}
