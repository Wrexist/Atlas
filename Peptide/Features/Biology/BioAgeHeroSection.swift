import SwiftUI

/// Top of the Biology tab. Three states:
///
///   • `.locked` — free tier: shows the dial outline + scale +
///     particle cluster where the marker would go, plus an
///     "Unlock with Pro" capsule. Aspirational, not punitive —
///     the user sees what they could have.
///   • `.building(progress:)` — Pro tier but < 7 days of HealthKit
///     data: shows "Building your baseline" with a progress bar.
///     Encouragement, not failure.
///   • `.unlocked(estimate:)` — Pro tier + sufficient data: the real
///     bio-age render, marker at position, big number in the middle,
///     delta badge and the three contributing signals underneath.
struct BioAgeHeroSection: View {
    let state: BioAgeState
    let chronologicalAge: Int
    let asOfDate: Date
    var onUnlockTapped: () -> Void = {}
    /// Metrics offered in the header pill's menu alongside Bio Age.
    /// Selecting one opens its history; the host owns that routing.
    var metricShortcuts: [Biomarker] = []
    var onSelectMetric: (Biomarker) -> Void = { _ in }
    var onExplainTapped: () -> Void = {}

    enum BioAgeState: Equatable, Sendable {
        case locked
        case building(progress: Double)               // 0…1, share of 7-day baseline collected
        case unlocked(estimate: PerformanceAgeEngine.Estimate)
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            header
            dialStack
            stateAffordance
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.sm)
    }

    // MARK: - Header

    /// The screen's subject, as a control rather than a caption. Tapping
    /// it lists the other metrics the user tracks, so Bio Age is one of
    /// the things Biology can be about rather than the only one.
    private var header: some View {
        VStack(spacing: Spacing.xs) {
            metricPill
            Text("As of \(Self.asOfFormatter.string(from: asOfDate))")
                .font(AppFont.scaled(13, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private var metricPill: some View {
        Menu {
            Section {
                Button {
                    // Already the hero — the item exists to show what the
                    // checkmark is attached to.
                } label: {
                    Label("Biological Age", systemImage: "checkmark")
                }
                .disabled(true)
            }
            if !metricShortcuts.isEmpty {
                Section("Your biomarkers") {
                    ForEach(metricShortcuts, id: \.self) { biomarker in
                        Button {
                            onSelectMetric(biomarker)
                        } label: {
                            Label(biomarker.displayName, systemImage: biomarker.icon)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "calendar")
                    .font(AppFont.scaled(13, weight: .semibold))
                Text("Biological Age")
                    .font(AppFont.scaled(16, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(AppFont.scaled(11, weight: .bold))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .foregroundStyle(AppColor.textPrimary)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .glassControl(.capsule)
            .minimumHitArea()
        }
        .accessibilityLabel("Biological Age. Choose a metric")
    }

    // MARK: - Dial + centre content

    private var dialStack: some View {
        ZStack {
            BioAgeDial(
                chronologicalAge: chronologicalAge,
                bioAge: dialMarkerValue,
                size: 280
            )
            centreContent
        }
        .frame(height: 280)
    }

    private var dialMarkerValue: Double? {
        switch state {
        case .locked, .building:                       return nil
        case .unlocked(let estimate):                  return estimate.biologicalAge
        }
    }

    @ViewBuilder
    private var centreContent: some View {
        switch state {
        case .locked:
            BioAgeParticleCluster(size: 200)
        case .building(let progress):
            buildingCentre(progress: progress)
        case .unlocked(let estimate):
            unlockedCentre(estimate: estimate)
        }
    }

    private func buildingCentre(progress: Double) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: "hourglass")
                .font(AppFont.scaled(28, weight: .light, relativeTo: .title1))
                .foregroundStyle(AppColor.textSecondary)
            Text("Building")
                .font(AppFont.scaled(13, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(AppColor.textSecondary)
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(AppColor.accentLight)
                .frame(width: 140)
        }
    }

    /// The number, its unit, and the way in. Sign-tinted so "younger than
    /// chronological" / "older than chronological" reads in the first
    /// 200ms of glance time.
    private func unlockedCentre(estimate: PerformanceAgeEngine.Estimate) -> some View {
        let isYounger = estimate.biologicalAge < Double(chronologicalAge)
        return VStack(spacing: 2) {
            Text(Self.bigNumberFormatter.string(from: NSNumber(value: estimate.biologicalAge)) ?? "—")
                .font(AppFont.scaled(56, weight: .heavy, design: .rounded, relativeTo: .largeTitle))
                .foregroundStyle(unlockedTint(isYounger: isYounger))
                .monospacedDigit()
                .contentTransition(.numericText())
                // A neutral drop, not a tinted halo. The number already
                // carries its own colour; legibility over the starfield
                // only needs the backdrop pushed away from it.
                .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
            Text("years")
                .font(AppFont.scaled(16, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
            explainButton
                .padding(.top, Spacing.xs)
        }
    }

    /// How the number was arrived at, one tap away. A bio-age estimate
    /// that can't explain itself is a number the user has no reason to
    /// trust.
    private var explainButton: some View {
        Button(action: onExplainTapped) {
            Image(systemName: "info.circle")
                .font(AppFont.scaled(16, weight: .regular))
                .foregroundStyle(AppColor.textTertiary)
                .minimumHitArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How Bio Age is calculated")
    }

    // MARK: - State affordance (Pro pill / progress label / delta + drivers)

    @ViewBuilder
    private var stateAffordance: some View {
        switch state {
        case .locked:
            unlockPill
        case .building(let progress):
            buildingLabel(progress: progress)
        case .unlocked(let estimate):
            unlockedSummary(estimate: estimate)
        }
    }

    private var unlockPill: some View {
        Button(action: onUnlockTapped) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "lock.fill")
                    .font(AppFont.scaled(11, weight: .heavy))
                Text("Unlock with Pro")
                    .font(AppFont.scaled(13, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(AppColor.textPrimary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .glassControl(.capsule)
            .minimumHitArea()
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.95))
        .accessibilityLabel("Unlock biological age with Pro")
    }

    private func buildingLabel(progress: Double) -> some View {
        // `progress` from BioAgeStateResolver is `dataDays / minBaselineDays`
        // — a fraction of the 7-day baseline *window*, NOT a fraction of the
        // three HRV/RHR/Sleep signals. Render the day count it represents,
        // keyed off `minBaselineDays` so the two never drift apart.
        let total = BioAgeStateResolver.minBaselineDays
        let days = max(0, min(total, Int((progress * Double(total)).rounded())))
        return Text("\(days) of \(total) days of data collected")
            .font(AppFont.scaled(13, weight: .semibold))
            .foregroundStyle(AppColor.textSecondary)
    }

    /// Below the dial: the delta-from-chronological badge, then the
    /// signals moving it. "1.5 years younger" is the headline; the driver
    /// chips are the small print explaining why.
    private func unlockedSummary(estimate: PerformanceAgeEngine.Estimate) -> some View {
        VStack(spacing: Spacing.md) {
            deltaBadge(for: estimate)
            if !estimate.drivers.isEmpty {
                driversRow(estimate: estimate)
            }
        }
    }

    private func deltaBadge(for estimate: PerformanceAgeEngine.Estimate) -> some View {
        let delta = estimate.biologicalAge - Double(chronologicalAge)
        let absDelta = abs(delta)
        let absRounded = absDelta < 0.05 ? 0 : absDelta
        let isYounger = delta < 0
        let tint = unlockedTint(isYounger: isYounger)
        let label: String = {
            if absRounded == 0 {
                return String(localized: "Matching your age")
            }
            let formatted = String(format: "%.1f", absRounded)
            return isYounger
                ? String(format: String(localized: "%@ years younger"), formatted)
                : String(format: String(localized: "%@ years older"), formatted)
        }()
        return HStack(spacing: Spacing.xs) {
            Image(systemName: absRounded == 0 ? "equal" : "sparkles")
                .font(AppFont.scaled(11, weight: .heavy))
            Text(label)
                .font(AppFont.scaled(13, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background {
            Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// Top three contributors by absolute impact. Drivers arrive sorted
    /// from the engine; we just trim. Equal-width chips so the row reads
    /// as one comparison rather than three unrelated pills.
    private func driversRow(estimate: PerformanceAgeEngine.Estimate) -> some View {
        HStack(spacing: Spacing.sm) {
            ForEach(estimate.drivers.prefix(3)) { driver in
                DriverChip(
                    icon: driverIcon(for: driver.kind),
                    label: driverLabel(for: driver.kind),
                    deltaYears: driver.deltaYears,
                    tint: unlockedTint(isYounger: driver.deltaYears < 0)
                )
            }
        }
    }

    private func driverIcon(for kind: PerformanceAgeEngine.Driver.Kind) -> String {
        switch kind {
        case .hrv:    return "heart"
        case .rhr:    return "waveform.path.ecg"
        case .sleep:  return "moon.fill"
        case .weight: return "scalemass.fill"
        }
    }

    private func driverLabel(for kind: PerformanceAgeEngine.Driver.Kind) -> LocalizedStringKey {
        switch kind {
        case .hrv:    return "HRV"
        case .rhr:    return "RHR"
        case .sleep:  return "Sleep"
        case .weight: return "Weight"
        }
    }

    /// Tint applied to the big bio-age number, the delta badge, and the
    /// driver chips. Green when younger / matching; warm orange when
    /// older. Saturated enough that the cosmic backdrop doesn't wash
    /// them out.
    private func unlockedTint(isYounger: Bool) -> Color {
        isYounger ? AppColor.positive : AppColor.negative
    }

    // MARK: - Formatters

    private static let asOfFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()

    private static let bigNumberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f
    }()
}

/// One contributing signal — HRV, RHR, Sleep — and the years it is
/// pulling the estimate. Fixed-height card so the three sit as a row of
/// peers; the tint is the only thing that differs between "helping" and
/// "hurting".
private struct DriverChip: View {
    let icon: String
    let label: LocalizedStringKey
    let deltaYears: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
                Spacer(minLength: 0)
            }
            Text(signed)
                .font(AppFont.scaled(16, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .strokeBorder(AppColor.glassBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(signed)
    }

    private var signed: String {
        String(format: "%@%.1fy", deltaYears > 0 ? "+" : "", deltaYears)
    }
}

#Preview("Locked") {
    ZStack {
        CosmicBackdrop(intensity: 0.55).ignoresSafeArea()
        BioAgeHeroSection(
            state: .locked,
            chronologicalAge: 26,
            asOfDate: Date()
        )
    }
}

#Preview("Building (4 of 7 days)") {
    ZStack {
        CosmicBackdrop(intensity: 0.55).ignoresSafeArea()
        BioAgeHeroSection(
            state: .building(progress: 4.0 / 7.0),
            chronologicalAge: 26,
            asOfDate: Date()
        )
    }
}

#Preview("Unlocked") {
    ZStack {
        CosmicBackdrop(intensity: 0.55).ignoresSafeArea()
        BioAgeHeroSection(
            state: .unlocked(estimate: .init(
                biologicalAge: 24.5,
                confidence: 0.8,
                drivers: [
                    .init(kind: .hrv, deltaYears: -1.1),
                    .init(kind: .rhr, deltaYears: -0.5),
                    .init(kind: .sleep, deltaYears: 0.1),
                ]
            )),
            chronologicalAge: 26,
            asOfDate: Date()
        )
    }
}
