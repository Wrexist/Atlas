import SwiftUI

/// Concentration / unit-conversion reference for reconstituted
/// powder. Powder comes in a vial (mg), is reconstituted with
/// bacteriostatic water (mL); the tool converts a target amount into
/// the equivalent volume on a U-100 syringe (units, where 100 units =
/// 1 mL) and surfaces the resulting concentration (mg/mL).
///
/// The math is trivial: `units = (target / (vialMg / waterMl)) × 100`.
/// The value is getting the units straight — units vs. mL vs. mcg vs.
/// mg — which is a pure arithmetic conversion of the user's own
/// inputs.
///
/// This is a converter, not a recommendation engine and not an
/// administration instruction: inputs are user-supplied, the output
/// is stated as an equivalence ("that amount equals N units"), never
/// as a directive to inject, and the disclaimer is explicit. The view
/// stays agnostic about whether the user should take anything.
struct ReconstitutionCalculator: View {
    @State private var vialMilligrams: Double = 5
    @State private var bacWaterMilliliters: Double = 2
    @State private var targetDoseMicrograms: Double = 250

    /// Resulting concentration in mg/mL — the intermediate the
    /// math depends on. Surfaced as a callout so users learn the
    /// pattern, not just the answer.
    private var concentrationMgPerMl: Double {
        guard bacWaterMilliliters > 0 else { return 0 }
        return vialMilligrams / bacWaterMilliliters
    }

    /// Units on a U-100 syringe (100 units = 1 mL).
    /// `units = doseMl × 100`, and `doseMl = doseMg / concentrationMgPerMl`.
    /// Combined and rearranged for clarity. Returns 0 when inputs
    /// can't produce a meaningful answer (zero water → division by
    /// zero) so the UI never displays NaN.
    private var unitsOnSyringe: Double {
        guard concentrationMgPerMl > 0 else { return 0 }
        let doseMg = targetDoseMicrograms / 1000.0
        let doseMl = doseMg / concentrationMgPerMl
        return doseMl * 100
    }

    private var unitsRounded: Int { Int(unitsOnSyringe.rounded()) }

