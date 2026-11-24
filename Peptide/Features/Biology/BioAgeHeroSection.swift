import SwiftUI

/// Top of the Biology tab. Until there is a number, a ghosted dial holds
/// its place with a dash, and one line under it names the step to get one:
///
///   • `.locked` — free tier: nothing here. The host's promo card carries
///     the one CTA, so an empty dial above it added nothing.
///   • `.needsAge` — Pro tier with no age (or under 18) in Profile: the
///     line asks for it instead of estimating against a made-up age.
///   • `.building(days:requiredDays:)` — Pro tier without enough data:
///     the one action is connecting Apple Health while it isn't; after
///     that, the Watch guidance with the day count and a progress bar,
///     and a way to check Atlas's Health access in Settings.
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
    /// Set while Apple Health isn't connected: the building state's one
    /// button asks for access. Nil once connected.
    var onConnectHealth: (() -> Void)?
    var onExplainTapped: () -> Void = {}
    /// Opens where the age is entered. Nil hides the button.
    var onAddAge: (() -> Void)?

    enum BioAgeState: Equatable, Sendable {
        case locked
        case needsAge
        /// `requiredDays` is the day the estimate unlocks with the signals
        /// present; nil when only more signals can unlock it.
        case building(days: Int, requiredDays: Int?)
        case unlocked(estimate: BiologicalAgeEngine.Estimate)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
    /// What the dial and the number show. Starts at the dial's younger
    /// bound and is animated to the estimate, so the arc sweeps in and the
    /// digits roll rather than the result just appearing.
    @State private var displayedAge: Double?
    @State private var hasPlayedReveal = false

    var body: some View {
        Group {
            switch state {
            case nil, .unlocked(_)?:
                VStack(spacing: Spacing.md) {
                    header
                    dialStack
                    if case .unlocked(let estimate)? = state {
                        unlockedSummary(estimate: estimate)
                            .transition(Self.stateTransition)
                    }
                }
                .padding(.top, Spacing.sm)
            case .locked?:
                EmptyView()
            case .needsAge?, .building(_, _)?:
                VStack(spacing: Spacing.lg) {
                    VStack(spacing: Spacing.md) {
                        header
                        ghostDial
                    }
                    setupStep
                        .frame(maxWidth: Self.setupWidth)
                }
                .padding(.top, Spacing.sm)
                .transition(Self.stateTransition)
            }
        }
        .frame(maxWidth: .infinity)
        .appAnimation(AppAnimation.springSmooth, value: state)
        .task(id: estimatedAge) { await reveal(to: estimatedAge) }
    }

    // MARK: - Header

    /// The dial's label: a quiet eyebrow centred on the dial's axis, so the
    /// screen's large title stays its only heading. It sits in the stack
    /// above the dial's frame, so it never runs into the arc as it grows.
    private var header: some View {
        Text("Biological Age")
            .textCase(.uppercase)
            .font(AppFont.eyebrow)
            .tracking(1.0)
            .foregroundStyle(AppColor.textSecondary)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Dial + centre content

    private var dialStack: some View {
        ZStack {
            BioAgeDial(
                chronologicalAge: chronologicalAge,
                bioAge: displayedAge,
                size: Self.dialSize
            )
            centreContent
                // The dial is a fixed 280pt; past AX2 the number and its
                // unit outgrow its interior and overlap the arc.
                // `AppFont.scaled` ignores this clamp, so the centre fonts
                // also scale for `centreTypeSize`.
                .dynamicTypeSize(...Self.centreTypeSizeLimit)
        }
        .frame(height: Self.dialSize)
        // The arc opens at the bottom: below its bound labels the square
        // frame is empty, so the caption is pulled up into that band.
        .padding(.bottom, -Self.dialOpenBand)
    }

    private static let dialSize: CGFloat = 280
    /// The empty strip under the dial's bound labels, which the content
    /// below tucks into.
    private static var dialOpenBand: CGFloat { BioAgeDial.openBandHeight(size: dialSize) }

    private static let centreTypeSizeLimit = DynamicTypeSize.accessibility2

    private var centreTypeSize: DynamicTypeSize { min(dynamicTypeSize, Self.centreTypeSizeLimit) }

    private var estimatedAge: Double? {
        guard case .unlocked(let estimate)? = state else { return nil }
        return estimate.biologicalAge
    }

    @ViewBuilder
    private var centreContent: some View {
        if case .unlocked(let estimate)? = state {
            unlockedCentre(estimate: estimate)
                .transition(Self.stateTransition)
        } else {
            resolvingCentre
                .transition(Self.stateTransition)
        }
    }

    /// Placeholder → card or dial cross-fade rather than swap.
    private static var stateTransition: AnyTransition { .opacity.combined(with: .scale(scale: 0.96)) }

    private var resolvingCentre: some View {
        Circle()
            .fill(AppColor.surfaceSecondary.opacity(0.6))
            .frame(width: 120, height: 120)
            .shimmer()
            .accessibilityHidden(true)
    }

    /// The number and its unit, alone in the arc so they sit on its
    /// optical centre. Sign-tinted so "younger" / "older" reads in the
    /// first glance.
    private func unlockedCentre(estimate: BiologicalAgeEngine.Estimate) -> some View {
        let shown = displayedAge ?? estimate.biologicalAge
        return VStack(spacing: Spacing.xxs) {
            Text(BioAgeFormat.age(shown))
                .font(AppFont.scaled(56, weight: .light, relativeTo: .largeTitle, in: centreTypeSize))
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
        }
    }

    /// The page's one action: what moved the number and how it's built.
    private var explainButton: some View {
        Button(action: onExplainTapped) {
            Text("Why this number")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.accentPrimary)
                .minimumHitArea()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows what moved your Biological Age and how it's calculated")
    }

    // MARK: - Setup

    /// The dial's shape with nothing on it: the scale is left off, since
    /// there is no reading to place against it, and a dash holds the
    /// number's spot. Decorative — the line below says what's missing.
    private var ghostDial: some View {
        ZStack {
            BioAgeDial(
                chronologicalAge: chronologicalAge,
                bioAge: nil,
                size: Self.ghostDialSize,
                showsScale: false
            )
            Text(verbatim: "—")
                .font(AppFont.scaled(56, weight: .light, relativeTo: .largeTitle, in: centreTypeSize))
                .foregroundStyle(AppColor.textTertiary)
                .dynamicTypeSize(...Self.centreTypeSizeLimit)
        }
        .frame(height: Self.ghostDialSize)
        .padding(.bottom, -BioAgeDial.openBandHeight(size: Self.ghostDialSize))
        .accessibilityHidden(true)
    }

    /// Smaller than the live dial: a placeholder shouldn't push the
    /// biomarkers further down than the reading it stands in for.
    private static let ghostDialSize: CGFloat = 200
    private static let setupWidth: CGFloat = 320

    @ViewBuilder
    private var setupStep: some View {
        switch state {
        case .needsAge?:
            needsAgeStep
        case .building(let days, let requiredDays)?:
            buildingStep(days: days, requiredDays: requiredDays)
        case nil, .locked?, .unlocked(_)?:
            EmptyView()
        }
    }

    private var needsAgeStep: some View {
        let isUnderage = (1..<BioAgeStateResolver.minimumAge).contains(chronologicalAge)
        return VStack(spacing: Spacing.md) {
            setupText(isUnderage
                ? String(localized: "Biological Age is available for users 18+.")
                : String(localized: "Add your age in Profile to see your Biological Age."))
            // The one step between the user and the estimate, one tap
            // away instead of a hunt through Profile.
            if !isUnderage, let onAddAge {
                GlassButton(title: "Open Profile", icon: "person.crop.circle", style: .primary) {
                    Haptics.impact(.light)
                    onAddAge()
                }
            }
        }
    }

    /// Health access first; once granted, days against the unlock day
    /// when more days will get there, otherwise the missing signals.
    @ViewBuilder
    private func buildingStep(days: Int, requiredDays: Int?) -> some View {
        if let onConnectHealth {
            VStack(spacing: Spacing.md) {
                setupText(String(localized: "Connect Apple Health so Atlas can read your heart rate, HRV and sleep."))
                GlassButton(title: "Connect Apple Health", icon: "heart.fill", style: .primary, action: onConnectHealth)
                    .accessibilityHint("Asks for read access to Apple Health")
            }
        } else {
            VStack(spacing: Spacing.sm) {
                setupText(String(localized: "Wear Apple Watch overnight. Atlas reads your heart rate, HRV and sleep."))
                // No data at all: a day count would only count zeros.
                if !noHealthData {
                    if let requiredDays {
                        GlassProgressBar(progress: Self.buildingProgress(days: days, requiredDays: requiredDays))
                        Text("\(min(days, requiredDays)) of \(requiredDays) days of data collected")
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.textSecondary)
                    } else {
                        setupText(String(localized: "A few more signals will unlock your estimate."))
                    }
                }
                // Connected but still no number: the one step left is
                // making sure Atlas can read the data.
                GlassButton(title: "Check Health access", icon: "heart.text.square", style: .secondary, action: openHealthSettings)
                    .padding(.top, Spacing.xs)
                    .accessibilityHint("Opens Settings, where Atlas's Apple Health access is set")
            }
        }
    }

    private func openHealthSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        Haptics.impact(.light)
        openURL(url)
    }

    private func setupText(_ text: String) -> some View {
        Text(text)
            .font(AppFont.subheadline)
            .foregroundStyle(AppColor.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Share of the unlock day reached; when only signals are missing,
    /// the share of the full confidence window instead.
    static func buildingProgress(days: Int, requiredDays: Int?) -> Double {
        let target = max(1, requiredDays ?? BiologicalAgeEngine.windowDays)
        return min(1, Double(max(0, days)) / Double(target))
    }

    /// Below the dial: the delta against chronological age, what it was
    /// read against and how sure it is, then the way into the detail.
    private func unlockedSummary(estimate: BiologicalAgeEngine.Estimate) -> some View {
        VStack(spacing: Spacing.sm) {
            deltaBadge(for: estimate)
            Text(contextLine(for: estimate))
                .font(AppFont.scaled(13, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
            explainButton
        }
    }

    private func contextLine(for estimate: BiologicalAgeEngine.Estimate) -> String {
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

    private func deltaBadge(for estimate: BiologicalAgeEngine.Estimate) -> some View {
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
                .font(AppFont.scaled(11, weight: .semibold))
                .symbolEffect(.bounce, value: hasPlayedReveal && !reduceMotion)
                .accessibilityHidden(true)
            Text(label)
                .font(AppFont.scaled(13, weight: .semibold))
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
    private func tint(for estimate: BiologicalAgeEngine.Estimate) -> Color {
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
            displayedAge = Double(chronologicalAge) - BiologicalAgeEngine.maxDriftYears
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

#Preview("Needs age") {
    ZStack {
        PageBackdrop().ignoresSafeArea()
        BioAgeHeroSection(
            state: .needsAge,
            chronologicalAge: 26,
            onAddAge: {}
        )
        .padding(Spacing.screenPadding)
    }
}

#Preview("Building (4 of 15 days)") {
    ZStack {
        PageBackdrop().ignoresSafeArea()
        BioAgeHeroSection(
            state: .building(days: 4, requiredDays: 15),
            chronologicalAge: 26
        )
        .padding(Spacing.screenPadding)
    }
}

#Preview("Health not connected") {
    ZStack {
        PageBackdrop().ignoresSafeArea()
        BioAgeHeroSection(
            state: .building(days: 0, requiredDays: 15),
            chronologicalAge: 26,
            onConnectHealth: {}
        )
        .padding(Spacing.screenPadding)
    }
}

#Preview("Unlocked") {
    ZStack {
        PageBackdrop().ignoresSafeArea()
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
