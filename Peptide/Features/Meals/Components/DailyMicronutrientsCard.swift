import SwiftUI

/// The day's vitamins and minerals against their daily reference values.
/// Collapsed to one summary line by default so the meals screen stays
/// calm; the choice is remembered on this device.
struct DailyMicronutrientsCard: View {
    let entries: [MealEntry]

    @AppStorage("meals.micronutrientsExpanded") private var isExpanded = false

    var body: some View {
        let intakes = MicronutrientEngine.dailyIntakes(entries)
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                header(knownCount: intakes.filter { $0.total != nil }.count, total: intakes.count)
                if isExpanded {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        ForEach(intakes, id: \.nutrient) { MicronutrientRow(intake: $0) }
                        Text("From foods with label data.")
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(knownCount: Int, total: Int) -> some View {
        Button {
            Haptics.selection()
            AppAnimation.with(AppAnimation.settle) { isExpanded.toggle() }
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "leaf.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.accentPrimary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Micronutrients")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Group {
                        if knownCount == 0 {
                            Text("Scan a barcode or a photo to see vitamins and minerals.")
                        } else {
                            Text("Data for \(knownCount) of \(total) nutrients")
                                .contentTransition(.numericText())
                        }
                    }
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(AppFont.scaled(11, weight: .bold))
                    .foregroundStyle(AppColor.accentLight)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .minimumHitArea()
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

/// One nutrient: its name, the day's amount against the reference, and
/// a bar that fills toward it. Sodium is a ceiling, so its bar turns to
/// the warning colour once the day goes over.
private struct MicronutrientRow: View {
    let intake: MicronutrientEngine.Intake

    private var nutrient: MicronutrientEngine.Nutrient { intake.nutrient }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(nutrient.title)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textPrimary)
                if nutrient.isLimit {
                    Text("Max")
                        .font(AppFont.badgeSmall)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: Spacing.sm)
                Text(amountText)
                    .font(AppFont.callout)
                    .monospacedDigit()
                    .foregroundStyle(intake.isOverLimit ? AppColor.warning : AppColor.textSecondary)
                    .contentTransition(.numericText())
                    .appAnimation(AppAnimation.settle, value: intake.total)
            }
            GlassProgressBar(
                progress: intake.fraction ?? 0,
                gradient: intake.isOverLimit ? [AppColor.warning, AppColor.warning] : nil
            )
        }
        .accessibilityElement(children: .combine)
    }

    private var amountText: String {
        guard let total = intake.total else { return String(localized: "Unavailable") }
        let unit = nutrient.unit.symbol
        let amount = "\(Self.format(total)) / \(Self.format(nutrient.dailyReference)) \(unit)"
        return intake.missing > 0 ? String(localized: "\(amount) · Partial") : amount
    }

    /// Whole numbers once a value reaches 10; one decimal below, where
    /// iron and the vitamins live.
    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 10 ? 0...1 : 0...0)))
    }
}

private extension MicronutrientEngine.Nutrient {
    var title: LocalizedStringKey {
        switch self {
        case .sodium:     "Sodium"
        case .potassium:  "Potassium"
        case .iron:       "Iron"
        case .calcium:    "Calcium"
        case .vitaminD:   "Vitamin D"
        case .vitaminB12: "Vitamin B12"
        }
    }
}
