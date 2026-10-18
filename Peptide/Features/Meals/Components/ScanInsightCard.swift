import SwiftUI

/// The scanner's reading of the whole photo or product, above the
/// per-item rows: what kind of thing it is, a one-line summary, what the
/// selected amount roughly costs, and the model's specific tips — the
/// frying oil it can't see, the milk it can't tell apart.
struct ScanInsightCard: View {
    let insight: ScanInsight
    let totalPrice: FoodPriceEstimate?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Label(insight.kind.displayName, systemImage: insight.kind.icon)
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background { Capsule().fill(AppColor.accentPrimary.opacity(0.15)) }
                Spacer(minLength: Spacing.sm)
                if let totalPrice {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(totalPrice.formatted)
                            .font(AppFont.scaled(16, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColor.textPrimary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(basisCaption(totalPrice.basis))
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textTertiary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if !insight.summary.isEmpty {
                Text(insight.summary)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(insight.tips, id: \.self) { tip in
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Image(systemName: "lightbulb.fill")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(AppColor.warning)
                    Text(tip)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    private func basisCaption(_ basis: FoodPriceEstimate.Basis) -> String {
        switch basis {
        case .store:      String(localized: "Store price", comment: "Price estimate basis")
        case .restaurant: String(localized: "Restaurant price", comment: "Price estimate basis")
        case .homemade:   String(localized: "Ingredient cost", comment: "Price estimate basis")
        }
    }
}
