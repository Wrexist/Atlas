import SwiftUI

/// The portion control shared by the barcode and food-library review
/// screens: a segmented switch between serving, package and grams,
/// over the matching detail — a servings stepper, the package weight, or
/// a gram slider with quick picks. One copy so the two flows can't drift.
/// A drink reads in millilitres with glass, can and bottle picks; a
/// millilitre counts as a gram, close enough for anything drinkable.
struct PortionPicker: View {
    let product: ScannedProduct
    @Binding var portion: ScannedProduct.Portion

    static let gramsStep: Double = 5
    static let quickGrams: [Double] = [50, 100, 200, 500]

    struct QuickPick: Sendable {
        let amount: Double
        let label: LocalizedStringResource
    }

    static let foodPicks: [QuickPick] = quickGrams.map {
        QuickPick(amount: $0, label: "\(Int($0)) g")
    }

    static let drinkPicks: [QuickPick] = [
        QuickPick(amount: 250, label: LocalizedStringResource("Glass", comment: "Drink quick pick, 25 cl")),
        QuickPick(amount: 330, label: LocalizedStringResource("Can 33 cl", comment: "Drink quick pick")),
        QuickPick(amount: 500, label: LocalizedStringResource("Bottle 50 cl", comment: "Drink quick pick")),
        QuickPick(amount: 1000, label: LocalizedStringResource("1 l", comment: "Drink quick pick, one litre")),
    ]

    private var isDrink: Bool { product.isDrink == true }
    private var unit: LocalizedStringKey { isDrink ? "ml" : "g" }

    private enum Mode: Hashable {
        case serving, wholePack, grams
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if modes.count > 1 {
                GlassSegmentedControl(options: modes, selected: modeBinding, label: label)
            }
            detail
        }
    }

    private var modes: [Mode] {
        var modes: [Mode] = []
        if product.servingGrams != nil { modes.append(.serving) }
        if product.packageGrams != nil { modes.append(.wholePack) }
        modes.append(.grams)
        return modes
    }

    private var modeBinding: Binding<Mode> {
        Binding(
            get: {
                switch portion {
                case .servings: .serving
                case .wholePackage: .wholePack
                case .grams: .grams
                }
            },
            set: { mode in
                switch mode {
                case .serving: portion = .servings(1)
                case .wholePack: portion = .wholePackage
                case .grams: portion = .grams(currentGrams)
                }
            }
        )
    }

    /// Switching to grams keeps the amount already chosen, not 100 g.
    private var currentGrams: Double {
        guard let grams = product.grams(for: portion), grams.isFinite else { return 100 }
        let range = FoodPortionInput.gramsRange
        return min(range.upperBound, max(range.lowerBound, grams.rounded()))
    }

    private func label(_ mode: Mode) -> LocalizedStringKey {
        switch mode {
        case .serving: "Serving"
        case .wholePack: "Package"
        case .grams: isDrink ? "ml" : "Grams"
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch portion {
        case .servings(let count):
            servingsStepper(count)
        case .wholePackage:
            wholePackage
        case .grams(let grams):
            gramsSlider(grams)
        }
    }

    private func servingsStepper(_ count: Double) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Stepper(
                value: Binding(
                    get: { count },
                    set: { value in AppAnimation.with(AppAnimation.quick) { portion = .servings(value) } }
                ),
                in: 0.5...10,
                step: 0.5
            ) {
                HStack(spacing: Spacing.xs) {
                    Text(count.formatted(.number.precision(.fractionLength(0...1))))
                        .font(AppFont.title2)
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize()
                        .contentTransition(.numericText(value: count))
                    Text(count == 1 ? "serving" : "servings")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .tint(AppColor.accentPrimary)
            if let label = product.servingSizeText {
                Text("1 serving = \(label)")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    private var wholePackage: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text("1")
                    .font(AppFont.title2)
                    .monospacedDigit()
                    .foregroundStyle(AppColor.textPrimary)
                Text("whole package")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
            }
            .frame(minHeight: Spacing.minimumHitTarget)
            if let grams = product.packageGrams {
                Text(isDrink ? "1 package = \(Int(grams.rounded())) ml" : "1 package = \(Int(grams.rounded())) g")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
            }
        }
    }

    private func gramsSlider(_ grams: Double) -> some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Text("\(Int(grams.rounded()))")
                    .font(AppFont.title2)
                    .monospacedDigit()
                    .foregroundStyle(AppColor.textPrimary)
                    .contentTransition(.numericText(value: grams))
                Text(unit)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
            }
            Slider(
                value: Binding(get: { grams }, set: { portion = .grams($0) }),
                in: FoodPortionInput.gramsRange,
                step: Self.gramsStep
            )
            .tint(AppColor.accentPrimary)
            .accessibilityLabel(isDrink ? "Millilitres" : "Grams")
            // A tick every 25 g so dragging has a feel without buzzing
            // on each 5 g step.
            .appSensoryFeedback(.selection, trigger: Int(grams / 25))
            HStack(spacing: Spacing.xs) {
                ForEach(isDrink ? Self.drinkPicks : Self.foodPicks, id: \.amount) { quick in
                    quickPick(quick, isActive: grams == quick.amount)
                }
            }
        }
    }

    private func quickPick(_ pick: QuickPick, isActive: Bool) -> some View {
        Button {
            AppAnimation.with(AppAnimation.quick) { portion = .grams(pick.amount) }
        } label: {
            Text(pick.label)
                .font(AppFont.caption2)
                .fontWeight(isActive ? .semibold : .regular)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isActive ? AppColor.textPrimary : AppColor.textSecondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background {
                    Capsule().fill(AppColor.accentPrimary.opacity(isActive ? 0.30 : 0.15))
                }
                .minimumHitArea()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}
