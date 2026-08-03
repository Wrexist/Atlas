import SwiftUI

struct HealthSummaryCard: View {
    @State private var restingHR: Double?
    @State private var hrv: Double?
    @State private var sleepHours: Double?
    @State private var steps: Double?
    @State private var isLoading = true
    @State private var isAvailable = true
    @State private var hasAnyData = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Label("Health Metrics", systemImage: "heart.fill")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text("7-day avg")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }

                if isLoading {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                            .tint(AppColor.accentPrimary)
                        Text("Loading your health metrics…")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, Spacing.md)
                    .accessibilityElement(children: .combine)
                } else if !isAvailable {
                    unavailableState
                } else if !hasAnyData {
                    noDataState
                } else {
                    HStack(spacing: Spacing.md) {
                        metricView(icon: "heart.fill", value: restingHR.map { "\(Int($0))" } ?? "--", unit: "bpm", label: "Resting HR")
                        metricView(icon: "waveform.path.ecg", value: hrv.map { "\(Int($0))" } ?? "--", unit: "ms", label: "HRV")
                        metricView(icon: "moon.fill", value: sleepHours.map { String(format: "%.1f", $0) } ?? "--", unit: "hrs", label: "Sleep")
                        metricView(icon: "figure.walk", value: steps.map { "\(Int($0 / 1000))k" } ?? "--", unit: "", label: "Steps")
                    }
                }
            }
        }
        .task { await loadHealthData() }
    }

    private var unavailableState: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: "heart.slash")
                .font(AppFont.scaled(20))
                .foregroundStyle(AppColor.textTertiary)
            Text("Apple Health isn't available on this device")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
    }

    private var noDataState: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppFont.scaled(16))
                .foregroundStyle(AppColor.accentPrimary.opacity(0.7))
            Text("No recent Health data")
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
            Text("Make sure Atlas has access in Settings → Health → Data Access.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
    }

    private func metricView(icon: String, value: String, unit: String, label: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(AppFont.scaled(13))
                .foregroundStyle(AppColor.accentPrimary)
                .accessibilityHidden(true)              // label below conveys the metric name
            Text(value + (unit.isEmpty ? "" : " ") + unit)
                .font(AppFont.caption)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(AppFont.scaled(8))
                .foregroundStyle(AppColor.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) \(unit)")
    }

    private func loadHealthData() async {
        let service = HealthKitService.shared
        guard service.isAvailable else {
            isAvailable = false
            isLoading = false
            return
        }
        async let hr = service.averageRestingHeartRate(days: 7)
        async let h = service.averageHRV(days: 7)
        async let s = service.averageSleepHours(days: 7)
        async let st = service.averageSteps(days: 7)
        restingHR = await hr
        hrv = await h
        sleepHours = await s
        steps = await st
        hasAnyData = restingHR != nil || hrv != nil || sleepHours != nil || steps != nil
        isLoading = false
    }
}
