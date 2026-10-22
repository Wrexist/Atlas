import SwiftUI

/// "Height & weight" onboarding step. Collects weight, height, age, and
/// sex via scroll-wheel pickers and pills. The numbers feed the daily
/// calorie / macro estimate (Mifflin-St Jeor) shown on the Projection
/// step and persisted as the Meals tab's targets.
///
/// Inputs are stored canonically in metric (`weightKg`, `heightCm`). The
/// metric/imperial toggle controls only the picker presentation — flipping
/// it never loses the underlying value because the wheels rebind to the
/// converted value on each render.
///
/// IMPORTANT: The numbers here power a *reference-only* calorie/macro
/// estimate, not a dose calculator. The medical disclaimer step makes
/// the reference-only nature explicit.
struct BodyMetricsPage: View {
    @Binding var metrics: BodyMetrics

    var body: some View {
        VStack(spacing: Spacing.lg) {
            OnboardingHeader(
                title: "Height & weight",
                subtitle: "Used to set your calorie and protein targets."
            )

            unitToggle

            VStack(spacing: Spacing.md) {
                heightPicker
                weightPicker
                agePicker
            }

            genderPills
        }
    }

    // MARK: - Unit toggle

    private var unitToggle: some View {
        HStack(spacing: Spacing.xs) {
            unitChip(label: "Metric", unit: .metric)
            unitChip(label: "Imperial", unit: .imperial)
        }
        .padding(Spacing.xs)
        .glassControl(.capsule)
    }

