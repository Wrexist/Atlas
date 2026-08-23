import SwiftUI
import StoreKit

/// Full-rebuild paywall presented from the upgrade entry points (Home,
/// Analytics, Protocols, PeptideDetail, ExportSection, ProBadge). The
/// onboarding `TrialOfferView` is intentionally separate — that lives
/// inside the onboarding TabView and renders without dismiss chrome.
///
/// Layout rule for this screen: the plan picker sits above the fold and the
/// CTA never scrolls. The previous version put the phone mockups (230pt) and
/// the feature list between the header and the prices, so on every iPhone the
/// buy button and the third plan were below the fold — the user had to scroll
/// to find out what they'd pay and scroll again to pay it. Prices now sit
/// directly under the offer headline and the button lives in a `pinnedFooter`,
/// so "decide" and "buy" are one gesture apart. The mockups and the longer
/// pitch moved below the prices, where they convince whoever keeps reading.
///
/// Constructor stays no-arg so the six existing call sites don't break;
/// callers also keep wrapping it in `.liquidGlassPresentation()` where
/// they want the system-glass sheet treatment.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var dataStore
    @State private var storeService = StoreService.shared

    @State private var selectedProductID: String?
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var errorMessage: String?
    @State private var isShowingDisclosure = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AppColor.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    header
                        .padding(.top, Spacing.xxxl)

                    offerHeadline

                    pricingCardsRow

                    socialProof

                    if let attribution = creatorAttribution {
                        creatorBanner(attribution)
                    }

                    trialTimeline

                    featureList

                    PaywallPhoneMockupRow()

                    reassuranceNote
                        .padding(.bottom, Spacing.sm)
                }
                .padding(.horizontal, Spacing.screenPadding)
            }
            .scrollBounceBehavior(.basedOnSize)
            // The CTA is the point of the screen, so it is pinned rather than
            // scrolled: `pinnedFooter` reserves its space *and* lays an opaque
            // backdrop under it, so the last card clears the button instead of
            // stopping behind it.
            .pinnedFooter {
                purchaseFooter
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.sm)
            }

            closeButton
                .padding(Spacing.lg)
        }
        .task {
            // Re-check entitlements first: a user who upgraded on another
            // device (or just restored) shouldn't be stranded on the paywall.
            await storeService.checkProAccess()
            if storeService.isProUser {
                dismiss()
                return
            }
            await storeService.loadProducts()
            if selectedProductID == nil {
                selectedProductID = storeService.annualProduct?.id
                    ?? storeService.monthlyProduct?.id
            }
        }
        .onChange(of: storeService.products.map(\.id)) { _, _ in
            if selectedProductID == nil {
                selectedProductID = storeService.annualProduct?.id
                    ?? storeService.monthlyProduct?.id
            }
        }
        .sheet(isPresented: $isShowingDisclosure) {
            disclosureSheet
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "flask.fill")
                .font(AppFont.scaled(20, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColor.accentLight, AppColor.accentPrimary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
                        .fill(AppColor.surfaceElevated)
                        .overlay {
                            RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
                                .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                        }
                }

            Text("Atlas Pro")
                .font(AppFont.scaled(26, weight: .bold, design: .rounded, relativeTo: .title1))
                .foregroundStyle(AppColor.textPrimary)
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(AppFont.scaled(13, weight: .bold))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(AppColor.surfaceSecondary.opacity(0.85))
                        .overlay {
                            Circle().strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                        }
                }
                .minimumHitArea()
        }
        .accessibilityLabel("Close")
    }

    // MARK: - Offer headline

    /// The one line that has to land before anything else: what it costs to
    /// say yes right now. It follows the selected plan, because a headline
    /// quoting a plan the button won't buy is worse than no headline.
    private var offerHeadline: some View {
        VStack(spacing: Spacing.xs) {
            Text(headlineEyebrow)
                .font(AppFont.scaled(11, weight: .heavy))
                .tracking(2)
                .foregroundStyle(AppColor.accentLight)

            Text(headlineHero)
                .font(AppFont.scaled(38, weight: .heavy, design: .rounded, relativeTo: .largeTitle))
                .foregroundStyle(AppColor.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(headlineSupport)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .animation(AppAnimation.springSnappy, value: selectedProductID)
    }

    private var headlineEyebrow: String {
        guard let product = selectedProduct else { return "EVERYTHING UNLOCKED" }
        if let days = storeService.redeemableTrialDays(for: product) {
            return "YOUR \(days)-DAY FREE TRIAL"
        }
        return product.type == .autoRenewable ? "EVERYTHING UNLOCKED" : "ONE PAYMENT, YOURS FOREVER"
    }

    private var headlineHero: String {
        guard let product = selectedProduct else { return "Atlas Pro" }
        if let days = storeService.redeemableTrialDays(for: product) {
            return "\(days) days free"
        }
        return product.displayPrice
    }

    private var headlineSupport: String {
        guard let product = selectedProduct else {
            return "Training, nutrition and recovery — one app, everything on."
        }
        guard product.type == .autoRenewable else {
            return "Pay once. No subscription, nothing to cancel."
        }
        let price = "\(product.displayPrice)\(periodSuffix(for: product))"
        if storeService.redeemableTrialDays(for: product) != nil {
            return "Then \(price). Cancel any time before it starts."
        }
        return "\(price) — cancel any time."
    }

    // MARK: - Social proof

    /// Rating + athlete count sit directly under the prices, where the user is
    /// weighing the number. Same claim as the welcome screen and the
    /// onboarding offer, so the story doesn't change between screens.
    private var socialProof: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(AppColor.achievement)
                }
            }
            Text("4.9")
                .font(AppFont.scaled(13, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
            Text("· Loved by 12k+ athletes")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rated 4.9 out of 5 by more than 12,000 athletes")
    }

    // MARK: - Trial timeline

    /// Walks the user through what actually happens across the trial. This is
    /// the objection the free-trial CTA raises and doesn't answer on its own —
    /// "when do I get charged, and can I get out?" — and answering it in
    /// three lines is worth more than another feature bullet.
    ///
    /// Every claim here is one the app can keep: no promise of a reminder
    /// email we don't send, and no cancel path other than the real one.
    @ViewBuilder
    private var trialTimeline: some View {
        if let product = selectedProduct,
           let days = storeService.redeemableTrialDays(for: product) {
            GlassCard(tinted: true) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("How your \(days) free days work")
                        .font(AppFont.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColor.textPrimary)

                    timelineRow(
                        icon: "lock.open.fill",
                        title: "Today",
                        detail: "Everything unlocks. You pay \(zeroPrice(for: product))."
                    )
                    timelineRow(
                        icon: "gearshape.fill",
                        title: "Day \(max(days - 1, 1))",
                        detail: "Still not for you? Cancel in Settings — one tap, keep the rest of the trial."
                    )
                    timelineRow(
                        icon: "checkmark.seal.fill",
                        title: "Day \(days)",
                        detail: "Your plan starts at \(product.displayPrice)\(periodSuffix(for: product))."
                    )
                }
            }
        }
    }

    private func timelineRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(AppColor.accentPrimary.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.scaled(13, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)
                Text(detail)
                    .font(AppFont.scaled(13))
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Feature list

    /// Outcomes, not machinery, and in the order the product is positioned:
    /// training, nutrition and recovery lead; protocol tracking stays for the
    /// advanced audience it was built for. The old list opened on "Unlimited
    /// peptide stacks & cycles" and never mentioned a workout or a meal, so
    /// the paywall was selling a different app than the one onboarding sold.
    private var featureList: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("What you get")
                .font(AppFont.scaled(13, weight: .heavy))
                .tracking(1)
                .foregroundStyle(AppColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(features, id: \.icon) { feature in
                featureRow(icon: feature.icon, title: feature.title)
            }
        }
    }

    private var features: [(icon: String, title: LocalizedStringKey)] {
        [
            ("figure.strengthtraining.traditional", "Lift more every week — plans that progress you automatically"),
            ("camera.viewfinder", "Log a meal in one photo — no weighing, no searching"),
            ("heart.text.square.fill", "Know before you train — recovery, HRV and Performance Age"),
            ("brain.head.profile.fill", "Ask anything, get cited research — not guesswork"),
            ("chart.line.uptrend.xyaxis", "Unlimited protocols — half-life, dosing and reconstitution"),
            ("icloud.fill", "Never lose a session — synced across iPhone, Watch and widgets"),
        ]
    }

    private func featureRow(icon: String, title: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(title)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    /// Closing line under the pitch. Restates the escape hatch after the
    /// user has read the whole page — the last thing between them and the
    /// button should be the reason not to worry about it.
    private var reassuranceNote: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.shield.fill")
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(AppColor.positive)
                .accessibilityHidden(true)
            Text("Cancel in two taps from Settings. Your logs, workouts and photos stay yours either way.")
                .font(AppFont.scaled(13))
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.6))
        }
    }

    /// Friendly error surface for purchase / restore failures. Replaces the
    /// previous raw `Text(errorMessage).foregroundStyle(.destructive)` line
    /// that just dumped the StoreKit description on the user with no path
    /// forward. Surfaces a localized headline + the underlying detail in
    /// muted secondary text, plus an explicit Restore Purchases shortcut so
    /// a transient StoreKit failure isn't a dead end.
    private func purchaseErrorBanner(message: String) -> some View {
        VStack(spacing: Spacing.xs) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.destructive)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Purchase didn't go through")
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(message)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: Spacing.sm) {
                if let product = selectedProduct {
                    Button("Try again") {
                        errorMessage = nil
                        Task { await purchase(product) }
                    }
                    .font(AppFont.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.accentLight)
                }

                Button("Restore purchases") {
                    errorMessage = nil
                    restore()
                }
                .font(AppFont.caption)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textSecondary)

                Spacer(minLength: 0)
            }
            .padding(.top, Spacing.xs)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.destructive.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.destructive.opacity(0.30), lineWidth: 0.5)
                }
        }
    }

    // MARK: - Creator banner

    private var creatorAttribution: CreatorAttribution? {
        guard let attribution = dataStore.profile.creatorAttribution,
              attribution.discountPercent > 0
        else { return nil }
        return attribution
    }

    /// Surfaces the attribution captured on the onboarding creator-code
    /// step. The discount percentage is stored on the profile but is
    /// NOT shown until the StoreKit / RevenueCat wiring actually applies
    /// it at checkout — claiming "X% off applied" while charging the
    /// full price is a trust regression we don't want users to spot
    /// post-purchase. Once the discount-on-purchase pipeline lands,
    /// switch the copy back to the "X% off applied — thanks to Y!"
    /// form via the `appliedDiscount` branch below.
    private func creatorBanner(_ attribution: CreatorAttribution) -> some View {
        let bannerGreen = AppColor.positive
        return HStack(spacing: Spacing.sm) {
            Image(systemName: "tag.fill")
                .font(AppFont.scaled(13, weight: .bold))
                .foregroundStyle(bannerGreen)
                .accessibilityHidden(true)              // Text alongside carries the meaning

            VStack(alignment: .leading, spacing: 2) {
                if let percent = appliedDiscount(for: attribution) {
                    Text("\(percent)% off applied — thanks to \(attribution.creatorName)!")
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Thanks for using \(attribution.creatorName)'s code")
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(bannerGreen.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(bannerGreen.opacity(0.45), lineWidth: 1)
                }
        }
    }

    /// Returns the discount percent only when the checkout pipeline can
    /// actually apply it. Today that's never — the StoreKit / RevenueCat
    /// integration is a deferred follow-up — so the banner falls back to
    /// attribution-only copy. When billing-side support lands, return
    /// `attribution.discountPercent` here (or a value StoreService can
    /// confirm is live) and the banner reads "X% off applied" again.
    private func appliedDiscount(for attribution: CreatorAttribution) -> Int? {
        // Intentionally returns nil until the discount is actually wired
        // into the purchase flow. Don't promise a discount we can't deliver.
        nil
    }

    // MARK: - Pricing cards

    private var pricingCardsRow: some View {
        // Three tiers — Yearly / Monthly / Lifetime — surfaced in
        // priority order with the savings anchor on Yearly. Lifetime
        // was previously loaded into StoreService.products but never
        // rendered on the paywall (audit Library P1.10).
        //
        // Stacked full-width rows rather than a 3-up grid: three tiers
        // side-by-side left each card ~100pt wide, which forced the
        // titles and localized prices to wrap mid-word ("Month\nly",
        // "$4.1\n7"). Rows give every plan room to breathe and read
        // as a single premium line — the layout RevenueCat / Whoop /
        // Bevel use for 3+ tiers.
        VStack(spacing: Spacing.sm) {
            if let annual = storeService.annualProduct {
                pricingRow(
                    product: annual,
                    title: "Yearly",
                    primaryPrice: perMonthEquivalent(for: annual) ?? annual.displayPrice,
                    primaryUnit: "/mo",
                    subtitle: yearlySubtitle(for: annual),
                    badge: savingsBadge
                )
            }
            if let monthly = storeService.monthlyProduct {
                pricingRow(
                    product: monthly,
                    title: "Monthly",
                    primaryPrice: monthly.displayPrice,
                    primaryUnit: "/mo",
                    subtitle: monthlySubtitle(for: monthly),
                    badge: nil
                )
            }
            if let lifetime = storeService.lifetimeProduct {
                // Lifetime is configured in App Store Connect but was
                // previously unreachable from the paywall, so revenue
                // from this product was effectively zero.
                pricingRow(
                    product: lifetime,
                    title: "Lifetime",
                    primaryPrice: lifetime.displayPrice,
                    primaryUnit: "once",
                    subtitle: "Pay once. Yours forever.",
                    // "BEST VALUE" is two words and it was pushing the
                    // title into a mid-word wrap ("Lifet / ime") on the
                    // narrowest phones. One word, same promise.
                    badge: "FOREVER"
                )
            }
        }
    }

    private func pricingRow(
        product: Product,
        title: LocalizedStringKey,
        primaryPrice: String,
        primaryUnit: String,
        subtitle: String,
        badge: String?
    ) -> some View {
        let isSelected = selectedProductID == product.id
        return Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                selectedProductID = product.id
            }
        } label: {
            HStack(spacing: Spacing.md) {
                radioMark(isSelected: isSelected)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.xs) {
                        Text(title)
                            .font(AppFont.scaled(16, weight: .bold))
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                            // Without `fixedSize` the badge alongside wins the
                            // width negotiation and the plan name — the one
                            // word that has to stay readable — wraps mid-word.
                            .fixedSize()
                        if let badge {
                            savingsPill(badge)
                        }
                    }

                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: Spacing.sm)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(primaryPrice)
                        .font(AppFont.scaled(20, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .monospacedDigit()
                    Text(primaryUnit)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .lineLimit(1)
                .fixedSize()
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(
                        isSelected
                            ? AppColor.accentPrimary.opacity(0.10)
                            : AppColor.surfaceSecondary.opacity(0.6)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(
                                isSelected ? AppColor.accentPrimary : AppColor.glassBorder,
                                lineWidth: isSelected ? 2 : 0.5
                            )
                    }
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.985))
    }

    private func radioMark(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? AppColor.accentPrimary : AppColor.glassBorder, lineWidth: isSelected ? 2 : 1)
                .frame(width: 24, height: 24)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(AppFont.scaled(11, weight: .bold))
                    .foregroundStyle(AppColor.accentPrimary)
            }
        }
        .contentTransition(.symbolEffect(.replace))
    }

    private func savingsPill(_ text: String) -> some View {
        Text(text)
            .font(AppFont.scaled(11, weight: .heavy))
            .foregroundStyle(AppColor.onAccent)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 2)
            .background {
                Capsule()
                    .fill(AppColor.accentFill)
            }
            .shadow(color: AppColor.accentGlow, radius: 6, y: 2)
    }

    /// "Billed €24.99/yr after 7 days free" when the intro offer is live;
    /// downgrades to plain "Billed €24.99/yr" once the user is no longer
    /// eligible (already redeemed an intro in this group).
    private func yearlySubtitle(for product: Product) -> String {
        let priceLine = "Billed \(product.displayPrice)/yr"
        if storeService.isEligibleForAnnualTrial,
           let trial = storeService.annualTrialDisplay {
            return "\(priceLine) after \(trial)"
        }
        return priceLine
    }

    private func monthlySubtitle(for product: Product) -> String {
        let priceLine = "Billed \(product.displayPrice)/mo"
        if storeService.isEligibleForMonthlyTrial,
           let trial = storeService.monthlyTrialDisplay {
            return "\(priceLine) after \(trial)"
        }
        return priceLine
    }

    /// Localised per-month string for the annual product. Uses StoreKit's
    /// `priceFormatStyle` so the currency symbol / grouping match the live
    /// product (€, kr, $, ¥ all render correctly).
    private func perMonthEquivalent(for annual: Product) -> String? {
        guard annual.price > 0 else { return nil }
        let monthly = annual.price / 12
        return monthly.formatted(annual.priceFormatStyle)
    }

    /// A localised zero in the product's own currency — "$0.00", "0,00 kr".
    /// Hard-coding "$0" would be wrong in every non-dollar storefront, and
    /// this string is the whole risk-reversal argument on the button.
    private func zeroPrice(for product: Product) -> String {
        Decimal.zero.formatted(product.priceFormatStyle)
    }

    /// "/yr", "/mo" — read from the product's own renewal period rather
    /// than its identifier, so a future weekly plan can't render as a
    /// yearly one.
    private func periodSuffix(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        switch period.unit {
        case .year:  return "/yr"
        case .month: return "/mo"
        case .week:  return "/wk"
        case .day:   return "/day"
        @unknown default: return ""
        }
    }

    /// Dynamic "X% OFF" pill computed from the live product prices. Falls
    /// back to nil when both products aren't loaded or annual isn't
    /// actually a discount versus 12× monthly.
    private var savingsBadge: String? {
        guard
            let monthly = storeService.monthlyProduct,
            let annual = storeService.annualProduct
        else { return nil }
        let yearAtMonthly = monthly.price * 12
        guard yearAtMonthly > annual.price else { return nil }
        let saved = (yearAtMonthly - annual.price) / yearAtMonthly
        // Round instead of truncating — a 0.085 fraction was rendering
        // as "8% OFF" before; a 0.07 fraction rendered as "7% OFF"
        // but a 0.999% (yes, occasionally happens with mismatched
        // currency rounding) silently became 0 and got filtered
        // (audit Library P1.9). Threshold raised to >= 5% so a
        // negligible saving doesn't ship a "5% OFF" badge that
        // makes the annual tier look weak.
        let percent = Int(((saved as NSDecimalNumber).doubleValue * 100).rounded())
        return percent >= 5 ? "SAVE \(percent)%" : nil
    }

    // MARK: - Pinned purchase footer

    private var purchaseFooter: some View {
        VStack(spacing: Spacing.sm) {
            if let errorMessage {
                purchaseErrorBanner(message: errorMessage)
            }

            primaryCTA

            autoRenewDisclosure

            footerLinks
        }
    }

    /// Two-line CTA: the action on top, the money underneath.
    ///
    /// The old label was "Continue", which is the weakest thing a paywall
    /// button can say — it names the gesture, not what the user gets, and it
    /// hides the one fact that removes the risk of tapping it. The top line
    /// now states the offer ("Start My 7-Day Free Trial") and the bottom line
    /// states the charge in the user's own currency ("$0.00 today, then
    /// $49.99/yr"). Both halves matter: trial-first framing is what lifts
    /// tap-through, and the explicit price is what stops the day-0 cancel
    /// from someone who tapped without knowing what came next.
    private var primaryCTA: some View {
        Button {
            guard let product = selectedProduct, !isPurchasing else { return }
            Task { await purchase(product) }
        } label: {
            VStack(spacing: 2) {
                if isPurchasing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppColor.onAccent)
                } else {
                    Text(ctaTitle)
                        .font(AppFont.scaled(16, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let ctaDetail {
                        Text(ctaDetail)
                            .font(AppFont.scaled(11, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .opacity(0.85)
                    }
                }
            }
            .foregroundStyle(AppColor.onAccent)
            .frame(maxWidth: .infinity, minHeight: 40)
            .padding(.vertical, Spacing.md)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColor.ctaGradientStart,
                                AppColor.ctaGradientEnd,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .shadow(color: AppColor.accentGlow, radius: 14, y: 6)
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.97))
        .disabled(selectedProduct == nil || isPurchasing)
        .opacity(selectedProduct == nil ? 0.5 : 1)
        .accessibilityLabel(ctaAccessibilityLabel)
    }

    private var ctaTitle: LocalizedStringKey {
        guard let product = selectedProduct else { return "Choose a plan" }
        guard product.type == .autoRenewable else { return "Get Lifetime Access" }
        if let days = storeService.redeemableTrialDays(for: product) {
            return "Start My \(days)-Day Free Trial"
        }
        return "Unlock Atlas Pro"
    }

    /// The money line. Never promises a free trial the user can't redeem —
    /// `redeemableTrialDays` is eligibility-gated, so a returning subscriber
    /// sees the real price on the button instead of a zero they won't get.
    private var ctaDetail: String? {
        guard let product = selectedProduct else { return nil }
        guard product.type == .autoRenewable else {
            return "\(product.displayPrice) once · no subscription"
        }
        let price = "\(product.displayPrice)\(periodSuffix(for: product))"
        if storeService.redeemableTrialDays(for: product) != nil {
            return "\(zeroPrice(for: product)) today, then \(price)"
        }
        return "\(price) · cancel any time"
    }

    private var ctaAccessibilityLabel: String {
        guard let product = selectedProduct else { return "Choose a plan" }
        let action: String
        if product.type != .autoRenewable {
            action = "Get lifetime access"
        } else if let days = storeService.redeemableTrialDays(for: product) {
            action = "Start my \(days) day free trial"
        } else {
            action = "Unlock Atlas Pro"
        }
        guard let ctaDetail else { return action }
        return "\(action). \(ctaDetail)"
    }

    // MARK: - Footer

    private var footerLinks: some View {
        HStack(spacing: Spacing.lg) {
            Button("Restore", action: restore)
                .disabled(isRestoring)

            Link("Terms of Use",
                 destination: URL.staticHTTPS("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"))

            Link("Privacy Policy",
                 destination: URL.staticHTTPS("https://wrexist.github.io/Peptide-ai/privacy.html"))
        }
        .font(AppFont.scaled(11))
        .foregroundStyle(AppColor.textSecondary)
    }

    /// Required by App Store guideline 3.1.2(a) — for a subscription the user
    /// must see length, auto-renewal, and where to cancel before they tap
    /// purchase, so it rides in the pinned footer with the button rather than
    /// somewhere down the scroll. The Lifetime plan is a one-time
    /// non-consumable, so the auto-renew/cancel copy must NOT apply to it
    /// (showing it on a one-time purchase is itself a 3.1.2(a) accuracy
    /// problem).
    @ViewBuilder
    private var autoRenewDisclosure: some View {
        if let product = selectedProduct, product.type != .autoRenewable {
            Text("One-time purchase, charged to your Apple ID. No subscription — nothing to renew or cancel.")
                .font(AppFont.scaled(11))
                .foregroundStyle(AppColor.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } else {
            Button {
                isShowingDisclosure = true
            } label: {
                (
                    Text("Auto-renews unless cancelled. ")
                    + Text("Details").foregroundColor(AppColor.accentLight)
                )
                .font(AppFont.scaled(11))
                .foregroundStyle(AppColor.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    private var disclosureSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Subscription Terms")
                        .font(AppFont.title2)
                        .foregroundStyle(AppColor.textPrimary)

                    Text("Payment is charged to your Apple ID. Subscription auto-renews at the same price unless cancelled at least 24 hours before the end of the current period. You can manage or cancel your subscription in Settings → Apple ID → Subscriptions.")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let monthly = storeService.monthlyProduct {
                        termRow("Monthly", price: "\(monthly.displayPrice)/month")
                    }
                    if let annual = storeService.annualProduct {
                        termRow("Annual", price: "\(annual.displayPrice)/year")
                    }
                }
                .padding(Spacing.lg)
            }
            .background(AppColor.background)
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isShowingDisclosure = false }
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.accentPrimary)
                }
            }
        }
    }

    private func termRow(_ label: LocalizedStringKey, price: String) -> some View {
        HStack {
            Text(label)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            Text(price)
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.accentLight)
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceElevated)
        }
    }

    // MARK: - Actions

    private var selectedProduct: Product? {
        guard let id = selectedProductID else { return nil }
        return storeService.products.first { $0.id == id }
    }

    private func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            // purchaseWithOutcome distinguishes success / pending /
            // cancel so an "Ask to Buy" approval-needed flow surfaces
            // a real message instead of looking like a no-op
            // (audit Library P0.5).
            let outcome = try await storeService.purchaseWithOutcome(product)
            switch outcome {
            case .success:
                // A verified, finished transaction means the user paid —
                // dismiss even if the entitlement snapshot lags a beat
                // (C8: gating on isProUser could strand them on the paywall).
                dismiss()
            case .pending:
                errorMessage = "Purchase pending approval. We'll unlock Pro automatically when it's approved."
            case .userCancelled:
                break // no UI noise on explicit cancel
            }
        } catch {
            errorMessage = "Purchase failed. Try again or restore."
        }
    }

    private func restore() {
        // Guard against concurrent restores: the footer button and the
        // error-banner "Restore purchases" shortcut can both fire AppStore.sync().
        guard !isRestoring else { return }
        isRestoring = true
        Task {
            defer { isRestoring = false }
            do {
                try await storeService.restorePurchases()
                if storeService.isProUser { dismiss() }
            } catch {
                errorMessage = "Restore failed. Check your internet connection and try again."
            }
        }
    }
}

#Preview {
    PaywallView()
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}
