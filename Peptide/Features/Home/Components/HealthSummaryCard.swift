import SwiftUI

struct HealthSummaryCard: View {
    @State private var restingHR: Double?
    @State private var hrv: Double?
    @State private var sleepHours: Double?
    @State private var steps: Double?
    @State private var isLoading = true

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
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(AppColor.accentPrimary)
                        Spacer()
                    }
                    .padding(.vertical, Spacing.md)
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

    private func metricView(icon: String, value: String, unit: String, label: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(AppColor.accentPrimary)
            Text(value + (unit.isEmpty ? "" : " ") + unit)
                .font(AppFont.caption)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(AppColor.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func loadHealthData() async {
        let service = HealthKitService.shared
        guard service.isAvailable else {
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
        isLoading = false
    }
}
