import SwiftUI

/// The portion control shared by the barcode and food-library review
/// screens: a segmented switch between serving, package and grams,
/// over the matching detail — a servings stepper, the package weight, or
/// a gram slider with quick picks. One copy so the two flows can't drift.
struct PortionPicker: View {
    let product: ScannedProduct
    @Binding var portion: ScannedProduct.Portion

    static let gramsStep: Double = 5
    static let quickGrams: [Double] = [50, 100, 200, 500]

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
        case .grams: "Grams"
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
                Text("1 package = \(Int(grams.rounded())) g")
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
                Text("g")
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
            .accessibilityLabel("Grams")
            // A tick every 25 g so dragging has a feel without buzzing
            // on each 5 g step.
            .appSensoryFeedback(.selection, trigger: Int(grams / 25))
            HStack(spacing: Spacing.xs) {
                ForEach(Self.quickGrams, id: \.self) { quick in
                    quickPick(quick, isActive: grams == quick)
                }
            }
        }
    }

    private func quickPick(_ grams: Double, isActive: Bool) -> some View {
        Button {
            AppAnimation.with(AppAnimation.quick) { portion = .grams(grams) }
        } label: {
            Text("\(Int(grams)) g")
                .font(AppFont.caption2)
                .fontWeight(isActive ? .semibold : .regular)
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
