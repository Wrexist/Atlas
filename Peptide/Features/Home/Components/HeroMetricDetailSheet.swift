import SwiftUI

/// Detail sheet presented when the user taps one of the Today hero-trio
/// rings. Same shell for all three metrics; the content switches per
/// `kind`. A big focal ring, why the number is worth caring about, and
/// then either what's driving it (Recovery), what it's made of (Sleep),
/// or what's still outstanding (Adherence).
///
/// Every metric carries one colour the whole way down — ring, eyebrow,
/// medallion, values — so the three sheets read as three subjects rather
/// than one template filled in three times.
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
    @Environment(\.openURL) private var openURL
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState

    /// Drives the per-signal history sheet a Recovery driver row opens.
    @State private var driverDetail: DriverDetailItem?

    private struct DriverDetailItem: Identifiable {
        let biomarker: Biomarker
        var id: Biomarker { biomarker }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    heroBlock
                    explainer
                    detailContent
                }
                .padding(Spacing.screenPadding)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(AppColor.background)
            .navigationTitle(kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "checkmark.circle")
                                .accessibilityHidden(true)
                            Text("Done")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    overflowMenu
                }
            }
            .sheet(item: $driverDetail) { item in
                BiomarkerDetailSheet(
                    biomarker: item.biomarker,
                    initialSnapshot: .empty(item.biomarker),
                    historicalFetcher: { await fetchSeries(for: item.biomarker) },
                    unit: dataStore.profile.bodyMetrics.unit
                )
                .liquidGlassPresentation()
            }
        }
    }

    // MARK: - Overflow

    /// One real action per metric. An overflow that opens to a single
    /// disabled item is worse than no overflow, so Adherence routes to
    /// the protocols that produce its doses and the two HealthKit-backed
    /// metrics route to the app that owns their data.
    @ViewBuilder
    private var overflowMenu: some View {
        Menu {
            switch kind {
            case .adherence:
                Button {
                    dismiss()
                    appState.showLibrary = true
                } label: {
                    Label("Manage protocols", systemImage: "list.bullet.rectangle")
                }
            case .recovery, .sleep:
                Button {
                    if let url = URL(string: "x-apple-health://") { openURL(url) }
                } label: {
                    Label("Open Apple Health", systemImage: "heart.text.square")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .minimumHitArea()
        }
        .accessibilityLabel("More actions")
    }

    // MARK: - Hero

    private var heroBlock: some View {
        HStack(alignment: .center, spacing: Spacing.lg) {
            MetricRing(
                progress: valueForRing.progress,
                diameter: 140,
                strokeWidth: 12,
                gradient: kind.gradient(active: valueForRing.isAvailable),
                appearAnimated: true
            ) {
                VStack(spacing: 2) {
                    Image(systemName: kind.icon)
                        .font(AppFont.scaled(20, weight: .semibold))
                        .foregroundStyle(ringTint)
                        .accessibilityHidden(true)
                    if valueForRing.isAvailable {
                        Text("\(valueForRing.displayPercent)%")
                            .font(AppFont.scaled(36, weight: .heavy, design: .rounded, relativeTo: .largeTitle))
                            .foregroundStyle(AppColor.textPrimary)
                            .monospacedDigit()
                    } else {
                        Text("—")
                            .font(AppFont.scaled(36, weight: .bold, relativeTo: .largeTitle))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            // No glow behind the arc. `design-lint`'s `glow` rule names
            // a halo around a stroked ring as the exact construct it
            // exists to stop, and `MetricRing`'s `glow` parameter was
            // deleted rather than defaulted off for the same reason. The
            // ring is the hero here on size and stroke weight instead.

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(kind.label)
                    .font(AppFont.title)
                    .fontWeight(.heavy)
                    .foregroundStyle(AppColor.textPrimary)
                if let line = supportingLine {
                    Text(line)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let line = targetLine {
                    Text(line)
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(ringTint)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// The metric's single colour, taken off the head of its own ring
    /// gradient so the two can never drift apart.
    private var ringTint: Color {
        kind.gradient(active: true).first ?? AppColor.accentPrimary
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
            return String(format: String(localized: "%@ last night"), String(format: "%.1f h", hours))
        }
    }

    /// Sleep is the only metric with a target the user is measured
    /// against, and it earns its own tinted line rather than a "· target
    /// 8 h" tail nobody reads.
    private var targetLine: String? {
        guard case .sleep = kind,
              let hours = context.lastSleepHours, hours > 0 else { return nil }
        return String(format: String(localized: "Target %@"),
                      String(format: "%.0f h", context.sleepTargetHours))
    }

    // MARK: - Explainer

    private var explainer: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: kind.explainerIcon)
                .font(AppFont.scaled(20, weight: .semibold))
                .foregroundStyle(ringTint)
                .frame(width: 48, height: 48)
                .background { Circle().fill(ringTint.opacity(0.18)) }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("WHY IT MATTERS")
                    .font(AppFont.scaled(11, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(ringTint)
                Text(explainerBody)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(ringTint.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(ringTint.opacity(0.20), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
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

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(AppFont.scaled(11, weight: .heavy, design: .rounded))
            .tracking(1.0)
            .foregroundStyle(AppColor.textSecondary)
    }

    // MARK: - Adherence list

    private var adherenceList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("TODAY'S DOSES")

            if context.todayEntries.isEmpty {
                emptyDoseCard
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(context.todayEntries) { entry in
                        doseRow(entry)
                    }
                }
            }
        }
    }

    /// An empty schedule is a *good* outcome on this sheet, so it says so
    /// rather than leaving a bare sentence where the list would be.
    private var emptyDoseCard: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.square")
                .font(AppFont.scaled(28, weight: .light, relativeTo: .title1))
                .foregroundStyle(AppColor.textSecondary)
            Text("No doses scheduled.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            Text("You're all caught up!")
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(ringTint)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xl)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .accessibilityElement(children: .combine)
    }

    private func doseRow(_ entry: ProtocolEntry) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: entry.completed ? "checkmark.circle.fill" : "circle")
                .font(AppFont.scaled(16, weight: .semibold))
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
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Recovery breakdown

    private var recoveryBreakdown: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("WHAT'S DRIVING IT")

            if let components = context.recoveryComponents {
                driverRow(.hrv, value: components.hrv)
                driverRow(.sleep, value: components.sleep)
                driverRow(.rhr, value: components.rhr)
                if let tip = recoveryTip(for: components) {
                    tipCard(tip)
                }
            } else {
                Text("Connect Apple Health and wear your Apple Watch to start tracking these signals.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.vertical, Spacing.sm)
            }
        }
    }

    /// The three signals `RecoveryScoreEngine` composes. Each carries its
    /// own colour — the same one the Biology tab uses for that signal —
    /// and opens the 90-day history for it.
    private enum RecoveryDriver {
        case hrv, sleep, rhr

        var label: LocalizedStringKey {
            switch self {
            case .hrv:   "HRV vs baseline"
            case .sleep: "Sleep vs 8h target"
            case .rhr:   "Resting HR vs baseline"
            }
        }

        var icon: String {
            switch self {
            case .hrv:   "waveform.path.ecg"
            case .sleep: "bed.double.fill"
            case .rhr:   "heart.fill"
            }
        }

        var tint: Color {
            switch self {
            case .hrv:   AppColor.metricHRV
            case .sleep: AppColor.metricSleep
            case .rhr:   AppColor.metricHeartRate
            }
        }

        var biomarker: Biomarker {
            switch self {
            case .hrv:   .hrvBaseline
            case .sleep: .sleepBaseline
            case .rhr:   .rhrBaseline
            }
        }
    }

    private func driverRow(_ driver: RecoveryDriver, value: Double?) -> some View {
        Button {
            Haptics.impact(.light)
            driverDetail = DriverDetailItem(biomarker: driver.biomarker)
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: driver.icon)
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(driver.tint)
                    .frame(width: 40, height: 40)
                    .background { Circle().fill(driver.tint.opacity(0.18)) }

                VStack(alignment: .leading, spacing: 2) {
                    Text(driver.label)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(value.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                        .font(AppFont.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(driver.tint)
                        .monospacedDigit()
                }

                Spacer(minLength: Spacing.sm)

                if let value {
                    GlassProgressBar(
                        progress: value,
                        height: 4,
                        gradient: [driver.tint.opacity(0.6), driver.tint]
                    )
                    .frame(width: 80)
                }

                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.55))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityElement(children: .combine)
    }

    /// Names the weakest of the three signals rather than offering
    /// generic advice — the score is a composite, so the only useful tip
    /// is which part of it to go work on.
    private func recoveryTip(for components: RecoveryScoreEngine.Components) -> LocalizedStringKey? {
        var scored: [(driver: RecoveryDriver, value: Double)] = []
        if let hrv = components.hrv { scored.append((.hrv, hrv)) }
        if let sleep = components.sleep { scored.append((.sleep, sleep)) }
        if let rhr = components.rhr { scored.append((.rhr, rhr)) }

        guard let weakest = scored.min(by: { $0.value < $1.value }) else { return nil }
        // Everything already at or near ceiling — congratulate rather
        // than manufacture a deficiency.
        guard weakest.value < 0.85 else {
            return "All three signals are near your baseline. Keep doing what you're doing."
        }
        switch weakest.driver {
        case .hrv:
            return "HRV is the signal holding your score back. It responds to stress load and alcohol faster than anything else here."
        case .sleep:
            return "Sleep is the signal holding your score back. An earlier bedtime moves this number faster than anything else you can do today."
        case .rhr:
            return "Resting heart rate is the signal holding your score back. It climbs with heat, illness, and hard training days."
        }
    }

    private func tipCard(_ tip: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "sparkles")
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(ringTint)
                .frame(width: 40, height: 40)
                .background { Circle().fill(ringTint.opacity(0.18)) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tip")
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                Text(tip)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .padding(.top, Spacing.sm)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Sleep detail

    private var sleepDetail: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("LAST NIGHT")

            HStack(spacing: Spacing.md) {
                sleepStat(
                    icon: "clock",
                    label: "Slept",
                    value: context.lastSleepHours.map { String(format: "%.1f h", $0) } ?? "—"
                )
                sleepStat(
                    icon: "target",
                    label: "Target",
                    value: String(format: "%.0f h", context.sleepTargetHours)
                )
                sleepStat(
                    icon: "star.fill",
                    label: "Of target",
                    value: valueForRing.isAvailable ? "\(valueForRing.displayPercent)%" : "—"
                )
            }
        }
    }

    private func sleepStat(icon: String, label: LocalizedStringKey, value: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(ringTint)
                .accessibilityHidden(true)
            Text(value)
                .font(AppFont.scaled(20, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(.vertical, Spacing.lg)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    // MARK: - Helpers

    /// 90-day series for a driver's biomarker, on the same path the
    /// Biology tab uses so both surfaces show the identical history.
    private func fetchSeries(for biomarker: Biomarker) async -> BiomarkerSnapshot? {
        let latestLab = dataStore.latestLabSummaries
            .max(by: { $0.latest.date < $1.latest.date })?
            .latest
        let snapshots = await BiomarkerSeriesService.snapshots(
            for: [biomarker],
            weightHistory: dataStore.profile.weightHistory,
            latestLab: latestLab,
            days: BiomarkerSeriesService.detailWindowDays,
            unit: dataStore.profile.bodyMetrics.unit
        )
        return snapshots.first
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}
