import SwiftUI

/// Detail sheet presented when the user taps one of the Today
/// hero-trio rings. Same shell for all three metrics; the content
/// switches per `kind`. Renders a big focal number, an explainer
/// line, and either a component breakdown (Recovery) or a list of
/// contributing entries (Adherence).
///
/// Bevel attaches a similar drill-down to every Strain / Recovery /
/// Sleep ring — taps that don't lead anywhere break the "feels
/// premium" promise. This closes that loop.
struct HeroMetricDetailSheet: View {
    let kind: HeroMetricKind
    let snapshot: HeroMetricSnapshot
    /// Optional context the sheet uses to fill in per-metric detail
    /// (today's dose entries for Adherence, HealthKit baselines for
    /// Recovery / Sleep). All fields are optional so the sheet
    /// degrades gracefully when a metric has no data.
    let context: Context

    struct Context {
        let todayEntries: [ProtocolEntry]
        let recoveryComponents: RecoveryScoreEngine.Components?
        let lastSleepHours: Double?
        let sleepTargetHours: Double

        init(
            todayEntries: [ProtocolEntry] = [],
            recoveryComponents: RecoveryScoreEngine.Components? = nil,
            lastSleepHours: Double? = nil,
            sleepTargetHours: Double = 8.0
        ) {
            self.todayEntries = todayEntries
            self.recoveryComponents = recoveryComponents
            self.lastSleepHours = lastSleepHours
            self.sleepTargetHours = sleepTargetHours
        }
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    heroBlock
                    explainer
                    detailContent
                }
                .padding(Spacing.screenPadding)
            }
            .background(AppColor.background)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var heroBlock: some View {
        HStack(alignment: .center, spacing: Spacing.lg) {
            MetricRing(
                progress: valueForRing.progress,
                diameter: 110,
                strokeWidth: 12,
                gradient: kind.gradient(active: valueForRing.isAvailable),
                appearAnimated: true,
                glow: true
            ) {
                if valueForRing.isAvailable {
                    Text("\(valueForRing.displayPercent)%")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .monospacedDigit()
                } else {
                    Text("—")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppColor.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(kind.label)
                    .font(AppFont.title2)
                    .fontWeight(.heavy)
                    .foregroundStyle(AppColor.textPrimary)
                if let line = supportingLine {
                    Text(line)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var valueForRing: HeroMetricValue {
        switch kind {
        case .adherence: snapshot.adherence
        case .recovery:  snapshot.recovery
        case .sleep:     snapshot.sleep
        }
    }

    private var supportingLine: String? {
        switch kind {
        case .adherence:
            let completed = context.todayEntries.filter(\.completed).count
            let total = context.todayEntries.count
            guard total > 0 else { return String(localized: "No doses scheduled today.") }
            return String(format: String(localized: "%d of %d doses logged today"), completed, total)
        case .recovery:
            guard valueForRing.isAvailable else {
                return String(localized: "Connect Apple Health to unlock Recovery.")
            }
            return String(localized: "Composite of HRV, last night's sleep, and resting heart rate.")
        case .sleep:
            guard let hours = context.lastSleepHours, hours > 0 else {
                return String(localized: "No sleep data yet for last night.")
            }
            let display = String(format: "%.1f h", hours)
            let target = String(format: "%.0f h", context.sleepTargetHours)
            return String(format: String(localized: "%@ last night · target %@"), display, target)
        }
    }

    // MARK: - Explainer

    private var explainer: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("WHY IT MATTERS")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(AppColor.accentLight)
            Text(explainerBody)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var explainerBody: String {
        switch kind {
        case .adherence:
            return String(localized: "Your daily peptide protocol works when it's followed consistently — adherence captures how much of today's planned dosing you've actually logged.")
        case .recovery:
            return String(localized: "Recovery is a 0–100 read on whether your body is ready to push or rest. Higher HRV + adequate sleep + a steady resting heart rate all push the number up; a short night or a stress spike pull it down.")
        case .sleep:
            return String(localized: "Sleep is the single biggest lever for recovery, hormone regulation, and protocol response. The target defaults to 8 hours — open Profile to adjust if your baseline differs.")
        }
    }

    // MARK: - Per-kind detail

    @ViewBuilder
    private var detailContent: some View {
        switch kind {
        case .adherence: adherenceList
        case .recovery:  recoveryBreakdown
        case .sleep:     sleepDetail
        }
    }

    // MARK: - Adherence list

    private var adherenceList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("TODAY'S DOSES")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(AppColor.accentLight)

            if context.todayEntries.isEmpty {
                Text("No doses scheduled.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.vertical, Spacing.sm)
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(context.todayEntries) { entry in
                        doseRow(entry)
                    }
                }
            }
        }
    }

    private func doseRow(_ entry: ProtocolEntry) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: entry.completed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(entry.completed ? AppColor.success : AppColor.textTertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.peptide.name)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("\(entry.dose) · \(Self.timeFormatter.string(from: entry.date))")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
        }
        .padding(Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
    }

    // MARK: - Recovery breakdown

    private var recoveryBreakdown: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("WHAT'S DRIVING IT")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(AppColor.accentLight)

            if let components = context.recoveryComponents {
                componentRow(label: "HRV vs baseline",        value: components.hrv,   icon: "waveform.path.ecg")
                componentRow(label: "Sleep vs 8h target",     value: components.sleep, icon: "bed.double.fill")
                componentRow(label: "Resting HR vs baseline", value: components.rhr,   icon: "heart.fill")
            } else {
                Text("Connect Apple Health and wear your Apple Watch to start tracking these signals.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.vertical, Spacing.sm)
            }
        }
    }

    private func componentRow(label: String, value: Double?, icon: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .frame(width: 28, height: 28)
                .background { Circle().fill(AppColor.accentPrimary.opacity(0.15)) }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(value.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
            }
            Spacer()
            if let value {
                ProgressView(value: value)
                    .progressViewStyle(.linear)
                    .frame(width: 80)
                    .tint(AppColor.accentPrimary)
            }
        }
        .padding(Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
    }

    // MARK: - Sleep detail

    private var sleepDetail: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("LAST NIGHT")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(AppColor.accentLight)

            HStack(spacing: Spacing.lg) {
                sleepStat(
                    label: "Slept",
                    value: context.lastSleepHours.map { String(format: "%.1f h", $0) } ?? "—"
                )
                sleepStat(
                    label: "Target",
                    value: String(format: "%.0f h", context.sleepTargetHours)
                )
                sleepStat(
                    label: "Of target",
                    value: valueForRing.isAvailable ? "\(valueForRing.displayPercent)%" : "—"
                )
            }
        }
    }

    private func sleepStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
    }

    // MARK: - Helpers

    private var navigationTitle: String {
        switch kind {
        case .adherence: String(localized: "Adherence")
        case .recovery:  String(localized: "Recovery")
        case .sleep:     String(localized: "Sleep")
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}