    private func unitChip(label: LocalizedStringKey, unit: MeasurementUnit) -> some View {
        let isSelected = metrics.unit == unit
        return Button {
            AppAnimation.with(AppAnimation.springSnappy) { metrics.unit = unit }
            Haptics.selection()
        } label: {
            Text(label)
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? AppColor.accentLight : AppColor.textSecondary)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.xs)
                .frame(minHeight: Spacing.minimumHitTarget)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(AppColor.accentPrimary.opacity(0.18))
                            .overlay {
                                Capsule().strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                            }
                    }
                }
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Pickers

    private var heightPicker: some View {
        WheelPickerRow(icon: "ruler.fill", title: "Height") {
            if metrics.unit == .metric {
                Picker("Centimeters", selection: heightCmBinding) {
                    ForEach(BodyMetricsRanges.heightCm, id: \.self) { cm in
                        Text("\(cm) cm").tag(cm)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 0) {
                    Picker("Feet", selection: heightFeetBinding) {
                        ForEach(BodyMetricsRanges.heightFeet, id: \.self) { ft in
                            Text("\(ft) ft").tag(ft)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Picker("Inches", selection: heightInchesBinding) {
                        ForEach(BodyMetricsRanges.heightInches, id: \.self) { inches in
                            Text("\(inches) in").tag(inches)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var weightPicker: some View {
        WheelPickerRow(icon: "scalemass.fill", title: "Weight") {
            if metrics.unit == .metric {
                Picker("Kilograms", selection: weightKgBinding) {
                    ForEach(BodyMetricsRanges.weightKg, id: \.self) { kg in
                        Text("\(kg) kg").tag(kg)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            } else {
                Picker("Pounds", selection: weightLbBinding) {
                    ForEach(BodyMetricsRanges.weightLb, id: \.self) { lb in
                        Text("\(lb) lb").tag(lb)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var agePicker: some View {
        WheelPickerRow(icon: "calendar", title: "Age") {
            Picker("Age", selection: ageBinding) {
                ForEach(BodyMetricsRanges.age, id: \.self) { age in
                    Text("\(age)").tag(age)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Gender pills

    private var genderPills: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label("Sex (for calorie estimate)", systemImage: "person.crop.circle")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)

            HStack(spacing: Spacing.xs) {
                ForEach(BiologicalSex.onboardingChoices) { option in
                    genderPill(option)
                }
            }
        }
    }

    private func genderPill(_ option: BiologicalSex) -> some View {
        let isSelected = metrics.sex == option
        return Button {
            AppAnimation.with(AppAnimation.springSnappy) { metrics.sex = option }
            Haptics.selection()
        } label: {
            Text(option.localizedShortLabel)
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? AppColor.textPrimary : AppColor.textSecondary)
                .frame(maxWidth: .infinity, minHeight: Spacing.minimumHitTarget)
                .glassControl(
                    .capsule,
                    tint: isSelected ? AppColor.accentPrimary.opacity(0.18) : nil,
                    border: isSelected ? AppColor.accentPrimary.opacity(0.45) : AppColor.glassBorder,
                    interactive: false
                )
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel(option.localizedDisplay)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Bindings (model storage is canonical metric)

    private var heightCmBinding: Binding<Int> {
        Binding(
            get: {
                let stored = Int((metrics.heightCm ?? Double(BodyMetricsRanges.defaultHeightCm)).rounded())
                return BodyMetricsRanges.clampHeightCm(stored)
            },
            set: { metrics.heightCm = Double($0) }
        )
    }

    private var heightFeetBinding: Binding<Int> {
        Binding(
            get: {
                let inchesTotal = (metrics.heightCm ?? Double(BodyMetricsRanges.defaultHeightCm)) / 2.54
                return BodyMetricsRanges.clampHeightFeet(Int(inchesTotal) / 12)
            },
            set: { newFeet in
                let inches = currentInches
                let totalInches = newFeet * 12 + inches
                metrics.heightCm = Double(totalInches) * 2.54
            }
        )
    }

    private var heightInchesBinding: Binding<Int> {
        Binding(
            get: {
                let inchesTotal = (metrics.heightCm ?? Double(BodyMetricsRanges.defaultHeightCm)) / 2.54
                return Int(inchesTotal) % 12
            },
            set: { newInches in
                let feet = currentFeet
                let totalInches = feet * 12 + newInches
                metrics.heightCm = Double(totalInches) * 2.54
            }
        )
    }

    private var currentFeet: Int {
        let inchesTotal = (metrics.heightCm ?? Double(BodyMetricsRanges.defaultHeightCm)) / 2.54
        return BodyMetricsRanges.clampHeightFeet(Int(inchesTotal) / 12)
    }

    private var currentInches: Int {
        let inchesTotal = (metrics.heightCm ?? Double(BodyMetricsRanges.defaultHeightCm)) / 2.54
        return Int(inchesTotal) % 12
    }

    private var weightKgBinding: Binding<Int> {
        Binding(
            get: {
                let stored = Int((metrics.weightKg ?? Double(BodyMetricsRanges.defaultWeightKg)).rounded())
                return BodyMetricsRanges.clampWeightKg(stored)
            },
            set: { metrics.weightKg = Double($0) }
        )
    }

    private var weightLbBinding: Binding<Int> {
        Binding(
            get: {
                let lb = MeasurementUnit.imperial.weightForDisplay(
                    metrics.weightKg ?? Double(BodyMetricsRanges.defaultWeightKg))
                return BodyMetricsRanges.clampWeightLb(Int(lb.rounded()))
            },
            set: { metrics.weightKg = MeasurementUnit.imperial.kilograms(fromDisplayed: Double($0)) }
        )
    }

    private var ageBinding: Binding<Int> {
        Binding(
            get: { BodyMetricsRanges.clampAge(metrics.age ?? BodyMetricsRanges.defaultAge) },
            set: { metrics.age = $0 }
        )
    }
}

private struct WheelPickerRow<Picker: View>: View {
    let icon: String
    let title: LocalizedStringKey
    @ViewBuilder var picker: () -> Picker

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label(title, systemImage: icon)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)

            picker()
                .frame(height: 110)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .fill(AppColor.surfaceSecondary.opacity(0.6))
                        .overlay {
                            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous))
        }
    }
}

/// Wheel-picker bounds and defaults. Centralised so the clamping in the
/// bindings always matches what the wheels actually offer.
enum BodyMetricsRanges {
    static let heightCm: ClosedRange<Int> = 100...230
    static let heightFeet: ClosedRange<Int> = 3...7
    static let heightInches: ClosedRange<Int> = 0...11
    static let weightKg: ClosedRange<Int> = 30...200
    static let weightLb: ClosedRange<Int> = 60...440
    static let age: ClosedRange<Int> = 13...100

    static let defaultHeightCm: Int = 175
    static let defaultWeightKg: Int = 75
    static let defaultAge: Int = 30

    static func clampHeightCm(_ v: Int) -> Int { v.clamped(to: heightCm) }
    static func clampHeightFeet(_ v: Int) -> Int { v.clamped(to: heightFeet) }
    static func clampWeightKg(_ v: Int) -> Int { v.clamped(to: weightKg) }
    static func clampWeightLb(_ v: Int) -> Int { v.clamped(to: weightLb) }
    static func clampAge(_ v: Int) -> Int { v.clamped(to: age) }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
