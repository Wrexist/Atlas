import SwiftUI
import StoreKit
#if canImport(UIKit)
import UIKit
#endif

/// Conversion-optimized paywall surfaced at the end of onboarding. The
/// user picks Yearly (anchored as best value with savings vs 12× monthly)
/// or Monthly — both carry the 7-day intro offer while this Apple ID is
/// still trial-eligible; the CTA delegates to
/// `StoreService.purchase(_:)` which calls `Product.purchase()` and lets
/// Apple present the intro-offer sheet or charge immediately as appropriate.
struct TrialOfferView: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var storeService = StoreService.shared
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var notice: PurchaseNotice?
    /// Starts `true` so the first frame shimmers rather than showing the
    /// "plans couldn't load" row while the initial fetch is in flight.
    @State private var isLoadingProducts = true
    /// The experiment's default tier applies once. `.task` re-fires each
    /// time the onboarding page reappears, and re-applying it would undo
    /// the plan the user picked before swiping back.
    @State private var didApplyVariantDefault = false
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
            case .annual:  return String(localized: "Yearly")
            case .monthly: return String(localized: "Monthly")
            }
        }
    }

    /// Shown in place of any price until StoreKit returns the storefront's
    /// own. A hard-coded "$9.99" fallback used to flow into the headline and
    /// the legal copy on every non-US storefront during the load window —
    /// a price in the wrong currency on a purchase screen.
    private static let pricePlaceholder = "—"

    /// Both plans loaded. Until then the CTA stays disabled and the legal
    /// copy waits, so nothing on screen quotes a price StoreKit hasn't given.
    private var arePricesLoaded: Bool {
        storeService.monthlyProduct != nil && storeService.annualProduct != nil
    }

    /// The fetch finished without both plans (offline, storefront hiccup):
    /// stop shimmering and offer a retry instead of loading forever.
    private var arePlansUnavailable: Bool {
        !isLoadingProducts && !arePricesLoaded
    }

    private var monthlyPrice: String {
        storeService.monthlyProduct?.displayPrice ?? Self.pricePlaceholder
    }

    private var annualPrice: String {
        storeService.annualProduct?.displayPrice ?? Self.pricePlaceholder
    }

    /// Per-month equivalent of the annual plan, formatted with the
    /// product's locale-aware price style.
    private var annualPerMonthPrice: String {
        guard let annual = storeService.annualProduct, annual.price > 0 else {
            return Self.pricePlaceholder
        }
        let perMonth = annual.price / 12
        return perMonth.formatted(annual.priceFormatStyle)
    }

    /// Savings percent of annual vs 12× monthly. Returns nil while
    /// products are loading or when annual isn't actually cheaper.
    /// Sub-5% savings are suppressed to match `PaywallView` — the two
    /// screens previously disagreed ("SAVE 1%" here, nothing there),
    /// and a single-digit badge reads as a gimmick, not a saving.
    private var annualSavingsPercent: Int? {
        guard let annual = storeService.annualProduct,
              let monthly = storeService.monthlyProduct,
              annual.price > 0, monthly.price > 0
        else { return nil }
        let yearAtMonthly = monthly.price * 12
        guard yearAtMonthly > annual.price else { return nil }
        let saved = (yearAtMonthly - annual.price) / yearAtMonthly
        let percent = Int((Double(truncating: saved as NSNumber) * 100).rounded())
        return percent >= 5 ? percent : nil
    }

    /// Trial length in days for the selected tier, or `nil` when this Apple
    /// ID can no longer redeem it. Both plans ship a free trial, so the
    /// headline, the CTA and the legal copy all have to ask per tier rather
    /// than assume the trial belongs to monthly.
    ///
    /// Eligibility-gated on purpose: monthly and annual share a subscription
    /// group, so once either trial is redeemed neither is free, and copy that
    /// still says "free" would be charging someone who was promised zero.
    private var trialDays: Int? { trialDays(for: selectedTier) }

    /// Redeemable trial length for a specific tier. Per-tier rather than
    /// per-selection because the tier cards each state their own offer — a
    /// row that borrowed the selected tier's trial length would advertise
    /// the annual trial on the monthly card.
    private func trialDays(for tier: Tier) -> Int? {
        guard let product = product(for: tier) else { return nil }
        return storeService.redeemableTrialDays(for: product)
    }

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: Spacing.lg) {
                    Spacer(minLength: Spacing.lg)

                    heroBadge
                    headline
                    tierPicker
                    valueBanner
                    benefitsCard
                    socialProof

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
            case .control:  orderedTiers = [.annual, .monthly]
            case .variantA: orderedTiers = [.monthly, .annual]
            }
            if !didApplyVariantDefault {
                selectedTier = orderedTiers[0]
                didApplyVariantDefault = true
            }

            await loadPlans()
        }
    }

    // MARK: - Hero

    private var heroBadge: some View {
        MilestoneArtwork(size: 80, style: .emblem)
            .frame(maxWidth: .infinity)
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
        guard let days = trialDays else { return String(localized: "YOUR WELCOME OFFER") }
        return String(localized: "YOUR \(days)-DAY FREE TRIAL")
    }

    private var headlineHero: String {
        if let days = trialDays { return String(localized: "\(days) days free") }
        guard arePricesLoaded else { return "Atlas Pro" }
        return selectedTier == .annual ? annualPrice : monthlyPrice
    }

    private var headlinePlan: String { planName(for: selectedTier) }

    private var headlineSupport: String {
        guard arePricesLoaded else { return plansStatus }
        // "Then …" only reads correctly when something comes first. Once the
        // trial is spent it's just the price, so the lead-in has to go.
        let lead = trialDays == nil ? "" : String(localized: "Then ")
        switch selectedTier {
        case .annual:
            // Guideline 3.1.2(c): the billed amount leads; the per-month
            // equivalent is the secondary figure.
            let billed = String(localized: "\(lead)\(annualPrice)/year · \(annualPerMonthPrice)/mo")
            guard let saved = annualSavingsPercent else { return billed }
            return String(localized: "\(billed) — save \(saved)%")
        case .monthly:
            return String(localized: "\(lead)\(monthlyPrice)/month — cancel anytime")
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
        // Until StoreKit answers, the eyebrow can't know whether a trial
        // is redeemable and the prices read "—"; show the shape of the
        // headline instead of copy that flips a beat later.
        .loadingPlaceholder(isLoadingProducts && !arePricesLoaded)
        .appAnimation(AppAnimation.fadeIn, value: arePricesLoaded)
        .animation(AppAnimation.motionAware(AppAnimation.springSnappy, reduceMotion: reduceMotion), value: selectedTier)
    }

    // MARK: - Benefits

    private var benefitsCard: some View {
        GlassCard(tinted: true) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(benefits, id: \.0) { benefit in
                    benefitRow(icon: benefit.0, title: benefit.1)
                }
            }
        }
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
    /// Biological Age, the cited-research chat, CloudKit sync).
    private let benefits: [(String, LocalizedStringKey)] = [
        ("figure.strengthtraining.traditional", "Lift more every week — plans that progress you automatically"),
        ("camera.viewfinder", "Log a meal in one photo — no weighing, no searching"),
        ("heart.text.square.fill", "Know before you train — recovery, HRV and Biological Age"),
        ("brain.head.profile.fill", "Ask anything, get cited research — not guesswork"),
        ("icloud.fill", "Never lose a session — synced across every device"),
    ]

    // MARK: - Value banner

    /// Static value banner. This used to be a live 10-minute
    /// "WELCOME OFFER ENDS IN mm:ss" countdown with a draining bar — but
    /// nothing actually changed at 0:00: the price, the trial, and the
    /// products were identical before and after, which makes it exactly the
    /// misleading-urgency pattern App Review has been rejecting under
    /// Guidelines 2.3.1/3.1.2, and dishonest besides. If a real
    /// time-limited offer ever ships (a genuine promotional offer with a
    /// server/StoreKit-enforced expiry), a countdown can return — driven by
    /// that offer's actual deadline, never a synthetic one.
    private var valueBanner: some View {
        // "Free trial" only while this Apple ID can still redeem one —
        // same eligibility gate as the headline and the CTA. "Best value"
        // only describes annual, so Monthly gets the offer alone.
        let caption: String
        switch (selectedTier == .annual, trialDays != nil) {
        case (true, true):   caption = String(localized: "Best value — start with a free trial")
        case (true, false):  caption = String(localized: "Best value — full access, cancel anytime")
        case (false, true):  caption = String(localized: "Start with a free trial")
        case (false, false): caption = String(localized: "Full access, cancel anytime")
        }
        return HStack(spacing: Spacing.xs) {
            Image(systemName: "bolt.fill")
                .font(AppFont.scaled(13, weight: .bold))
                .foregroundStyle(AppColor.warning)
            Text(caption)
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
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
        .accessibilityLabel(caption)
    }

    // MARK: - Trust line

    /// Trust signal directly under the feature list, right where the user is
    /// weighing the price. Verifiable claims only — the previous fabricated
    /// "4.9 · 12k+ athletes" rating is gone (Guideline 2.3.1; no App Store
    /// source existed). Mirrors PaywallView's trust line so the story stays
    /// consistent between screens.
    private var socialProof: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "lock.shield.fill")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.accentPrimary)
            Text("Private by design — no ads, no tracking, cancel anytime")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Private by design. No ads, no tracking. Cancel anytime.")
    }

    private func benefitRow(icon: String, title: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(AppColor.accentPrimary.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
            }
            .accessibilityHidden(true)
            Text(title)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(AppFont.scaled(16))
                .foregroundStyle(AppColor.accentPrimary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Tier picker

    private var tierPicker: some View {
        VStack(spacing: Spacing.sm) {
            // A/B: control = yearly first (savings anchor), variantA =
            // monthly first (trial framing prominent). Variant is sticky
            // per install via OnboardingExperiment so a user doesn't see
            // the order flip between launches.
            if arePlansUnavailable {
                plansUnavailable
            } else {
                ForEach(orderedTiers, id: \.self) { tier in
                    tierCard(tier)
                }
            }
        }
    }

    /// Same recovery as `PaywallView.productsUnavailable`: without it a
    /// failed fetch left the cards shimmering and the CTA disabled for good.
    private var plansUnavailable: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "wifi.exclamationmark")
                .font(AppFont.scaled(20, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .accessibilityHidden(true)
            Text("Plans couldn't load")
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
            Text("Check your connection and try again.")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await loadPlans() }
            } label: {
                Text("Retry")
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.accentLight)
                    .padding(.horizontal, Spacing.lg)
                    .minimumHitArea()
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
        }
    }

    private func tierCard(_ tier: Tier) -> some View {
        let isSelected = selectedTier == tier
        let isAnnual = tier == .annual
        return Button {
            Haptics.selection()
            withAnimation(AppAnimation.motionAware(AppAnimation.springSnappy, reduceMotion: reduceMotion)) { selectedTier = tier }
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
                        if isAnnual {
                            // Inline, not offset above the card: the old
                            // floating badge collided with the card above
                            // when the A/B order put yearly second. "Best
                            // value" is what the savings maths supports;
                            // "most popular" was an unverified claim.
                            Text(annualSavingsPercent.map { String(localized: "BEST VALUE · SAVE \($0)%") } ?? String(localized: "BEST VALUE"))
                                .font(AppFont.badge)
                                .tracking(0.6)
                                .foregroundStyle(AppColor.onAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(AppColor.accentFill)
                                )
                        }
                    }
                    Text(tierSubtitle(for: tier))
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .loadingPlaceholder(!arePricesLoaded)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(tierPrimaryPrice(for: tier))
                        .font(AppFont.scaled(16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(tierPriceUnit(for: tier))
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
                }
                .loadingPlaceholder(!arePricesLoaded)
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
        }
        .buttonStyle(ScalePressStyle())
        .appAnimation(AppAnimation.fadeIn, value: arePricesLoaded)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// The billed amount per period — never the per-month equivalent of the
    /// annual plan, which Guideline 3.1.2(c) allows only as the secondary line.
    private func tierPrimaryPrice(for tier: Tier) -> String {
        switch tier {
        case .annual:  return annualPrice
        case .monthly: return monthlyPrice
        }
    }

    private func tierPriceUnit(for tier: Tier) -> String {
        switch tier {
        case .annual:  return "/yr"
        case .monthly: return "/mo"
        }
    }

    private func tierSubtitle(for tier: Tier) -> String {
        // "%lld days free" carries the plural variants, so a one-day
        // trial reads "1 day free" rather than "1 days free".
        let free = trialDays(for: tier).map { String(localized: "\($0) days free") }
        switch tier {
        case .annual:
            let perMonth = "\(annualPerMonthPrice)/mo"
            guard let free else { return String(localized: "Just \(perMonth)") }
            return String(localized: "\(free) · \(perMonth)")
        case .monthly:
            let billed = "\(monthlyPrice)/mo"
            guard let free else { return String(localized: "Billed \(billed)") }
            return String(localized: "\(free), then \(billed)")
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: Spacing.sm) {
            if let notice {
                Text(notice.message)
                    .font(AppFont.caption2)
                    .foregroundStyle(notice.color)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            Button(action: startTrial) {
                VStack(spacing: 2) {
                    if isPurchasing {
                        ProgressView()
                            .tint(AppColor.onAccent)
                    } else {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "sparkles")
                                .font(AppFont.scaled(16, weight: .bold))
                            Text(ctaTitle)
                                .font(AppFont.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        Text(ctaDetail)
                            .font(AppFont.scaled(11, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .opacity(0.85)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.vertical, Spacing.md + 2)
                .padding(.horizontal, Spacing.xl)
                .foregroundStyle(AppColor.onAccent)
                .background {
                    Capsule()
                        .fill(AppColor.accentFill)
                        .overlay(Capsule().strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5))
                }
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.97))
            .disabled(isPurchasing || isRestoring || !arePricesLoaded)
            .opacity(arePricesLoaded ? 1 : 0.5)
            .accessibilityLabel("\(ctaTitle). \(ctaDetail)")

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
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
                    .padding(.vertical, Spacing.xs)
                    .minimumHitArea()
            }
            .buttonStyle(.plain)
            // A restore that finishes after declining would call onAccept
            // on a page onboarding has already left.
            .disabled(isPurchasing || isRestoring)

            Text(legalCopy)
                .font(AppFont.scaled(11))
                .foregroundStyle(AppColor.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.md)

            HStack(spacing: Spacing.md) {
                Button(action: restore) {
                    Text("Restore Purchases").minimumHitArea()
                }
                .buttonStyle(.plain)
                .disabled(isPurchasing || isRestoring)
                Text("·").foregroundStyle(AppColor.textTertiary)
                Link(destination: URL.staticHTTPS("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")) {
                    Text("Terms of Use").minimumHitArea()
                }
                Text("·").foregroundStyle(AppColor.textTertiary)
                Link(destination: URL.staticHTTPS("https://wrexist.github.io/Atlas/privacy.html")) {
                    Text("Privacy Policy").minimumHitArea()
                }
            }
            .font(AppFont.scaled(11))
            .foregroundStyle(AppColor.accentLight)
        }
        // VoiceOver focus returns to the CTA after the purchase sheet
        // closes, so the notice has to be spoken to be noticed.
        .onChange(of: notice?.message) { _, message in
            guard let message else { return }
            AccessibilityNotification.Announcement(message).post()
        }
    }

    private var productForSelectedTier: Product? { product(for: selectedTier) }

    /// The App Store product's own name ("Atlas Pro Annual"), so the
    /// purchase surface names the subscription exactly as Guideline 3.1.2
    /// and App Store Connect do. The fallback covers the load window.
    private func planName(for tier: Tier) -> String {
        if let product = product(for: tier) { return product.displayName }
        switch tier {
        case .annual:  return "Atlas Pro Annual"
        case .monthly: return "Atlas Pro Monthly"
        }
    }

    private func product(for tier: Tier) -> Product? {
        switch tier {
        case .annual:  return storeService.annualProduct
        case .monthly: return storeService.monthlyProduct
        }
    }

    // MARK: - CTA / legal copy

    /// Top line of the CTA: what the tap gets you, never "Continue".
    private var ctaTitle: String {
        guard let days = trialDays else {
            return String(localized: "Get \(headlinePlan)")
        }
        return String(localized: "Start My \(days)-Day Free Trial")
    }

    /// Second line of the CTA: the charge, in the user's own currency. A
    /// trial button that doesn't say "\(zeroPriceToday) today" leaves the
    /// user to guess whether tapping it bills them, and the ones who guess
    /// wrong cancel within the hour.
    private var ctaDetail: String {
        guard arePricesLoaded else { return plansStatus }
        let price = selectedTier == .annual
            ? "\(annualPrice)/yr"
            : "\(monthlyPrice)/mo"
        guard trialDays != nil else { return String(localized: "\(price) · cancel anytime") }
        return String(localized: "\(zeroPriceToday) today, then \(price)")
    }

    /// A localised zero in the selected plan's currency — "$0.00", "0,00 kr".
    private var zeroPriceToday: String {
        guard let product = productForSelectedTier else { return Self.pricePlaceholder }
        return Decimal.zero.formatted(product.priceFormatStyle)
    }

    /// Friction-reducing line under the CTA. Gated on a *redeemable* trial,
    /// not on the tier: "no charge today" is a promise about this Apple ID,
    /// and it stops being true the moment the shared intro offer is spent.
    private var reassuranceCopy: String {
        guard trialDays != nil else { return String(localized: "Cancel anytime · Secured by the App Store") }
        return String(localized: "No charge today · Cancel anytime")
    }

    private var plansStatus: String {
        isLoadingProducts ? String(localized: "Loading plans…") : String(localized: "Plans unavailable")
    }

    /// Guideline 3.1.2 terms. Before StoreKit answers there is no price in
    /// the storefront's currency to quote, but the plan names, lengths and
    /// auto-renewal still have to be on the purchase surface.
    private var legalCopy: String {
        let renewal = String(localized: "Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in Settings → your name → Subscriptions.")
        guard arePricesLoaded else {
            return String(localized: "\(planName(for: .monthly)) (billed monthly) and \(planName(for: .annual)) (billed yearly) are auto-renewable subscriptions. \(renewal)")
        }
        let plan = selectedTier == .annual
            ? String(localized: "\(annualPrice) per year for the \(planName(for: .annual)) subscription")
            : String(localized: "\(monthlyPrice) per month for the \(planName(for: .monthly)) subscription")
        guard let days = trialDays else { return String(localized: "Billed \(plan). \(renewal)") }
        return String(localized: "No charge for \(days) days. Then \(plan). \(renewal)")
    }

    // MARK: - Actions

    private func startTrial() {
        guard !isPurchasing, !isRestoring else { return }
        Haptics.impact(.medium)
        notice = nil
        guard let product = productForSelectedTier else {
            AppAnimation.with(AppAnimation.fadeIn) { notice = .failed(String(localized: "Plan still loading. Try again in a moment.")) }
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
                    AppAnimation.with(AppAnimation.fadeIn) {
                        notice = .pending
                    }
                case .userCancelled:
                    break // no UI noise on explicit cancel
                }
            } catch {
                AppAnimation.with(AppAnimation.fadeIn) { notice = .failed(String(localized: "Couldn't complete the purchase. Please try again.")) }
            }
        }
    }

    /// Same restore path as `PaywallView`. A returning subscriber who
    /// restores leaves onboarding exactly as a fresh purchase would.
    private func restore() {
        guard !isRestoring, !isPurchasing else { return }
        notice = nil
        isRestoring = true
        Task {
            defer { isRestoring = false }
            do {
                guard try await storeService.restorePurchases() == .completed else { return }
                if storeService.isProUser {
                    Haptics.success()
                    onAccept()
                } else {
                    AppAnimation.with(AppAnimation.fadeIn) { notice = .nothingToRestore }
                }
            } catch {
                AppAnimation.with(AppAnimation.fadeIn) { notice = .failed(String(localized: "Restore failed. Check your internet connection and try again.")) }
            }
        }
    }

    private func loadPlans() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        await storeService.loadProducts()
    }

    private func declineTrial() {
        Haptics.impact(.light)
        onDecline()
    }
}

/// What the footer reports after a purchase or restore attempt. Only a
/// real failure is red — a pending Ask to Buy and an empty restore are
/// outcomes, not errors, matching `PaywallView`.
private enum PurchaseNotice {
    case failed(String)
    case pending
    case nothingToRestore

    var message: String {
        switch self {
        case .failed(let message): return message
        case .pending:             return String(localized: "Purchase pending approval. We'll unlock Pro as soon as it's approved.")
        case .nothingToRestore:    return String(localized: "No previous purchase found to restore.")
        }
    }

    var color: Color {
        switch self {
        case .failed:           return AppColor.destructive
        case .pending:          return AppColor.recap
        case .nothingToRestore: return AppColor.textSecondary
        }
    }
}

private extension View {
    /// Redacted, shimmering stand-in while StoreKit prices load; the
    /// real content once they arrive.
    @ViewBuilder
    func loadingPlaceholder(_ isLoading: Bool) -> some View {
        if isLoading {
            self.redacted(reason: .placeholder).shimmer()
        } else {
            self
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        TrialOfferView(onAccept: {}, onDecline: {})
    }
    .preferredColorScheme(.dark)
}
