import SwiftUI
import StoreKit
#if canImport(UIKit)
import UIKit
#endif

/// Conversion-optimized paywall surfaced at the end of onboarding. The
/// user picks Yearly (anchored as best value with savings vs 12× monthly)
/// or Monthly (with the 3-day free trial); the CTA delegates to
/// `StoreService.purchase(_:)` which calls `Product.purchase()` and lets
/// Apple present the intro-offer sheet or charge immediately as appropriate.
struct TrialOfferView: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var storeService = StoreService.shared
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var sparklePhase = 0.0
    @State private var ctaPulse = false
    @State private var didReveal = false
    /// Length of the soft urgency window. Long enough to read the screen
    /// without feeling like a scam, short enough to nudge a decision now
    /// rather than "later" (which converts far worse). The countdown's
    /// drain bar divides by this, so the two cannot drift apart.
    private static let offerWindow: TimeInterval = 10 * 60
    /// Deadline for the welcome offer, set once on first render so it counts
    /// down from when the user actually lands on the paywall.
    @State private var offerDeadline = Date().addingTimeInterval(TrialOfferView.offerWindow)
    /// Selected billing cadence. Initialised to `.annual` then re-assigned
    /// from `OnboardingExperiment.variant(for: .paywallTierOrder)` inside
    /// the view's `.task` modifier — the experiment service is
    /// `@MainActor`-isolated and calling it from a `@State` default
    /// initializer is a Swift 6 concurrency violation (audit H1).
    @State private var selectedTier: Tier = .annual
    /// Tier display order, written once on view appear from the same
    /// experiment assignment. Until the task runs, the view renders
    /// the default (annual-first); the task assigns synchronously on
    /// MainActor so the "blink" is invisible to the user.
    @State private var orderedTiers: [Tier] = [.annual, .monthly]

    enum Tier: String, CaseIterable, Identifiable {
        case annual, monthly
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .annual:  return "Yearly"
            case .monthly: return "Monthly"
            }
        }
    }

    private var monthlyPrice: String {
        storeService.monthlyProduct?.displayPrice ?? "$9.99"
    }

    private var annualPrice: String {
        storeService.annualProduct?.displayPrice ?? "$49.99"
    }

    /// Per-month equivalent of the annual plan, formatted with the
    /// product's locale-aware price style. Falls back to a hard-coded
    /// "$4.17" so the UI is never empty before products load.
    private var annualPerMonthPrice: String {
        guard let annual = storeService.annualProduct, annual.price > 0 else {
            return "$4.17"
        }
        let perMonth = annual.price / 12
        return perMonth.formatted(annual.priceFormatStyle)
    }

    /// Savings percent of annual vs 12× monthly. Returns nil while
    /// products are loading or when annual isn't actually cheaper.
    private var annualSavingsPercent: Int? {
        guard let annual = storeService.annualProduct,
              let monthly = storeService.monthlyProduct,
              annual.price > 0, monthly.price > 0
        else { return nil }
        let yearAtMonthly = monthly.price * 12
        guard yearAtMonthly > annual.price else { return nil }
        let saved = (yearAtMonthly - annual.price) / yearAtMonthly
        return Int((Double(truncating: saved as NSNumber) * 100).rounded())
    }

    /// Trial length in days. Must convert through the intro offer's
    /// `period.unit` — Apple may configure a 1-week trial as
    /// `(value: 1, unit: .week)` rather than `(value: 7, unit: .day)`,
    /// and the legacy `period.value * periodCount` math returned `1` in
    /// that case (audit code-review #7). Falls back to 3 when products
    /// haven't loaded yet so the headline reads sensibly during the
    /// brief StoreKit warm-up.
    private var trialDays: Int {
        guard let intro = storeService.monthlyProduct?.subscription?.introductoryOffer,
              intro.paymentMode == .freeTrial
        else { return 3 }
        let count = intro.period.value * intro.periodCount
        switch intro.period.unit {
        case .day:   return count
        case .week:  return count * 7
        case .month: return count * 30
        case .year:  return count * 365
        @unknown default: return count
        }
    }

    var body: some View {
        ZStack {
            sparkleField

            ScrollView(showsIndicators: false) {
                VStack(spacing: Spacing.lg) {
                    Spacer(minLength: Spacing.lg)

                    heroBadge
                    headline
                    countdownBanner
                    benefitsCard
                    socialProof
                    tierPicker

                    Spacer(minLength: Spacing.md)
                }
                .padding(.horizontal, Spacing.screenPadding)
            }
            .scrollBounceBehavior(.basedOnSize)
            // `pinnedFooter` reserves the footer's space *and* lands an
            // opaque backdrop under it. The previous hand-rolled version
            // opened at `.opacity(0)`, so it was fully transparent exactly
            // where the CTA sits: the tier cards and the ratings row showed
            // straight through and collided with the button and the legal
            // copy. The fade now completes inside the top padding, above the
            // button — a soft edge where content passes under, solid ground
            // everywhere text is drawn.
            .pinnedFooter {
                footer
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.md)
            }
        }
        .task {
            // Resolve the A/B experiment assignment from inside the
            // MainActor-isolated task — calling
            // OnboardingExperiment.variant from a `@State` default
            // initializer would violate Swift 6 actor isolation.
            // resolve(for:) returns the variant + an isFresh flag so
            // the funnel event fires exactly once per install rather
            // than from inside the experiment service (which would
            // make it depend on the funnel tracker).
            let resolution = OnboardingExperiment.resolve(for: .paywallTierOrder)
            if resolution.isFresh {
                OnboardingFunnelTracker.recordEvent(
                    OnboardingExperiment.funnelEventName(
                        for: .paywallTierOrder,
                        variant: resolution.variant
                    )
                )
            }
            switch resolution.variant {
            case .control:
                orderedTiers = [.annual, .monthly]
                selectedTier = .annual
            case .variantA:
                orderedTiers = [.monthly, .annual]
                selectedTier = .monthly
            }

            await storeService.loadProducts()
            withAnimation(AppAnimation.springBouncy) { didReveal = true }
            if !reduceMotion {
                withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                    sparklePhase = 1
                }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    ctaPulse = true
                }
            }
            Haptics.success()
        }
    }

    // MARK: - Hero

    private var heroBadge: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .strokeBorder(AppColor.accentPrimary.opacity(0.35), lineWidth: 1)
                    .frame(width: 130, height: 130)
                    .scaleEffect(didReveal ? 1.0 + CGFloat(ring) * 0.18 : 0.6)
                    .opacity(didReveal ? 0.55 - Double(ring) * 0.15 : 0)
            }

            // The app's own mark, not `gift.fill`. This is the screen that
            // asks for money — a stock SF Symbol here says "generic upsell",
            // while the logo the user has been looking at since the welcome
            // screen says "the thing you have been setting up". HeroLogo
            // already renders it as the brand disc and respects
            // reduce-motion, so the paywall uses the same treatment the
            // rest of onboarding does rather than inventing a parallel one.
            HeroLogo(size: 96)
                .scaleEffect(didReveal ? 1 : 0.4)
                .opacity(didReveal ? 1 : 0)
        }
        .frame(height: 140)
    }

    /// The headline follows `selectedTier`, and that is the whole point of it.
    ///
    /// It used to be hard-coded to the monthly pitch — "3 Days Free", "Atlas
    /// Pro Monthly", "Then $9.99/month" — while `.annual` is what loads
    /// selected and what the CTA underneath says it will start. So the only
    /// price above the fold was for a plan the button was not going to buy,
    /// and the actual amount lived in the tier card, below the fold, invisible
    /// at rest. A paywall you have to scroll to find the price on converts
    /// worse, and one that shows the *wrong* price converts worse still.
    private var headlineEyebrow: String {
        switch selectedTier {
        case .annual:  return "YOUR WELCOME OFFER"
        case .monthly: return "YOUR WELCOME GIFT"
        }
    }

    private var headlineHero: String {
        switch selectedTier {
        case .annual:  return annualPrice
        case .monthly: return "\(trialDays) Days Free"
        }
    }

    private var headlinePlan: String {
        switch selectedTier {
        case .annual:  return "Atlas Pro Yearly"
        case .monthly: return "Atlas Pro Monthly"
        }
    }

    private var headlineSupport: String {
        switch selectedTier {
        case .annual:
            guard let saved = annualSavingsPercent else {
                return "\(annualPerMonthPrice)/month — cancel anytime"
            }
            return "\(annualPerMonthPrice)/month — save \(saved)%"
        case .monthly:
            return "Then \(monthlyPrice)/month — cancel anytime"
        }
    }

    private var headline: some View {
        VStack(spacing: Spacing.xs) {
            Text(headlineEyebrow)
                .font(AppFont.scaled(11, weight: .heavy))
                .tracking(2)
                .foregroundStyle(AppColor.textSecondary)

            Text(headlineHero)
                .font(AppFont.scaled(44, weight: .heavy, design: .rounded, relativeTo: .largeTitle))
                .foregroundStyle(AppColor.textPrimary)
                .contentTransition(.numericText())

            Text(headlinePlan)
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)

            Text(headlineSupport)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
        }
        .multilineTextAlignment(.center)
        .opacity(didReveal ? 1 : 0)
        .offset(y: didReveal ? 0 : 12)
        .animation(AppAnimation.springSnappy, value: selectedTier)
    }

    // MARK: - Benefits

    private var benefitsCard: some View {
        GlassCard(tinted: true) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(Array(benefits.enumerated()), id: \.offset) { index, benefit in
                    benefitRow(icon: benefit.0, title: benefit.1, index: index)
                }
            }
        }
        .opacity(didReveal ? 1 : 0)
        .offset(y: didReveal ? 0 : 16)
    }

    /// Outcomes, not features. The previous list named the machinery —
    /// "AI photo + barcode meal scanner", "Cloud sync across all your
    /// devices" — which tells someone what they are buying but not what
    /// changes for them. Each line now leads with the result and keeps the
    /// mechanism as the short half, so the column scans as a list of things
    /// that get better.
    ///
    /// Nothing here promises an outcome the app does not measure: every
    /// claim maps to a surface that exists (auto-progression, the scanner,
    /// Performance Age, the cited-research chat, CloudKit sync).
    private let benefits: [(String, LocalizedStringKey)] = [
        ("figure.strengthtraining.traditional", "Lift more every week — plans that progress you automatically"),
        ("camera.viewfinder", "Log a meal in one photo — no weighing, no searching"),
        ("heart.text.square.fill", "Know before you train — recovery, HRV and Performance Age"),
        ("brain.head.profile.fill", "Ask anything, get cited research — not guesswork"),
        ("icloud.fill", "Never lose a session — synced across every device"),
    ]

    // MARK: - Urgency countdown

    /// Live "offer ends in mm:ss" banner. Drives conversion by giving the
    /// decision a deadline. `TimelineView` re-renders every second without
    /// any timer plumbing; once the window elapses it flips to a calmer
    /// "best value — today only" line rather than showing 00:00.
    /// A deadline has to look like one. This was a thin capsule with the clock
    /// set at 16pt inline with its own label — the same visual weight as a
    /// filter chip, which is to say none. Nothing about it read as time
    /// running out, so the urgency it was there to create did not land.
    ///
    /// It is now a card: the digits get display size and their own line, and
    /// the window drains visibly underneath. The bar is what makes it read as
    /// a deadline rather than a number that happens to change — you can see
    /// how much is left without reading anything.
    private var countdownBanner: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            countdownCard(remaining: max(0, offerDeadline.timeIntervalSince(context.date)))
        }
        .opacity(didReveal ? 1 : 0)
        .offset(y: didReveal ? 0 : 10)
        .animation(AppAnimation.springSmooth.delay(0.1), value: didReveal)
    }

    /// Split out of the `TimelineView` closure rather than written inline.
    /// Inline, the closure was large enough that one ambiguity inside it —
    /// an `accessibilityLabel` ternary the compiler could not resolve between
    /// the `LocalizedStringKey` and `StringProtocol` overloads — surfaced as
    /// "generic parameter 'Content' could not be inferred" on the
    /// `TimelineView` line, pointing nowhere near the actual problem.
    @ViewBuilder
    private func countdownCard(remaining: TimeInterval) -> some View {
        VStack(spacing: Spacing.sm) {
            if remaining > 0 {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "bolt.fill")
                        .font(AppFont.scaled(11, weight: .bold))
                    Text("WELCOME OFFER ENDS IN")
                        .font(AppFont.scaled(11, weight: .heavy))
                        .tracking(1.5)
                }
                .foregroundStyle(AppColor.warning)

                Text(timeString(remaining))
                    .font(AppFont.scaled(34, weight: .heavy, design: .rounded, relativeTo: .title))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.textPrimary)
                    .contentTransition(.numericText())

                countdownDrainBar(remaining: remaining)
            } else {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "bolt.fill")
                        .font(AppFont.scaled(13, weight: .bold))
                        .foregroundStyle(AppColor.warning)
                    Text("Best value — claim it today")
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.controlCornerRadius, style: .continuous)
                .fill(AppColor.warning.opacity(0.14))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.controlCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.warning.opacity(0.35), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(countdownAccessibilityLabel(remaining: remaining))
    }

    /// Drains left-to-right over the offer window. A Capsule rather than a
    /// ProgressView so the track reads as part of the card instead of a
    /// system control dropped into it.
    private func countdownDrainBar(remaining: TimeInterval) -> some View {
        GeometryReader { geo in
            Capsule()
                .fill(AppColor.warning)
                .frame(width: geo.size.width * remaining / Self.offerWindow)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 4)
        .background {
            Capsule().fill(AppColor.warning.opacity(0.18))
        }
        .animation(.linear(duration: 1), value: remaining)
    }

    /// A plain `String`, not a ternary at the call site — the two branches
    /// pick different `accessibilityLabel` overloads otherwise.
    private func countdownAccessibilityLabel(remaining: TimeInterval) -> String {
        remaining > 0
            ? "Welcome offer ends in \(timeString(remaining))"
            : "Best value — claim it today"
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Social proof

    /// Star rating + athlete count directly under the feature list. Trust
    /// signal right where the user is weighing the price — mirrors the
    /// welcome screen's `SocialProofPill` so the claim is consistent.
    private var socialProof: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(AppColor.achievement)
                }
            }
            Text("4.9")
                .font(AppFont.scaled(13, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
            Text("· Loved by 12k+ athletes")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
        }
        .opacity(didReveal ? 1 : 0)
        .animation(AppAnimation.springSmooth.delay(0.45), value: didReveal)
    }

    private func benefitRow(icon: String, title: LocalizedStringKey, index: Int) -> some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(AppColor.accentPrimary.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .symbolEffect(.bounce, value: didReveal)
            }
            Text(title)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(AppFont.scaled(16))
                .foregroundStyle(AppColor.accentPrimary)
        }
        .opacity(didReveal ? 1 : 0)
        .offset(x: didReveal ? 0 : -16)
        .animation(
            AppAnimation.springSmooth.delay(0.15 + Double(index) * 0.06),
            value: didReveal
        )
    }

    // MARK: - Tier picker

    private var tierPicker: some View {
        VStack(spacing: Spacing.sm) {
            // A/B: control = yearly first (savings anchor), variantA =
            // monthly first (trial framing prominent). Variant is sticky
            // per install via OnboardingExperiment so a user doesn't see
            // the order flip between launches.
            ForEach(orderedTiers, id: \.self) { tier in
                tierCard(tier)
            }
        }
        .opacity(didReveal ? 1 : 0)
        .offset(y: didReveal ? 0 : 16)
        .animation(AppAnimation.springSmooth.delay(0.35), value: didReveal)
    }

    private func tierCard(_ tier: Tier) -> some View {
        let isSelected = selectedTier == tier
        let isAnnual = tier == .annual
        return Button {
            Haptics.impact(.soft)
            withAnimation(AppAnimation.springSnappy) { selectedTier = tier }
        } label: {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? AppColor.accentPrimary : AppColor.glassBorder,
                            lineWidth: isSelected ? 6 : 1.2
                        )
                        .frame(width: 22, height: 22)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.xs) {
                        Text(tier.displayName)
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                        if isAnnual, let savings = annualSavingsPercent {
                            Text("SAVE \(savings)%")
                                .font(AppFont.scaled(11, weight: .heavy))
                                .tracking(0.6)
                                .foregroundStyle(AppColor.background)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(AppColor.accentLight)
                                )
                        }
                    }
                    Text(tierSubtitle(for: tier))
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(tierPrimaryPrice(for: tier))
                        .font(AppFont.scaled(16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("/mo")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(isSelected
                          ? AppColor.accentPrimary.opacity(0.14)
                          : AppColor.surfaceSecondary.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .stroke(
                        isSelected ? AppColor.accentPrimary : AppColor.glassBorder,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isAnnual {
                    Text("MOST POPULAR")
                        .font(AppFont.scaled(8, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(AppColor.background)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(AppColor.accentPrimary))
                        .offset(x: -Spacing.sm, y: -9)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func tierPrimaryPrice(for tier: Tier) -> String {
        switch tier {
        case .annual:  return annualPerMonthPrice
        case .monthly: return monthlyPrice
        }
    }

    private func tierSubtitle(for tier: Tier) -> String {
        switch tier {
        case .annual:
            return "Billed \(annualPrice)/yr"
        case .monthly:
            return "\(trialDays) days free, then \(monthlyPrice)/mo"
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: Spacing.sm) {
            if let errorMessage {
                Text(errorMessage)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.destructive)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            Button(action: startTrial) {
                HStack(spacing: Spacing.sm) {
                    if isPurchasing {
                        ProgressView()
                            .tint(AppColor.textPrimary)
                    } else {
                        Image(systemName: "sparkles")
                            .font(AppFont.scaled(16, weight: .bold))
                        Text(ctaTitle)
                            .font(AppFont.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md + 2)
                .padding(.horizontal, Spacing.xl)
                .foregroundStyle(AppColor.onAccent)
                .background {
                    Capsule()
                        .fill(AppColor.accentFill)
                        .overlay(Capsule().strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5))
                }
                .scaleEffect(ctaPulse && !isPurchasing ? 1.02 : 1.0)
                .shadow(color: AppColor.accentPrimary.opacity(0.4), radius: ctaPulse ? 18 : 8, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing)
            .accessibilityLabel(ctaTitle)

            HStack(spacing: Spacing.xs) {
                Image(systemName: "checkmark.shield.fill")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                Text(reassuranceCopy)
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }

            Button(action: declineTrial) {
                Text("Maybe later")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .padding(.vertical, Spacing.xs)
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing)

            Text(legalCopy)
                .font(AppFont.scaled(11))
                .foregroundStyle(AppColor.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.md)

            HStack(spacing: Spacing.md) {
                Link("Terms of Use", destination: URL.staticHTTPS("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"))
                Text("·").foregroundStyle(AppColor.textTertiary)
                Link("Privacy Policy", destination: URL.staticHTTPS("https://wrexist.github.io/Peptide-ai/privacy.html"))
            }
            .font(AppFont.scaled(11))
            .foregroundStyle(AppColor.accentLight)
        }
    }

    // MARK: - Sparkles

    private var sparkleField: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<14, id: \.self) { index in
                    sparkle(index: index, in: proxy.size)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func sparkle(index: Int, in size: CGSize) -> some View {
        let seed = Double(index)
        let xRatio = (sin(seed * 1.7) + 1) / 2
        let yBase = (cos(seed * 2.3) + 1) / 2
        let drift = (sparklePhase + seed / 14).truncatingRemainder(dividingBy: 1)
        let y = (yBase + drift).truncatingRemainder(dividingBy: 1)
        let scale = 0.5 + (sin(seed) + 1) / 2 * 0.6
        return Image(systemName: "sparkle")
            .font(AppFont.scaled(11))
            .foregroundStyle(AppColor.accentLight.opacity(0.35))
            .scaleEffect(scale)
            .position(x: size.width * xRatio, y: size.height * (1 - y))
    }

    private var productForSelectedTier: Product? {
        switch selectedTier {
        case .annual:  return storeService.annualProduct
        case .monthly: return storeService.monthlyProduct
        }
    }

    // MARK: - CTA / legal copy

    private var ctaTitle: String {
        switch selectedTier {
        case .annual:
            return "Start Yearly Plan"
        case .monthly:
            return "Start My \(trialDays)-Day Free Trial"
        }
    }

    /// Friction-reducing line under the CTA. Accurate per tier — only
    /// the monthly trial means "no charge today"; the annual plan bills
    /// immediately, so it leans on the cancel-anytime guarantee.
    private var reassuranceCopy: String {
        switch selectedTier {
        case .annual:  return "Cancel anytime · Secured by the App Store"
        case .monthly: return "No charge today · Cancel anytime"
        }
    }

    private var legalCopy: String {
        switch selectedTier {
        case .annual:
            return "Billed \(annualPrice) per year for the Atlas Pro Yearly subscription. Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in Settings → Apple ID → Subscriptions."
        case .monthly:
            return "No charge for \(trialDays) days. Then \(monthlyPrice)/month for the Atlas Pro Monthly subscription. Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in Settings → Apple ID → Subscriptions."
        }
    }

    // MARK: - Actions

    private func startTrial() {
        guard !isPurchasing else { return }
        Haptics.impact(.medium)
        errorMessage = nil
        guard let product = productForSelectedTier else {
            withAnimation(AppAnimation.fadeIn) { errorMessage = "Plan still loading. Try again in a moment." }
            return
        }
        isPurchasing = true
        Task {
            // Reset isPurchasing unconditionally in a defer so a userCancelled
            // or pending purchase doesn't leave the CTA stuck (audit C-1).
            // purchaseWithOutcome distinguishes success / cancel /
            // pending so we can surface "Ask to Buy" as a real
            // outcome instead of letting the tap look like a no-op
            // (audit Library P0.5).
            defer { isPurchasing = false }
            do {
                let outcome = try await storeService.purchaseWithOutcome(product)
                switch outcome {
                case .success:
                    Haptics.success()
                    onAccept()
                case .pending:
                    withAnimation(AppAnimation.fadeIn) {
                        errorMessage = "Purchase pending approval. We'll unlock Pro as soon as it's approved."
                    }
                case .userCancelled:
                    break // no UI noise on explicit cancel
                }
            } catch {
                withAnimation(AppAnimation.fadeIn) { errorMessage = "Couldn't complete the purchase. Please try again." }
            }
        }
    }

    private func declineTrial() {
        Haptics.impact(.light)
        onDecline()
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        TrialOfferView(onAccept: {}, onDecline: {})
    }
    .preferredColorScheme(.dark)
}