    /// `unitsOnSyringe` is the precise math result; users dial in
    /// integer units on the syringe. Display rounding, but keep the
    /// math precise underneath so a 12.6 result reads honestly as
    /// "≈ 13" rather than silently rounding to 12.
    private var hasFractionalUnits: Bool {
        abs(unitsOnSyringe - Double(unitsRounded)) > 0.05
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            inputCard
            resultCard
            disclaimer
        }
    }

    // MARK: - Input

    private var inputCard: some View {
        GlassCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                inputRow(
                    label: "Vial size",
                    value: vialMilligrams,
                    unit: "mg",
                    range: 0.5...50,
                    step: 0.5,
                    quickPicks: [2, 5, 10, 15],
                    bind: $vialMilligrams
                )
                inputRow(
                    label: "Bac water",
                    value: bacWaterMilliliters,
                    unit: "mL",
                    range: 0.5...10,
                    step: 0.5,
                    quickPicks: [1, 2, 3, 5],
                    bind: $bacWaterMilliliters
                )
                inputRow(
                    label: "Target dose",
                    value: targetDoseMicrograms,
                    unit: "mcg",
                    range: 50...10_000,
                    step: 25,
                    quickPicks: [250, 500, 1000, 2000],
                    bind: $targetDoseMicrograms
                )
            }
        }
    }

    private func inputRow(
        label: LocalizedStringKey,
        value: Double,
        unit: String,
        range: ClosedRange<Double>,
        step: Double,
        quickPicks: [Double],
        bind: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(AppFont.scaled(12, weight: .semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                Text("\(formatted(value)) \(unit)")
                    .font(AppFont.scaled(20, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.textPrimary)
                    .contentTransition(.numericText())
            }
            Slider(value: bind, in: range, step: step)
                .tint(AppColor.accentPrimary)
            HStack(spacing: Spacing.xs) {
                ForEach(quickPicks, id: \.self) { pick in
                    Button("\(formatted(pick))") {
                        Haptics.impact(.light)
                        bind.wrappedValue = pick
                    }
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 4)
                    .background {
                        Capsule().fill(AppColor.accentPrimary.opacity(0.15))
                    }
                }
            }
        }
    }

    // MARK: - Result

    private var resultCard: some View {
        GlassCard(tinted: true, padding: Spacing.md) {
            VStack(spacing: Spacing.md) {
                resultHeadline
                SyringeDiagram(unitsToFill: unitsOnSyringe)
                    .frame(height: 80)
                    .padding(.horizontal, Spacing.sm)
                concentrationFootnote
            }
        }
    }

    private var resultHeadline: some View {
        VStack(spacing: 4) {
            // Declarative equivalence, not an imperative "draw to" —
            // the tool states what the user's inputs convert to, it
            // does not instruct administration.
            Text("Equivalent volume")
                .font(AppFont.scaled(12, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.accentLight.opacity(0.85))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if hasFractionalUnits {
                    Text("≈ \(unitsRounded)")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                        .contentTransition(.numericText())
                } else {
                    Text("\(unitsRounded)")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                        .contentTransition(.numericText())
                }
                Text("units")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
            Text("on a 100-unit (U-100) insulin syringe")
                .font(AppFont.scaled(11))
                .foregroundStyle(AppColor.textTertiary)
        }
    }

    private var concentrationFootnote: some View {
        HStack(spacing: Spacing.lg) {
            footnoteCell(
                label: String(localized: "Concentration"),
                value: String(format: "%.2f mg/mL", concentrationMgPerMl)
            )
            footnoteCell(
                label: String(localized: "Doses / vial"),
                value: dosesPerVialString
            )
        }
    }

    private func footnoteCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppFont.scaled(10, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.textSecondary)
            Text(value)
                .font(AppFont.scaled(13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(AppColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dosesPerVialString: String {
        let doseMg = targetDoseMicrograms / 1000.0
        guard doseMg > 0 else { return "—" }
        let count = Int((vialMilligrams / doseMg).rounded(.down))
        return "\(count)"
    }

    private var disclaimer: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "info.circle")
                .font(AppFont.scaled(12))
                .foregroundStyle(AppColor.textSecondary)
                .padding(.top, 1)
            Text("Calculator only. Doses and protocols vary widely — consult a qualified medical professional. Atlas doesn't recommend any specific compound or dose.")
                .font(AppFont.scaled(11))
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func formatted(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}

/// Visual U-100 syringe. The fill animates to the computed unit
/// mark, with the major unit ticks labelled (10, 20, 30, …, 100).
/// Lets users sanity-check the calculator answer against the
/// physical syringe they're holding. Doesn't try to be a
/// photorealistic syringe — a clean schematic reads faster than a
/// 3D render and accessibility tools handle it gracefully.
struct SyringeDiagram: View {
    let unitsToFill: Double

    private let maxUnits: Double = 100
    private let majorTickEvery: Int = 10

    private var fillFraction: Double {
        guard unitsToFill > 0 else { return 0 }
        return min(1.0, unitsToFill / maxUnits)
    }

    var body: some View {
        GeometryReader { proxy in
            let bodyWidth  = proxy.size.width * 0.78
            let needleWidth = proxy.size.width * 0.18
            let plungerHeight = proxy.size.height * 0.42
            let needleHeight  = proxy.size.height * 0.20
            let centerY = proxy.size.height / 2

            ZStack(alignment: .leading) {
                // Syringe body track (clear)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.65))
                    .frame(width: bodyWidth, height: plungerHeight)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
                    .position(x: bodyWidth / 2, y: centerY)

                // Liquid fill
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColor.accentPrimary.opacity(0.85),
                                AppColor.accentLight.opacity(0.85),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: bodyWidth * fillFraction, height: plungerHeight - 4)
                    .position(x: bodyWidth * fillFraction / 2, y: centerY)
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: fillFraction)

                // Tick marks (major)
                ForEach(0...10, id: \.self) { tick in
                    let x = bodyWidth * (Double(tick) / 10.0)
                    Rectangle()
                        .fill(AppColor.textTertiary.opacity(0.75))
                        .frame(width: 1, height: plungerHeight)
                        .position(x: x, y: centerY)

                    if tick > 0 && tick < 10 {
                        Text("\(tick * majorTickEvery)")
                            .font(AppFont.scaled(8, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(AppColor.textTertiary)
                            .position(x: x, y: centerY + plungerHeight / 2 + 8)
                    }
                }

                // Needle on the right side
                Rectangle()
                    .fill(AppColor.textTertiary.opacity(0.8))
                    .frame(width: needleWidth - 4, height: needleHeight / 4)
                    .position(x: bodyWidth + (needleWidth - 4) / 2, y: centerY)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let units = Int(unitsToFill.rounded())
        return String(
            localized: "Syringe diagram. Equivalent volume: \(units) units on a 100-unit syringe.",
            comment: "VoiceOver readout for the reconstitution calculator's syringe diagram."
        )
    }
}
