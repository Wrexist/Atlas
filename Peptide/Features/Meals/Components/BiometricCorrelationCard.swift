import SwiftUI

/// Surfaces the headline biometric correlation between dose-day
/// flags and HealthKit metrics (HRV, RHR, sleep). Sibling to
/// `OutcomeCorrelationCard` — same shape, different signal source.
/// The two are intentionally separate cards so a user can read
/// "outcome scores trended up" and "HRV trended up" as independent
/// confirmations.
///
/// Async-loads the biometric series via `HealthKitService` on
/// appear and re-evaluates when the dose-entry list changes
/// (logging a new dose can flip a borderline correlation).
/// Renders nothing while loading or when no qualifying finding
/// exists — the empty state is "the engine has no opinion yet",
/// which is the honest answer for a 5-day-old install.
struct BiometricCorrelationCard: View {
    let entries: [ProtocolEntry]
    let healthConnected: Bool
    /// Window for the biometric pull, in days. 30 days balances
    /// "long enough to have signal" against "short enough that
    /// the user's protocol changes don't muddle the bucket
    /// averages". Tunable from the call site if a future
    /// "30/60/90" toggle ever lands.
    var windowDays: Int = 30

    @State private var headline: BiometricCorrelationEngine.Finding?
    @State private var didLoad: Bool = false

    var body: some View {
        if !healthConnected {
            EmptyView()
        } else if let headline {
            content(finding: headline)
                .task(id: triggerHash) { await reload() }
        } else {
            // Hidden when nothing meaningful surfaced — see the
            // engine's noise-floor + sample-size guards.
            Color.clear
                .frame(height: 0)
                .task(id: triggerHash) { await reload() }
        }
    }

    /// Re-fire on any change to the entry list so logging a new
    /// dose can flip a borderline correlation. Hashing once
    /// avoids triggering on incidental observation cycles
    /// (e.g. the user editing an unrelated profile field).
    private var triggerHash: Int {
        var hasher = Hasher()
        hasher.combine(entries.count)
        hasher.combine(entries.last?.date)
        hasher.combine(windowDays)
        return hasher.finalize()
    }

    @MainActor
    private func reload() async {
        didLoad = true
        let service = HealthKitService.shared
        async let hrv = service.dailyHRV(days: windowDays)
        async let rhr = service.dailyRestingHeartRate(days: windowDays)
        async let sleep = service.dailySleepHours(days: windowDays)
        let (hrvSeries, rhrSeries, sleepSeries) = await (hrv, rhr, sleep)
        let findings = BiometricCorrelationEngine.correlations(
            seriesByMetric: [
                .hrv: hrvSeries,
                .restingHeartRate: rhrSeries,
                .sleep: sleepSeries,
            ],
            entries: entries
        )
        headline = BiometricCorrelationEngine.headline(from: findings)
    }

    // MARK: - Content

    private func content(finding: BiometricCorrelationEngine.Finding) -> some View {
        GlassCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                headerRow(finding: finding)
                comparisonChart(finding: finding)
                footnote(finding: finding)
            }
        }
    }

    private func headerRow(finding: BiometricCorrelationEngine.Finding) -> some View {
        let tint: Color = finding.isFavourable
            ? AppColor.positive
            : AppColor.negative
        return HStack(alignment: .top, spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: icon(for: finding.metric))
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Biometric pattern")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(tint.opacity(0.85))
                Text(headlineCopy(finding: finding))
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(deltaPhrase(finding: finding))
                .font(AppFont.scaled(20, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }

    private func icon(for metric: BiometricCorrelationEngine.Metric) -> String {
        switch metric {
        case .hrv:               "waveform.path.ecg"
        case .restingHeartRate:  "heart.fill"
        case .sleep:             "moon.zzz.fill"
        }
    }

    private func headlineCopy(finding: BiometricCorrelationEngine.Finding) -> LocalizedStringResource {
        let dir: String = finding.isFavourable
            ? (finding.metric.higherIsBetter
                ? String(localized: "higher")
                : String(localized: "lower"))
            : (finding.metric.higherIsBetter
                ? String(localized: "lower")
                : String(localized: "higher"))
        return LocalizedStringResource(
            "Your \(finding.metric.displayName.lowercased()) trends \(dir) on dosing days.",
            comment: "Biometric correlation headline. Direction word ('higher' / 'lower') is composed in code based on the metric's direction-of-good."
        )
    }

    private func deltaPhrase(finding: BiometricCorrelationEngine.Finding) -> String {
        let signed = finding.delta
        let prefix = signed >= 0 ? "+" : "−"
        let value = abs(signed)
        let formatted = value < 10
            ? String(format: "%.1f", value)
            : String(format: "%.0f", value)
        return "\(prefix)\(formatted)"
    }

    private func comparisonChart(finding: BiometricCorrelationEngine.Finding) -> some View {
        let scaleRef = max(finding.onDoseDays, finding.offDoseDays, 1)
        return VStack(spacing: Spacing.xs) {
            bar(
                label: String(localized: "Dosing days"),
                value: finding.onDoseDays,
                fraction: finding.onDoseDays / scaleRef,
                count: finding.doseDayCount,
                tint: finding.isFavourable
                    ? AppColor.positive
                    : AppColor.negative
            )
            bar(
                label: String(localized: "Off days"),
                value: finding.offDoseDays,
                fraction: finding.offDoseDays / scaleRef,
                count: finding.offDayCount,
                tint: AppColor.textSecondary
            )
        }
    }

    private func bar(label: String, value: Double, fraction: Double, count: Int, tint: Color) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(label)
                .font(AppFont.scaled(11, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 84, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(AppColor.surfaceSecondary.opacity(0.55))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tint.opacity(0.75))
                        .frame(width: max(6, proxy.size.width * fraction))
                }
            }
            .frame(height: 10)
            Text(formatValue(value))
                .font(AppFont.scaled(12, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppColor.textPrimary)
                .frame(width: 38, alignment: .trailing)
            Text("\(count)d")
                .font(AppFont.scaled(10))
                .monospacedDigit()
                .foregroundStyle(AppColor.textTertiary)
                .frame(width: 28, alignment: .trailing)
        }
    }

    private func footnote(finding: BiometricCorrelationEngine.Finding) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle")
                .font(AppFont.scaled(10))
            Text("Pulled from Apple Health over \(windowDays) days. Correlation, not causation.")
                .font(AppFont.scaled(11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(AppColor.textSecondary)
    }

    private func formatValue(_ value: Double) -> String {
        if value < 10 { return String(format: "%.1f", value) }
        return String(format: "%.0f", value)
    }
}
