import SwiftUI

/// Onboarding page that captures the body metrics needed to personalize
/// dose recommendations. All inputs are optional — users can skip the
/// page and the engine will fall back to published dosage ranges.
///
/// Numeric fields are backed by raw `@State` strings so partial input
/// like "75." (decimal in progress) and locale-friendly commas survive
/// keystroke-by-keystroke. The model is updated only when the parsed
/// value is valid, and re-syncs when the unit toggle flips.
struct BodyMetricsPage: View {
    @Binding var metrics: BodyMetrics

    @State private var weightInput: String = ""
    @State private var heightInput: String = ""
    @State private var ageInput: String = ""

    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case weight, height, age }

    var body: some View {
        VStack(spacing: Spacing.md) {
            Text("Help us personalize your doses")
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)

            Text("Body weight, height, and age let us scale recommendations to you. Everything stays on your device.")
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)

            unitToggle
                .padding(.top, Spacing.sm)

            VStack(spacing: Spacing.md) {
                weightField
                heightField
                ageField
                sexPicker
                activityPicker
            }
            .padding(.top, Spacing.sm)
        }
        .onAppear(perform: hydrateInputs)
        .onChange(of: metrics.unit) { _, _ in hydrateInputs() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.accentPrimary)
            }
        }
    }

    // MARK: - Unit toggle

    private var unitToggle: some View {
        HStack(spacing: Spacing.xs) {
            unitChip(label: "Metric", unit: .metric)
            unitChip(label: "Imperial", unit: .imperial)
        }
        .padding(4)
        .background {
            Capsule()
                .fill(AppColor.surfaceElevated)
                .overlay {
                    Capsule().strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
    }

    private func unitChip(label: String, unit: MeasurementUnit) -> some View {
        let isSelected = metrics.unit == unit
        return Button {
            withAnimation(AppAnimation.springSnappy) { metrics.unit = unit }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            Text(label)
                .font(AppFont.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(isSelected ? AppColor.textPrimary : AppColor.textSecondary)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.xs)
                .background {
                    Capsule()
                        .fill(isSelected ? AppColor.glassTint : Color.clear)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Numeric fields

    private var weightField: some View {
        MetricNumericField(
            icon: "scalemass.fill",
            title: "Weight",
            placeholder: metrics.unit == .metric ? "75" : "165",
            unit: metrics.unit == .metric ? "kg" : "lb",
            value: $weightInput
        )
        .focused($focusedField, equals: .weight)
        .onChange(of: weightInput) { _, new in syncWeight(from: new) }
    }

    private var heightField: some View {
        MetricNumericField(
            icon: "ruler.fill",
            title: "Height",
            placeholder: metrics.unit == .metric ? "180" : "70",
            unit: metrics.unit == .metric ? "cm" : "in",
            value: $heightInput
        )
        .focused($focusedField, equals: .height)
        .onChange(of: heightInput) { _, new in syncHeight(from: new) }
    }

    private var ageField: some View {
        MetricNumericField(
            icon: "calendar",
            title: "Age",
            placeholder: "30",
            unit: "years",
            value: $ageInput,
            decimalAllowed: false
        )
        .focused($focusedField, equals: .age)
        .onChange(of: ageInput) { _, new in
            metrics.age = Int(new.filter(\.isNumber))
        }
    }

    // MARK: - Sex picker

    private var sexPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label("Biological sex", systemImage: "person.crop.circle")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)

            HStack(spacing: Spacing.xs) {
                ForEach(BiologicalSex.allCases) { option in
                    sexChip(option)
                }
            }
        }
    }

    private func sexChip(_ option: BiologicalSex) -> some View {
        let isSelected = metrics.sex == option
        return Button {
            withAnimation(AppAnimation.springSnappy) { metrics.sex = option }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            Text(option.shortLabel)
                .font(AppFont.caption)
                .fontWeight(.medium)
                .foregroundStyle(isSelected ? AppColor.textPrimary : AppColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .fill(isSelected ? AppColor.accentPrimary.opacity(0.15) : AppColor.surfaceSecondary.opacity(0.6))
                        .overlay {
                            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                                .strokeBorder(
                                    isSelected ? AppColor.accentPrimary.opacity(0.45) : AppColor.glassBorder,
                                    lineWidth: 0.5
                                )
                        }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Activity picker

    private var activityPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label("Activity level", systemImage: "figure.run")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(ActivityLevel.allCases) { option in
                        activityChip(option)
                    }
                }
            }
        }
    }

    private func activityChip(_ option: ActivityLevel) -> some View {
        let isSelected = metrics.activityLevel == option
        return Button {
            withAnimation(AppAnimation.springSnappy) { metrics.activityLevel = option }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            VStack(spacing: 2) {
                Text(option.displayName)
                    .font(AppFont.caption)
                    .fontWeight(.semibold)
                Text(option.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .foregroundStyle(isSelected ? AppColor.textPrimary : AppColor.textSecondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background {
                Capsule()
                    .fill(isSelected ? AppColor.accentPrimary.opacity(0.18) : AppColor.surfaceSecondary.opacity(0.6))
                    .overlay {
                        Capsule().strokeBorder(
                            isSelected ? AppColor.accentPrimary.opacity(0.45) : AppColor.glassBorder,
                            lineWidth: 0.5
                        )
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Hydration & parsing

    private func hydrateInputs() {
        weightInput = formattedDisplay(for: metrics.weightKg, kgToDisplay: kgToDisplayWeight)
        heightInput = formattedDisplay(for: metrics.heightCm, kgToDisplay: cmToDisplayHeight)
        ageInput = metrics.age.map(String.init) ?? ""
    }

    private func syncWeight(from text: String) {
        guard let value = parseDouble(text) else {
            metrics.weightKg = nil
            return
        }
        metrics.weightKg = metrics.unit == .metric ? value : value / 2.20462
    }

    private func syncHeight(from text: String) {
        guard let value = parseDouble(text) else {
            metrics.heightCm = nil
            return
        }
        metrics.heightCm = metrics.unit == .metric ? value : value * 2.54
    }

    private func parseDouble(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    private func formattedDisplay(for canonical: Double?, kgToDisplay: (Double) -> Double) -> String {
        guard let value = canonical, value > 0 else { return "" }
        let display = kgToDisplay(value)
        if display == display.rounded() { return String(Int(display.rounded())) }
        return String(format: "%.1f", display)
    }

    private func kgToDisplayWeight(_ kg: Double) -> Double {
        metrics.unit == .metric ? kg : kg * 2.20462
    }

    private func cmToDisplayHeight(_ cm: Double) -> Double {
        metrics.unit == .metric ? cm : cm / 2.54
    }
}

private struct MetricNumericField: View {
    let icon: String
    let title: String
    let placeholder: String
    let unit: String
    @Binding var value: String
    var decimalAllowed: Bool = true

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColor.accentLight)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                TextField(placeholder, text: $value)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textPrimary)
                    .keyboardType(decimalAllowed ? .decimalPad : .numberPad)
                    .tint(AppColor.accentPrimary)
            }

            Spacer()

            Text(unit)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
    }
}
