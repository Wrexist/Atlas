import SwiftUI

/// Compact summary of the user's optional body metrics on the Profile
/// screen, with a sheet for editing. The values are stored locally for the
/// user's own reference and HealthKit correlation; Atlas does not use
/// them to calculate or recommend any dose.
struct BodyMetricsCard: View {
    let metrics: BodyMetrics
    let onUpdate: (BodyMetrics) -> Void

    @State private var isEditing = false
    @State private var draft: BodyMetrics = .unspecified

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Label("Body Metrics", systemImage: "figure.arms.open")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Button {
                        draft = metrics
                        isEditing = true
                    } label: {
                        Text(metrics.isComplete ? "Edit" : "Add")
                            .font(AppFont.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.accentPrimary)
                    }
                }

                if metrics.hasWeight || metrics.hasHeight || (metrics.age ?? 0) > 0 {
                    HStack(spacing: Spacing.md) {
                        metricStat(label: "Weight", value: weightText)
                        metricStat(label: "Height", value: heightText)
                        metricStat(label: "Age", value: ageText)
                    }

                    HStack(spacing: Spacing.xs) {
                        infoChip(metrics.sex.localizedDisplay)
                    }
                } else {
                    Text("Optional. Add your weight, height, and age to display alongside your compliance trends. Atlas never calculates doses for you.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            BodyMetricsEditSheet(
                metrics: $draft,
                onSave: {
                    onUpdate(draft)
                    isEditing = false
                },
                onCancel: { isEditing = false }
            )
            .liquidGlassPresentation()
        }
    }

    private var weightText: String {
        guard let kg = metrics.weightKg else { return "—" }
        if metrics.unit == .metric {
            return "\(formatNumber(kg)) kg"
        }
        return "\(formatNumber(kg * 2.20462)) lb"
    }

    private var heightText: String {
        guard let cm = metrics.heightCm else { return "—" }
        if metrics.unit == .metric {
            return "\(formatNumber(cm)) cm"
        }
        // Imperial reads as feet + inches ("5'11\"") — decimal inches
        // ("71 in") is technically correct but nobody states height that
        // way. Round total inches first so we never render "5'12\"".
        let totalInches = Int((cm / 2.54).rounded())
        return "\(totalInches / 12)'\(totalInches % 12)\""
    }

    private var ageText: String {
        guard let age = metrics.age, age > 0 else { return "—" }
        return "\(age)"
    }

    private func formatNumber(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value.rounded())) }
        return String(format: "%.1f", value)
    }

    private func metricStat(label: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(AppFont.title3)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoChip(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textSecondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(AppColor.surfaceElevated)
                    .overlay {
                        Capsule().strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
            }
    }
}

private struct BodyMetricsEditSheet: View {
    @Binding var metrics: BodyMetrics
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                BodyMetricsPage(metrics: $metrics)
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.xxxxl)
            }
            .background(AppColor.background)
            .navigationTitle("Body Metrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(AppColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.accentPrimary)
                }
            }
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        BodyMetricsCard(
            metrics: BodyMetrics(
                weightKg: 80,
                heightCm: 180,
                age: 32,
                sex: .male,
                activityLevel: .active,
                unit: .metric
            ),
            onUpdate: { _ in }
        )
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
