import SwiftUI

/// Bevel-style three-ring hero at the top of Today.
/// Adherence (taken doses) / Recovery (HRV + sleep + RHR composite)
/// / Sleep (last night's hours vs target). Each ring tells a
/// distinct part of "should I push or recover today?" so the user
/// gets the same one-glance answer Bevel / Whoop give for training,
/// in the peptide-protocol context.
///
/// The trio drives off `HeroMetricSnapshot` which is built once on
/// view appear and refreshed when scene phase returns to .active.
/// Async HealthKit reads happen inside the snapshot builder; the
/// view never blocks waiting for them — missing data renders as a
/// dimmed ring with an em-dash centre and (collectively) a single
/// "Connect Health for full picture" footer.
struct HeroMetricTrio: View {
    let snapshot: HeroMetricSnapshot
    var onTapRing: ((HeroMetricKind) -> Void)?

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                ringTile(.adherence, value: snapshot.adherence)
                ringTile(.recovery,  value: snapshot.recovery)
                ringTile(.sleep,     value: snapshot.sleep)
            }
            .frame(maxWidth: .infinity)

            if snapshot.needsHealthConnection {
                healthConnectionFooter
            }
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today's metrics")
    }

    // MARK: - Ring tile

    @ViewBuilder
    private func ringTile(_ kind: HeroMetricKind, value: HeroMetricValue) -> some View {
        Button {
            onTapRing?(kind)
        } label: {
            VStack(spacing: Spacing.xs) {
                MetricRing(
                    progress: value.progress,
                    diameter: 96,
                    strokeWidth: 10,
                    gradient: kind.gradient(active: value.isAvailable),
                    // Only Adherence celebrates at 100% — it's the
                    // ring the user actively drives by logging
                    // doses. Recovery + Sleep crossing 100 would be
                    // a false positive (great recovery is the
                    // ceiling, not a finished task).
                    celebrateAtCompletion: kind == .adherence
                ) {
                    ringCenter(kind: kind, value: value)
                }
                .onChange(of: value.progress) { oldValue, newValue in
                    // Pair the celebration scale-pulse with a
                    // success notification haptic the first time
                    // the adherence ring crosses 100% in a day.
                    // Suppressed for Recovery + Sleep — same
                    // reason as celebrateAtCompletion above.
                    guard kind == .adherence,
                          oldValue < 1.0, newValue >= 1.0 else { return }
                    Haptics.success()
                }

                Text(kind.label)
                    .font(AppFont.scaled(13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value.accessibilityLabel(for: kind))
    }

    @ViewBuilder
    private func ringCenter(kind: HeroMetricKind, value: HeroMetricValue) -> some View {
        if value.isAvailable {
            Text("\(value.displayPercent)%")
                .font(AppFont.scaled(20, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
        } else {
            Text("—")
                .font(AppFont.scaled(20, weight: .bold))
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    // MARK: - Footer

    private var healthConnectionFooter: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "heart.text.square.fill")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
            Text("Connect Apple Health for Recovery & Sleep scores")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.xs)
    }
}

// MARK: - Snapshot types

enum HeroMetricKind: Hashable, CaseIterable {
    case adherence, recovery, sleep

    var label: LocalizedStringKey {
        switch self {
        case .adherence: "Adherence"
        case .recovery:  "Recovery"
        case .sleep:     "Sleep"
        }
    }

    /// Gradient stops drawn into the ring's angular gradient. The
    /// dimmed variant kicks in when the metric has no data so the
    /// "—" centre reads as inactive without being invisible.
    func gradient(active: Bool) -> [Color] {
        guard active else {
            return [AppColor.textSecondary.opacity(0.45), AppColor.textSecondary.opacity(0.25)]
        }
        switch self {
        case .adherence:
            return [AppColor.accentLight, AppColor.accentPrimary]
        case .recovery:
            return [AppColor.ringRecoveryStart, AppColor.ringRecoveryEnd]
        case .sleep:
            return [AppColor.ringSleepStart, AppColor.ringSleepEnd]
        }
    }
}

/// Per-ring value carrier. `progress` (0…1) drives the arc;
/// `displayPercent` is the user-facing integer the centre shows;
/// `isAvailable` is false when the input data is missing so the
/// ring degrades cleanly instead of pegging at 0%.
struct HeroMetricValue: Equatable, Sendable {
    let progress: Double
    let displayPercent: Int
    let isAvailable: Bool

    static let unavailable = HeroMetricValue(progress: 0, displayPercent: 0, isAvailable: false)

    static func percent(_ raw: Double) -> HeroMetricValue {
        let clamped = max(0, min(1, raw))
        return HeroMetricValue(
            progress: clamped,
            displayPercent: Int((clamped * 100).rounded()),
            isAvailable: true
        )
    }

    func accessibilityLabel(for kind: HeroMetricKind) -> String {
        let name: String
        switch kind {
        case .adherence: name = "Adherence"
        case .recovery:  name = "Recovery"
        case .sleep:     name = "Sleep"
        }
        guard isAvailable else { return "\(name), no data" }
        return "\(name), \(displayPercent) percent"
    }
}

/// Build-once snapshot consumed by HeroMetricTrio. Constructed
/// async in HomeView so the view body stays synchronous.
struct HeroMetricSnapshot: Equatable, Sendable {
    let adherence: HeroMetricValue
    let recovery: HeroMetricValue
    let sleep: HeroMetricValue
    let healthConnected: Bool
    /// Recovery score breakdown captured at build time so the
    /// detail sheet can show "HRV vs baseline / Sleep vs target /
    /// RHR vs baseline" without re-running the HealthKit reads.
    /// Nil when HealthKit isn't connected or the score couldn't be
    /// computed.
    let recoveryComponents: RecoveryScoreEngine.Components?
    /// Last-night sleep duration in hours, captured for the same
    /// reason — the sleep detail sheet shows "Slept N h" without a
    /// second HealthKit hop.
    let lastSleepHours: Double?

    /// True when Recovery or Sleep are unavailable AND the user
    /// hasn't connected HealthKit. Drives the footer prompt. Once
    /// they connect, missing values come from "no recent samples"
    /// rather than "permissions denied" — different copy.
    var needsHealthConnection: Bool {
        !healthConnected && (!recovery.isAvailable || !sleep.isAvailable)
    }

    static let empty = HeroMetricSnapshot(
        adherence: .unavailable,
        recovery: .unavailable,
        sleep: .unavailable,
        healthConnected: false,
        recoveryComponents: nil,
        lastSleepHours: nil
    )

    /// Builds the snapshot. Adherence is synchronous (uses the
    /// caller's already-computed ratio); Recovery and Sleep pull
    /// from HealthKit via `RecoveryScoreEngine`. Safe to call from
    /// `.task` in HomeView — the call sites batch their work so a
    /// scene-phase change re-runs once, not three times.
    static func build(
        adherenceRatio: Double,
        healthConnected: Bool,
        sleepTargetHours: Double = 8.0
    ) async -> HeroMetricSnapshot {
        guard healthConnected else {
            return HeroMetricSnapshot(
                adherence: .percent(adherenceRatio),
                recovery: .unavailable,
                sleep: .unavailable,
                healthConnected: false,
                recoveryComponents: nil,
                lastSleepHours: nil
            )
        }

        let kit = await HealthKitService.shared
        async let recentHRV  = kit.averageHRV(days: 3)
        async let baseHRV    = kit.averageHRV(days: 30)
        async let recentRHR  = kit.averageRestingHeartRate(days: 3)
        async let baseRHR    = kit.averageRestingHeartRate(days: 30)
        async let sleepHours = kit.averageSleepHours(days: 1)

        let inputs = await RecoveryScoreEngine.Inputs(
            recentHRV: recentHRV,
            baselineHRV: baseHRV,
            recentRHR: recentRHR,
            baselineRHR: baseRHR,
            lastSleepHours: sleepHours,
            sleepTargetHours: sleepTargetHours
        )

        let recoveryScore = RecoveryScoreEngine.score(inputs: inputs)
        let recoveryValue: HeroMetricValue = {
            guard let s = recoveryScore else { return .unavailable }
            return .percent(Double(s.value) / 100)
        }()

        let sleepValue: HeroMetricValue = {
            guard let hours = inputs.lastSleepHours, hours > 0 else { return .unavailable }
            return .percent(hours / sleepTargetHours)
        }()

        return HeroMetricSnapshot(
            adherence: .percent(adherenceRatio),
            recovery: recoveryValue,
            sleep: sleepValue,
            healthConnected: true,
            recoveryComponents: recoveryScore?.components,
            lastSleepHours: inputs.lastSleepHours
        )
    }
}

#Preview("All present") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        HeroMetricTrio(
            snapshot: HeroMetricSnapshot(
                adherence: .percent(0.75),
                recovery: .percent(0.85),
                sleep: .percent(0.82),
                healthConnected: true,
                recoveryComponents: .init(hrv: 0.9, sleep: 0.85, rhr: 0.6),
                lastSleepHours: 7.5
            )
        )
        .padding(Spacing.lg)
    }
    .preferredColorScheme(.dark)
}

#Preview("No health connection") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        HeroMetricTrio(
            snapshot: HeroMetricSnapshot(
                adherence: .percent(0.50),
                recovery: .unavailable,
                sleep: .unavailable,
                healthConnected: false,
                recoveryComponents: nil,
                lastSleepHours: nil
            )
        )
        .padding(Spacing.lg)
    }
    .preferredColorScheme(.dark)
}
