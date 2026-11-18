import SwiftUI

/// Compact summary of the user's optional body metrics on the Profile
/// screen, with a sheet for editing. They feed the calorie and macro
/// targets on Meals and the Biological Age estimate on Biology.
struct BodyMetricsCard: View {
    let metrics: BodyMetrics
    let onUpdate: (BodyMetrics) -> Void

    @State private var isEditing = false
    @State private var draft: BodyMetrics = .unspecified

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Label("Body metrics", systemImage: "figure.arms.open")
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
                    .minimumHitArea()
                    .accessibilityLabel(metrics.isComplete ? "Edit body metrics" : "Add body metrics")
                }

                if metrics.hasWeight || metrics.hasHeight || (metrics.age ?? 0) > 0 {
                    HStack(spacing: Spacing.md) {
                        metricStat(label: "Weight", value: weightText)
                        metricStat(label: "Height", value: heightText)
                        metricStat(label: "Age", value: ageText)
                    }
                    .appAnimation(AppAnimation.springSnappy, value: metrics)

                    if metrics.sex != .unspecified {
                        infoChip(metrics.sex.localizedDisplay)
                    }
                } else {
                    Text("Optional. Add your weight, height, and age so Atlas can calculate your calorie and macro targets and your Biological Age.")
                        .font(AppFont.caption2)
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
        metrics.weightLabel ?? "—"
    }

    private var heightText: String {
        metrics.heightLabel ?? "—"
    }

    private var ageText: String {
        guard let age = metrics.age, age > 0 else { return "—" }
        return "\(age)"
    }

    private func metricStat(label: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(AppFont.title3)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func infoChip(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(AppFont.caption2)
            .foregroundStyle(AppColor.textSecondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
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
            .navigationTitle("Body metrics")
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
