import SwiftUI

/// Top of the Biology tab. Three states:
///
///   • `.locked` — free tier: shows the dial outline + scale + particle
///     cluster where the marker would go, plus an "Unlock with Pro"
///     capsule. Aspirational, not punitive.
///   • `.building(progress:)` — Pro tier without enough data: shows
///     "Building" with a progress bar and the day count.
///   • `.unlocked(estimate:)` — Pro tier + sufficient data: the arc sweeps
///     up to the estimate as the number rolls to it, then the delta against
///     chronological age and how sure the estimate is.
///
/// `nil` state means the resolver hasn't answered yet: the dial shows a
/// neutral placeholder and no affordance, so a Pro user never sees the
/// locked upsell flash while HealthKit is read.
struct BioAgeHeroSection: View {
    let state: BioAgeState?
    let chronologicalAge: Int
    let asOfDate: Date
    var onUnlockTapped: () -> Void = {}
    /// Metrics offered in the header pill's menu alongside Biological Age.
    /// Selecting one opens its history; the host owns that routing.
    var metricShortcuts: [Biomarker] = []
    var onSelectMetric: (Biomarker) -> Void = { _ in }
    var onExplainTapped: () -> Void = {}

    enum BioAgeState: Equatable, Sendable {
        case locked
        case building(progress: Double)               // 0…1, share of 7-day baseline collected
        case unlocked(estimate: PerformanceAgeEngine.Estimate)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What the dial and the number show. Starts at the dial's younger
    /// bound and is animated to the estimate, so the arc sweeps in and the
    /// digits roll rather than the result just appearing.
    @State private var displayedAge: Double?
    @State private var hasPlayedReveal = false

    var body: some View {
        VStack(spacing: Spacing.md) {
            header
            dialStack
            stateAffordance
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.sm)
        .task(id: estimatedAge) { await reveal(to: estimatedAge) }
    }

    // MARK: - Header

