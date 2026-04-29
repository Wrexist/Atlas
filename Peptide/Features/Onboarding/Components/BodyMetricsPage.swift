import SwiftUI

/// Onboarding page that captures the body metrics needed to personalize
/// dose recommendations. All inputs are optional — users can skip the
/// page and the engine will fall back to published dosage ranges.
struct BodyMetricsPage: View {
    @Binding var metrics: BodyMetrics

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
    }

    // MARK: - Fields

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
    }

    private var weightField: some View {
        MetricNumericField(
            icon: "scalemass.fill",
            title: "Weight",
            placeholder: metrics.unit == .metric ? "75" : "165",
            unit: metrics.unit == .metric ? "kg" : "lb",
            value: Binding(
                get: { displayWeight },
                set: { setWeight(from: $0) }
            )
        )
    }

    private var heightField: some View {
        MetricNumericField(
            icon: "ruler.fill",
            title: "Height",
            placeholder: metrics.unit == .metric ? "180" : "70",
            unit: metrics.unit == .metric ? "cm" : "in",
            value: Binding(
                get: { displayHeight },
                set: { setHeight(from: $0) }
            )
        )
    }

    private var ageField: some View {
        MetricNumericField(
            icon: "calendar",
            title: "Age",
            placeholder: "30",
            unit: "years",
            value: Binding(
                get: { metrics.age.map(String.init) ?? "" },
                set: { metrics.age = Int($0.filter(\.isNumber)) }
            )
        )
    }

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
            Text(option.displayName)
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
    }

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
    }

    // MARK: - Conversions

    private var displayWeight: String {
        guard let kg = metrics.weightKg else { return "" }
        if metrics.unit == .metric { return formatNumber(kg) }
        return formatNumber(kg * 2.20462)
    }

    private var displayHeight: String {
        guard let cm = metrics.heightCm else { return "" }
        if metrics.unit == .metric { return formatNumber(cm) }
        return formatNumber(cm / 2.54)
    }

    private func setWeight(from text: String) {
        let parsed = parseDouble(text)
        guard let value = parsed else {
            metrics.weightKg = nil
            return
        }
        metrics.weightKg = metrics.unit == .metric ? value : value / 2.20462
    }

    private func setHeight(from text: String) {
        let parsed = parseDouble(text)
        guard let value = parsed else {
            metrics.heightCm = nil
            return
        }
        metrics.heightCm = metrics.unit == .metric ? value : value * 2.54
    }

    private func parseDouble(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        return Double(cleaned)
    }

    private func formatNumber(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value.rounded())) }
        return String(format: "%.1f", value)
    }
}

private struct MetricNumericField: View {
    let icon: String
    let title: String
    let placeholder: String
    let unit: String
    @Binding var value: String

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
                    .keyboardType(.decimalPad)
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
