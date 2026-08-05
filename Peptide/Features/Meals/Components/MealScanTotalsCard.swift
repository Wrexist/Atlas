import SwiftUI

/// What the whole meal comes to, once the user has ticked and re-portioned.
///
/// The review screen used to end on the last item card, so the only total was
/// a caption in the header — the number the user is actually deciding on had
/// the smallest type on the screen. This gives it a card, and splits it into
/// the three macros with the share each contributes by energy.
struct MealScanTotalsCard: View {
    let calories: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int

    /// Energy shares, not gram shares. Four calories a gram for protein and
    /// carbohydrate, nine for fat — a gram split would show fat as a sliver
    /// of a meal it dominates.
    private var shares: (protein: Double, carbs: Double, fat: Double) {
        let p = Double(proteinG) * 4
        let c = Double(carbsG) * 4
        let f = Double(fatG) * 9
        let total = p + c + f
        guard total > 0 else { return (0, 0, 0) }
        return (p / total, c / total, f / total)
    }

    var body: some View {
        HStack(spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text("Total")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer(minLength: Spacing.sm)
                    Text("\(calories)")
                        .font(AppFont.scaled(24, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("kcal")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    macroRow("Protein", grams: proteinG, share: shares.protein, tint: AppColor.macroProtein)
                    macroRow("Carbs", grams: carbsG, share: shares.carbs, tint: AppColor.macroCarbs)
                    macroRow("Fat", grams: fatG, share: shares.fat, tint: AppColor.macroFat)
                }
            }

            ring
        }
        .padding(Spacing.lg)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius, tinted: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Total \(calories) kilocalories. "
            + "Protein \(proteinG) grams, carbohydrate \(carbsG) grams, fat \(fatG) grams."
        )
    }

    private func macroRow(_ title: String, grams: Int, share: Double, tint: Color) -> some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            Text("\(grams)g")
                .font(AppFont.scaled(13, weight: .bold))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
            Spacer(minLength: Spacing.xs)
            Text(share.formatted(.percent.precision(.fractionLength(0))))
                .font(AppFont.caption)
                .foregroundStyle(tint)
                .monospacedDigit()
        }
    }

    /// Three arcs on one track, drawn in the order they are listed so the
    /// legend reads clockwise from the top.
    private var ring: some View {
        ZStack {
            Circle()
                .stroke(AppColor.surfaceElevated, lineWidth: 12)

            arc(from: 0, to: shares.protein, tint: AppColor.macroProtein)
            arc(from: shares.protein, to: shares.protein + shares.carbs, tint: AppColor.macroCarbs)
            arc(from: shares.protein + shares.carbs, to: 1, tint: AppColor.macroFat)
        }
        .frame(width: 84, height: 84)
        .animation(AppAnimation.springSmooth, value: calories)
        .accessibilityHidden(true)
    }

    private func arc(from start: Double, to end: Double, tint: Color) -> some View {
        Circle()
            .trim(from: start, to: max(start, end))
            .stroke(tint, style: StrokeStyle(lineWidth: 12, lineCap: .butt))
            .rotationEffect(.degrees(-90))
    }
}
