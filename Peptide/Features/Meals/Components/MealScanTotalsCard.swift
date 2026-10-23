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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Grows with the number inside it, capped so the macro grid beside
    /// it keeps room at the largest sizes.
    @ScaledMetric(relativeTo: .title3) private var ringDiameter: CGFloat = 96

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
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Total")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)

            HStack(spacing: Spacing.lg) {
                ring
                Grid(alignment: .leading, horizontalSpacing: Spacing.sm, verticalSpacing: Spacing.sm) {
                    macroRow("Protein", grams: proteinG, share: shares.protein, tint: AppColor.macroProtein)
                    macroRow("Carbs", grams: carbsG, share: shares.carbs, tint: AppColor.macroCarbs)
                    macroRow("Fat", grams: fatG, share: shares.fat, tint: AppColor.macroFat)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(Spacing.lg)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius, tinted: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Total \(calories) kilocalories. Protein \(proteinG) grams, carbohydrate \(carbsG) grams, fat \(fatG) grams."
        )
    }

    /// One grid row: name, grams and energy share each sit in their own
    /// column, so the numbers line up whatever the label widths.
    private func macroRow(_ title: LocalizedStringKey, grams: Int, share: Double, tint: Color) -> some View {
        GridRow {
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
            }
            .gridColumnAlignment(.leading)
            Text("\(grams) g")
                .font(AppFont.scaled(16, weight: .bold))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(AppAnimation.motionAware(AppAnimation.springSnappy, reduceMotion: reduceMotion), value: grams)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .gridColumnAlignment(.trailing)
            Text(share.formatted(.percent.precision(.fractionLength(0))))
                .font(AppFont.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(tint)
                .monospacedDigit()
                .frame(minWidth: 36, alignment: .trailing)
                .gridColumnAlignment(.trailing)
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
            arc(from: shares.protein + shares.carbs, to: shares.protein + shares.carbs + shares.fat, tint: AppColor.macroFat)

            VStack(spacing: 0) {
                Text("\(calories)")
                    .font(AppFont.scaled(20, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .animation(AppAnimation.motionAware(AppAnimation.springSnappy, reduceMotion: reduceMotion), value: calories)
                // The unit is in the card's spoken label; at accessibility
                // sizes the hole only fits the number.
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("kcal")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, Spacing.md)
        }
        .frame(width: min(ringDiameter, 140), height: min(ringDiameter, 140))
        .animation(AppAnimation.motionAware(AppAnimation.springSmooth, reduceMotion: reduceMotion), value: [proteinG, carbsG, fatG])
        .accessibilityHidden(true)
    }

    private func arc(from start: Double, to end: Double, tint: Color) -> some View {
        Circle()
            .trim(from: start, to: max(start, end))
            .stroke(tint, style: StrokeStyle(lineWidth: 12, lineCap: .butt))
            .rotationEffect(.degrees(-90))
    }
}
