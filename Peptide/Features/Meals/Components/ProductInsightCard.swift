import SwiftUI

/// Atlas AI's take on a scanned product, under the barcode review: what
/// the chosen amount roughly costs, one-tap amounts that suit this
/// product ("1 glass 250 ml", "whole pack 400 g"), and the model's tips.
/// Purely additive — the review works the same while it loads or if it
/// never arrives.
struct ProductInsightCard: View {
    let scan: MealScannerService.SmartScan?
    let isLoading: Bool
    /// Grams in the portion currently selected, for the price line.
    let portionGrams: Double?
    let onPickPortion: (Double) -> Void

    private var item: MealScannerService.ScannedFoodItem? { scan?.items.first }

    private var portionPrice: FoodPriceEstimate? {
        guard let item, let price = item.price, let portionGrams else { return nil }
        return price.scaled(by: portionGrams / item.grams)
    }

    var body: some View {
        GlassCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "sparkles")
                        .font(AppFont.scaled(11, weight: .bold))
                        .foregroundStyle(AppColor.accentPrimary)
                    Text("Atlas AI")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                    Spacer(minLength: Spacing.sm)
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else if let portionPrice {
                        Text(portionPrice.formatted)
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .accessibilityLabel("Estimated cost \(portionPrice.formatted)")
                    }
                }

                if isLoading {
                    Text("Estimating price and portions…")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
                } else if let scan {
                    if !scan.insight.summary.isEmpty {
                        Text(scan.insight.summary)
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let options = item?.portionOptions, !options.isEmpty {
                        portionChips(options)
                    }
                    ForEach(scan.insight.tips, id: \.self) { tip in
                        HStack(alignment: .top, spacing: Spacing.xs) {
                            Image(systemName: "lightbulb.fill")
                                .font(AppFont.scaled(11))
                                .foregroundStyle(AppColor.warning)
                            Text(tip)
                                .font(AppFont.caption2)
                                .foregroundStyle(AppColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .appAnimation(AppAnimation.springSnappy, value: isLoading)
    }

    private func portionChips(_ options: [FoodPortionOption]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(options) { option in
                    let isActive = portionGrams.map { abs($0 - option.grams) < 0.5 } ?? false
                    Button {
                        Haptics.selection()
                        onPickPortion(option.grams)
                    } label: {
                        Text(option.label)
                            .font(AppFont.scaled(11, weight: .semibold))
                            .foregroundStyle(isActive ? AppColor.onAccent : AppColor.textSecondary)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background {
                                Capsule().fill(isActive ? AppColor.accentPrimary : AppColor.surfaceElevated)
                            }
                    }
                    .buttonStyle(.plain)
                    .minimumHitArea()
                }
            }
        }
    }
}
