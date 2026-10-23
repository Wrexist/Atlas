import SwiftUI

/// Top of the Biology tab. Three states:
///
///   • `.locked` — free tier: shows the dial outline + scale + particle
///     cluster where the marker would go, plus a quiet "Included with
///     Atlas Pro" caption. The host's promo card carries the one CTA.
///   • `.needsAge` — Pro tier with no age (or under 18) in Profile: asks
///     for it instead of estimating against a made-up age.
///   • `.building(days:requiredDays:)` — Pro tier without enough data:
///     shows a progress bar and the day count, or asks for more signals
///     when more days alone can't unlock the estimate.
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
    /// Health is connected but returned no heart or sleep data at all —
    /// read access denied, or no Watch. Waiting won't help, so the
    /// building state says so instead of counting days.
    var noHealthData = false
    /// Metrics offered in the header pill's menu alongside Biological Age.
    /// Selecting one opens its history; the host owns that routing.
    var metricShortcuts: [Biomarker] = []
    var onSelectMetric: (Biomarker) -> Void = { _ in }
    var onExplainTapped: () -> Void = {}
    /// Opens where the age is entered. Nil hides the button.
    var onAddAge: (() -> Void)?

    enum BioAgeState: Equatable, Sendable {
        case locked
        case needsAge
        /// `requiredDays` is the day the estimate unlocks with the signals
        /// present; nil when only more signals can unlock it.
        case building(days: Int, requiredDays: Int?)
        case unlocked(estimate: PerformanceAgeEngine.Estimate)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        .appAnimation(AppAnimation.springSmooth, value: state)
        .task(id: estimatedAge) { await reveal(to: estimatedAge) }
    }

    // MARK: - Header

    /// The screen's subject, as a control rather than a caption. Tapping
    /// it lists the other metrics the user tracks.
    private var header: some View {
        metricPill
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
                Image(systemName: "gauge.with.needle")
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
                // The dial is a fixed 280pt; past AX2 the number, unit and
                // info button outgrow its interior and overlap the arc.
                // `AppFont.scaled` ignores this clamp, so the centre fonts
                // also scale for `centreTypeSize`.
                .dynamicTypeSize(...Self.centreTypeSizeLimit)
        }
        .frame(height: 280)
    }

    private static let centreTypeSizeLimit = DynamicTypeSize.accessibility2

    private var centreTypeSize: DynamicTypeSize { min(dynamicTypeSize, Self.centreTypeSizeLimit) }

    private var estimatedAge: Double? {
        guard case .unlocked(let estimate)? = state else { return nil }
        return estimate.biologicalAge
    }

    @ViewBuilder
    private var centreContent: some View {
        switch state {
        case nil:
            resolvingCentre
                .transition(Self.stateTransition)
        case .locked?:
            BioAgeParticleCluster(size: 200)
                .transition(Self.stateTransition)
        case .needsAge?:
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(AppFont.scaled(32, weight: .light, relativeTo: .title1, in: centreTypeSize))
                .foregroundStyle(AppColor.textSecondary)
                .accessibilityHidden(true)
                .transition(Self.stateTransition)
        case .building(let days, let requiredDays)?:
            buildingCentre(progress: Self.buildingProgress(days: days, requiredDays: requiredDays))
                .transition(Self.stateTransition)
        case .unlocked(let estimate)?:
            unlockedCentre(estimate: estimate)
                .transition(Self.stateTransition)
        }
    }

    /// Locked → building → unlocked cross-fade rather than swap.
    private static var stateTransition: AnyTransition { .opacity.combined(with: .scale(scale: 0.96)) }

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
                .font(AppFont.scaled(28, weight: .light, relativeTo: .title1, in: centreTypeSize))
                .foregroundStyle(AppColor.textSecondary)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion && !noHealthData)
                .accessibilityHidden(true)
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
                .font(AppFont.scaled(56, weight: .heavy, design: .rounded, relativeTo: .largeTitle, in: centreTypeSize))
                .foregroundStyle(tint(for: estimate))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText(value: shown))
                .animation(reduceMotion ? nil : AppAnimation.springSmooth, value: shown)
                // A neutral drop, not a tinted halo. Legibility over the
                // starfield only needs the backdrop pushed away.
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0), radius: 8, y: 2)
                .accessibilityLabel(Text("Biological age \(BioAgeFormat.age(estimate.biologicalAge)) years"))
            Text("years")
                .font(AppFont.scaled(16, weight: .medium, in: centreTypeSize))
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
                .font(AppFont.scaled(16, weight: .regular, in: centreTypeSize))
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
            proCaption
                .transition(Self.stateTransition)
        case .needsAge?:
            needsAgeLabel
                .transition(Self.stateTransition)
        case .building(let days, let requiredDays)?:
            buildingLabel(days: days, requiredDays: requiredDays)
                .transition(Self.stateTransition)
        case .unlocked(let estimate)?:
            unlockedSummary(estimate: estimate)
                .transition(Self.stateTransition)
        }
    }

    /// A quiet note, not a second button: the promo card below the hero
    /// is the one place to upgrade.
    private var proCaption: some View {
        Label("Included with Atlas Pro", systemImage: "lock.fill")
            .font(AppFont.scaled(13, weight: .semibold))
            .foregroundStyle(AppColor.textSecondary)
    }

    private var needsAgeLabel: some View {
        let isUnderage = (1..<BioAgeStateResolver.minimumAge).contains(chronologicalAge)
        return VStack(spacing: Spacing.md) {
            Text(isUnderage
                ? String(localized: "Biological Age is available for users 18+.")
                : String(localized: "Add your age in Profile to see your Biological Age."))
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            // The one step between the user and the estimate, one tap
            // away instead of a hunt through Profile.
            if !isUnderage, let onAddAge {
                GlassButton(title: "Open Profile", icon: "person.crop.circle", style: .secondary) {
                    Haptics.impact(.light)
                    onAddAge()
                }
            }
        }
    }

    @ViewBuilder
    private func buildingLabel(days: Int, requiredDays: Int?) -> some View {
        if noHealthData {
            Text("Atlas can't see any heart or sleep data. Check that Atlas has read access in the Health app, and wear Apple Watch overnight.")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
        } else {
            buildingProgressLabel(days: days, requiredDays: requiredDays)
        }
    }

    /// Days against the unlock day when more days will get there;
    /// otherwise the missing signals are what's holding it back.
    private func buildingProgressLabel(days: Int, requiredDays: Int?) -> some View {
        VStack(spacing: Spacing.xs) {
            if let requiredDays {
                Text("\(min(days, requiredDays)) of \(requiredDays) days of data collected")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
            } else {
                Text("A few more signals will unlock your estimate.")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Spacing.xl)
    }

    /// Share of the unlock day reached; when only signals are missing,
    /// the share of the full confidence window instead.
    static func buildingProgress(days: Int, requiredDays: Int?) -> Double {
        let target = max(1, requiredDays ?? PerformanceAgeEngine.windowDays)
        return min(1, Double(max(0, days)) / Double(target))
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
        let absDelta = abs(delta) < Self.matchingTolerance ? 0 : abs(delta)
        let badgeTint = tint(for: estimate)
        let label: String = {
            if absDelta == 0 {
                return String(localized: "Matching your age")
            }
            let formatted = BioAgeFormat.age(absDelta)
            return delta < 0
                ? String(format: String(localized: "%@ years younger"), formatted)
                : String(format: String(localized: "%@ years older"), formatted)
        }()
        return HStack(spacing: Spacing.xs) {
            Image(systemName: absDelta == 0 ? "equal" : (delta < 0 ? "sparkles" : "arrow.up.right"))
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
        estimate.biologicalAge - Double(chronologicalAge) < Self.matchingTolerance
            ? AppColor.positive
            : AppColor.negative
    }

    /// Below this many years either way the badge reads "Matching your
    /// age", so the tint treats it as matching too.
    private static let matchingTolerance = 0.05

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
}

#Preview("Locked") {
    ZStack {
        CosmicBackdrop(intensity: 0.55).ignoresSafeArea()
        BioAgeHeroSection(
            state: .locked,
            chronologicalAge: 26
        )
    }
}

#Preview("Building (4 of 15 days)") {
    ZStack {
        CosmicBackdrop(intensity: 0.55).ignoresSafeArea()
        BioAgeHeroSection(
            state: .building(days: 4, requiredDays: 15),
            chronologicalAge: 26
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
            chronologicalAge: 26
        )
    }
}