    /// The screen's subject, as a control rather than a caption. Tapping
    /// it lists the other metrics the user tracks.
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
                bioAge: displayedAge,
                size: 280
            )
            centreContent
        }
        .frame(height: 280)
    }

    private var estimatedAge: Double? {
        guard case .unlocked(let estimate)? = state else { return nil }
        return estimate.biologicalAge
    }

    @ViewBuilder
    private var centreContent: some View {
        switch state {
        case nil:
            resolvingCentre
        case .locked?:
            BioAgeParticleCluster(size: 200)
        case .building(let progress)?:
            buildingCentre(progress: progress)
        case .unlocked(let estimate)?:
            unlockedCentre(estimate: estimate)
        }
    }

    private var resolvingCentre: some View {
        Circle()
            .fill(AppColor.surfaceSecondary.opacity(0.6))
            .frame(width: 120, height: 120)
            .shimmer()
            .accessibilityHidden(true)
    }

    private func buildingCentre(progress: Double) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: "hourglass")
                .font(AppFont.scaled(28, weight: .light, relativeTo: .title1))
                .foregroundStyle(AppColor.textSecondary)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            Text("Building")
                .font(AppFont.scaled(13, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(AppColor.textSecondary)
            GlassProgressBar(progress: progress)
                .frame(width: 140)
        }
    }

    /// The number, its unit, and the way in. Sign-tinted so "younger" /
    /// "older" reads in the first glance.
    private func unlockedCentre(estimate: PerformanceAgeEngine.Estimate) -> some View {
        let shown = displayedAge ?? estimate.biologicalAge
        return VStack(spacing: Spacing.xxs) {
            Text(BioAgeFormat.age(shown))
                .font(AppFont.scaled(56, weight: .heavy, design: .rounded, relativeTo: .largeTitle))
                .foregroundStyle(tint(for: estimate))
                .monospacedDigit()
                .contentTransition(.numericText(value: shown))
                .animation(reduceMotion ? nil : AppAnimation.springSmooth, value: shown)
                // A neutral drop, not a tinted halo. Legibility over the
                // starfield only needs the backdrop pushed away.
                .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                .accessibilityLabel(Text("Biological age \(BioAgeFormat.age(estimate.biologicalAge)) years"))
            Text("years")
                .font(AppFont.scaled(16, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
                .accessibilityHidden(true)
            explainButton
                .padding(.top, Spacing.xs)
        }
    }

    /// How the number was arrived at, one tap away.
    private var explainButton: some View {
        Button(action: onExplainTapped) {
            Image(systemName: "info.circle")
                .font(AppFont.scaled(16, weight: .regular))
                .foregroundStyle(AppColor.textTertiary)
                .minimumHitArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How Biological Age is calculated")
    }

    // MARK: - State affordance

    @ViewBuilder
    private var stateAffordance: some View {
        switch state {
        case nil:
            EmptyView()
        case .locked?:
            unlockPill
        case .building(let progress)?:
            buildingLabel(progress: progress)
        case .unlocked(let estimate)?:
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
        // `progress` is `dataDays / minBaselineDays` — a fraction of the
        // 7-day baseline window. Render the day count it represents.
        let total = BioAgeStateResolver.minBaselineDays
        let days = max(0, min(total, Int((progress * Double(total)).rounded())))
        return VStack(spacing: Spacing.xs) {
            Text("\(days) of \(total) days of data collected")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
            if days >= total {
                Text("Enough days — a few more signals will unlock your estimate.")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Spacing.xl)
    }

    /// Below the dial: the delta against chronological age, then what it
    /// was read against and how sure it is.
    private func unlockedSummary(estimate: PerformanceAgeEngine.Estimate) -> some View {
        VStack(spacing: Spacing.sm) {
            deltaBadge(for: estimate)
            Text(contextLine(for: estimate))
                .font(AppFont.scaled(13, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func contextLine(for estimate: PerformanceAgeEngine.Estimate) -> String {
        let confidence = Self.confidenceLabel(estimate.confidence)
        return String(localized: "Chronological age \(chronologicalAge) · \(confidence)")
    }

    /// Three words for a 0…1 score. Deliberately coarse — a percentage
    /// would claim a precision the estimate doesn't have.
    static func confidenceLabel(_ confidence: Double) -> String {
        if confidence >= 0.9 { return String(localized: "High confidence") }
        if confidence >= 0.75 { return String(localized: "Good confidence") }
        return String(localized: "Early estimate")
    }

    private func deltaBadge(for estimate: PerformanceAgeEngine.Estimate) -> some View {
        let delta = estimate.biologicalAge - Double(chronologicalAge)
        let absDelta = abs(delta) < 0.05 ? 0 : abs(delta)
        let badgeTint = tint(for: estimate)
        let label: String = {
            if absDelta == 0 {
                return String(localized: "Matching your age")
            }
            let formatted = String(format: "%.1f", absDelta)
            return delta < 0
                ? String(format: String(localized: "%@ years younger"), formatted)
                : String(format: String(localized: "%@ years older"), formatted)
        }()
        return HStack(spacing: Spacing.xs) {
            Image(systemName: absDelta == 0 ? "equal" : "sparkles")
                .font(AppFont.scaled(11, weight: .heavy))
                .symbolEffect(.bounce, value: hasPlayedReveal && !reduceMotion)
                .accessibilityHidden(true)
            Text(label)
                .font(AppFont.scaled(13, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(badgeTint)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background {
            Capsule().strokeBorder(badgeTint.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// Green when younger / matching; warm orange when older.
    private func tint(for estimate: PerformanceAgeEngine.Estimate) -> Color {
        estimate.biologicalAge <= Double(chronologicalAge) ? AppColor.positive : AppColor.negative
    }

    // MARK: - Reveal

    /// Sweeps the dial and rolls the number from the younger bound to the
    /// estimate the first time it lands, then animates later changes
    /// directly. Under Reduce Motion the value is simply set.
    private func reveal(to target: Double?) async {
        guard let target else {
            displayedAge = nil
            return
        }
        if reduceMotion {
            displayedAge = target
            playRevealHaptic()
            return
        }
        if displayedAge == nil {
            displayedAge = Double(chronologicalAge - 5)
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
        }
        withAnimation(AppAnimation.springGentle) {
            displayedAge = target
        }
        playRevealHaptic()
    }

    private func playRevealHaptic() {
        guard !hasPlayedReveal else { return }
        hasPlayedReveal = true
        Haptics.impact(.soft)
    }

    // MARK: - Formatters

    private static let asOfFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()
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
                    .init(kind: .hrv, deltaYears: -1.1, value: 58, reference: 42.5),
                    .init(kind: .rhr, deltaYears: -0.5, value: 60, reference: 65),
                    .init(kind: .sleep, deltaYears: 0.1, value: 7.4, reference: 7.5),
                ]
            )),
            chronologicalAge: 26,
            asOfDate: Date()
        )
    }
}
