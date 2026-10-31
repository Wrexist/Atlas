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
/// `source` defaults to `.generic` so a bare `PaywallView()` still
/// compiles; entry points pass their own so the headline can name the
/// feature the user reached for and the funnel events split per entry
/// point. Callers also keep wrapping it in `.liquidGlassPresentation()`
/// where they want the system-glass sheet treatment.
struct PaywallView: View {
    let source: PaywallSource

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var storeService = StoreService.shared

    @State private var selectedProductID: String?
    @Namespace private var planSelection
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var notice: PurchaseNotice?
    @State private var isShowingDisclosure = false
    /// Starts `true` so the first frame shows a spinner, not the
    /// "plans didn't load" state, while the initial fetch is in flight.
    @State private var isLoadingProducts = true
    @State private var isRedeemingCode = false
    /// Set once the view counts as seen, so `onDisappear` only records a
    /// dismissal for a paywall that was actually shown (not the instant
    /// auto-dismiss for an existing Pro user).
    @State private var didRecordView = false
    /// Set when the sheet closes because the user bought, restored or
    /// redeemed — those exits are not dismissals.
    @State private var didConvert = false
    /// Holds the CTA on a "Welcome to Atlas Pro" beat for a moment after a
    /// successful purchase, so paying visibly lands before the sheet closes.
    @State private var didPurchase = false

    init(source: PaywallSource = .generic) {
        self.source = source
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AppColor.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // With a context headline the emblem alone carries the
                    // brand, so the screen has one heading, not three.
                    header(showsTitle: source.headline == nil)
                        .padding(.top, Spacing.xxxl)

                    if let headline = source.headline {
                        contextHeadline(headline, subhead: source.subhead)
                    }

                    offerHeadline

                    pricingCardsRow

                    socialProof

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
            if !didRecordView {
                didRecordView = true
                OnboardingFunnelTracker.recordEvent(source.viewedEvent)
            }
            await loadPlans()
        }
        .onDisappear {
            if didRecordView && !didConvert {
                OnboardingFunnelTracker.recordEvent(source.dismissedEvent)
            }
        }
        .offerCodeRedemption(isPresented: $isRedeemingCode) { _ in
            Task { await finishCodeRedemption() }
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

    private func header(showsTitle: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            MilestoneArtwork(size: 40, style: .emblem)
            if showsTitle {
                Text("Atlas Pro")
                    .font(AppFont.scaled(26, weight: .bold, design: .rounded, relativeTo: .title1))
                    .foregroundStyle(AppColor.textPrimary)
            }
        }
    }

    /// Names the feature the user was reaching for when the paywall opened.
    /// Sits above the offer hero rather than replacing it, so the price and
    /// trial terms stay exactly where every other entry point shows them.
    private func contextHeadline(_ headline: String, subhead: String?) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(headline)
                .font(AppFont.scaled(24, weight: .bold, design: .rounded, relativeTo: .title2))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
            if let subhead {
                Text(subhead)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
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
        .appAnimation(AppAnimation.springSnappy, value: selectedProductID)
    }

    private var headlineEyebrow: String {
        guard let product = selectedProduct else { return String(localized: "EVERYTHING UNLOCKED") }
        if let days = storeService.redeemableTrialDays(for: product) {
            return String(localized: "YOUR \(days)-DAY FREE TRIAL")
        }
        return product.type == .autoRenewable
            ? String(localized: "EVERYTHING UNLOCKED")
            : String(localized: "ONE PAYMENT, YOURS FOREVER")
    }

    private var headlineHero: String {
        guard let product = selectedProduct else { return String(localized: "Atlas Pro") }
        if let days = storeService.redeemableTrialDays(for: product) {
            return days == 1 ? String(localized: "1 day free") : String(localized: "\(days) days free")
        }
        return product.displayPrice
    }

    private var headlineSupport: String {
        guard let product = selectedProduct else {
            return String(localized: "Training, nutrition and recovery — one app, everything on.")
        }
        guard product.type == .autoRenewable else {
            return String(localized: "Pay once. No subscription, nothing to cancel.")
        }
        let price = "\(product.displayPrice)\(periodSuffix(for: product))"
        if storeService.redeemableTrialDays(for: product) != nil {
            return String(localized: "Then \(price). Cancel anytime before it starts.")
        }
        return String(localized: "\(price) — cancel anytime.")
    }

    // MARK: - Trust line

    /// Sits directly under the prices, where the user is weighing the number.
    /// A verifiable claim only: the app's privacy posture. The previous
    /// "4.9 · 12k+ athletes" rating had no App Store source behind it —
    /// fabricated social proof inside a purchase flow is a Guideline 2.3.1
    /// problem and beneath the app's honesty bar. Reinstate a rating pill
    /// only when it renders the real, current App Store figure.
    private var socialProof: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "lock.shield.fill")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.accentPrimary)
            // "Cancel anytime" already sits in the offer line and the CTA;
            // repeating it here made the trust line read as boilerplate.
            Text("Private by design — no ads, no tracking")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Private by design. No ads, no tracking.")
    }

    /// Lifetime is a one-time purchase: "cancel anytime" copy would
    /// contradict the footer's "nothing to renew or cancel" disclosure.
    private var isOneTimePurchaseSelected: Bool {
        guard let product = selectedProduct else { return false }
        return product.type != .autoRenewable
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
                    // A cancel day only reads as distinct from Today and the
                    // charge day when the trial leaves room for one.
                    if days >= 3 {
                        timelineRow(
                            icon: "gearshape.fill",
                            title: "Day \(days - 1)",
                            detail: "Still not for you? Cancel anytime in Settings → your name → Subscriptions and keep the rest of the trial."
                        )
                    }
                    timelineRow(
                        icon: "checkmark.seal.fill",
                        title: "Day \(days)",
                        detail: "Your plan starts at \(product.displayPrice)\(periodSuffix(for: product))."
                    )
                }
            }
        }
    }

    private func timelineRow(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
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

    /// Only what Pro actually unlocks; see `ProBenefits` for why.
    private var featureList: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("What you get")
                .font(AppFont.scaled(13, weight: .heavy))
                .tracking(1)
                .foregroundStyle(AppColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(ProBenefits.all, id: \.icon) { feature in
                featureRow(icon: feature.icon, title: feature.title)
            }
        }
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
            Text(isOneTimePurchaseSelected
                 ? "One payment. Your logs, workouts and photos stay yours."
                 : "Cancel anytime in Settings → your name → Subscriptions. Your logs, workouts and photos stay yours either way.")
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

    /// Only a real failure gets the red banner: a pending Ask to Buy and
    /// a restore with nothing to restore are outcomes, not errors.
    @ViewBuilder
    private func noticeView(_ notice: PurchaseNotice) -> some View {
        switch notice {
        case .purchaseFailed(let message):
            failureBanner(title: "Purchase didn't go through", message: message, isRestore: false)
        case .restoreFailed(let message):
            failureBanner(title: "Restore didn't go through", message: message, isRestore: true)
        case .pending:
            pendingApprovalBanner
        case .nothingToRestore:
            Text("No previous purchase found to restore.")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var pendingApprovalBanner: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "clock.fill")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.recap)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Waiting for approval")
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                Text("We'll unlock Pro automatically when the purchase is approved.")
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.recap.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.recap.opacity(0.30), lineWidth: 0.5)
                }
        }
        .accessibilityElement(children: .combine)
    }

    /// Friendly error surface for purchase / restore failures. Replaces the
    /// previous raw `Text(errorMessage).foregroundStyle(.destructive)` line
    /// that just dumped the StoreKit description on the user with no path
    /// forward. Surfaces a localized headline + the underlying detail in
    /// muted secondary text, plus an explicit Restore Purchases shortcut so
    /// a transient StoreKit failure isn't a dead end. A failed restore
    /// retries the restore — never a purchase the user didn't ask for.
    private func failureBanner(title: LocalizedStringKey, message: String, isRestore: Bool) -> some View {
        VStack(spacing: Spacing.xs) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.destructive)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(message)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: Spacing.sm) {
                if isRestore {
                    Button {
                        notice = nil
                        restore()
                    } label: {
                        Text("Try again").minimumHitArea()
                    }
                    .foregroundStyle(AppColor.accentLight)
                } else {
                    if let product = selectedProduct {
                        Button {
                            notice = nil
                            Task { await purchase(product) }
                        } label: {
                            Text("Try again").minimumHitArea()
                        }
                        .foregroundStyle(AppColor.accentLight)
                    }

                    Button {
                        notice = nil
                        restore()
                    } label: {
                        Text("Restore purchases").minimumHitArea()
                    }
                    .foregroundStyle(AppColor.textSecondary)
                }

                Spacer(minLength: 0)
            }
            .font(AppFont.caption2)
            .fontWeight(.semibold)
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
            if storeService.products.isEmpty {
                if isLoadingProducts {
                    // The shape of the three plan rows, so prices land in
                    // place instead of replacing a spinner.
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonBlock(height: 72, cornerRadius: Spacing.cardCornerRadius)
                    }
                } else {
                    productsUnavailable
                }
            }
            if let annual = storeService.annualProduct {
                pricingRow(
                    product: annual,
                    title: "Yearly",
                    // Guideline 3.1.2(c): the billed amount is the headline
                    // number; the per-month equivalent rides in the subtitle.
                    primaryPrice: annual.displayPrice,
                    primaryUnit: String(localized: "/yr"),
                    subtitle: yearlySubtitle(for: annual),
                    badge: savingsBadge
                )
            }
            if let monthly = storeService.monthlyProduct {
                pricingRow(
                    product: monthly,
                    title: "Monthly",
                    primaryPrice: monthly.displayPrice,
                    primaryUnit: String(localized: "/mo"),
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
                    primaryUnit: String(localized: "once"),
                    subtitle: String(localized: "Pay once. Yours forever."),
                    // "BEST VALUE" is two words and it was pushing the
                    // title into a mid-word wrap ("Lifet / ime") on the
                    // narrowest phones. One word, same promise.
                    badge: String(localized: "FOREVER"),
                    // Only the recommended plan's pill is lit, so the eye
                    // has one place to land instead of two glowing badges.
                    isBadgeEmphasized: false
                )
            }
        }
        .appAnimation(AppAnimation.fadeIn, value: storeService.products.isEmpty)
    }

    /// Shown when StoreKit returned no products (offline, storefront
    /// hiccup). Without it the plan list collapsed to nothing and the CTA
    /// sat disabled with no explanation or way forward.
    private var productsUnavailable: some View {
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

    private func pricingRow(
        product: Product,
        title: LocalizedStringKey,
        primaryPrice: String,
        primaryUnit: String,
        subtitle: String,
        badge: String?,
        isBadgeEmphasized: Bool = true
    ) -> some View {
        let isSelected = selectedProductID == product.id
        return Button {
            Haptics.selection()
            AppAnimation.with(AppAnimation.step) {
                selectedProductID = product.id
            }
        } label: {
            // One line when it fits. At accessibility sizes the fixed-width
            // title, badge and price no longer fit side by side, and the row
            // used to push the whole paywall — Close included — past the
            // screen edge, so it stacks instead.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.md) {
                    radioMark(isSelected: isSelected)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Spacing.xs) {
                            planTitle(title)
                                // Without `fixedSize` the badge alongside wins the
                                // width negotiation and the plan name — the one
                                // word that has to stay readable — wraps mid-word.
                                .fixedSize()
                            if let badge {
                                savingsPill(badge, isEmphasized: isBadgeEmphasized)
                            }
                        }

                        Text(subtitle)
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer(minLength: Spacing.sm)

                    planPrice(primaryPrice, unit: primaryUnit)
                        .fixedSize()
                }

                HStack(alignment: .top, spacing: Spacing.md) {
                    radioMark(isSelected: isSelected)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        planTitle(title)
                            .minimumScaleFactor(0.7)
                        if let badge {
                            savingsPill(badge, isEmphasized: isBadgeEmphasized)
                        }
                        Text(subtitle)
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        planPrice(primaryPrice, unit: primaryUnit)
                            .minimumScaleFactor(0.5)
                    }
                }
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
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
                    .overlay {
                        // One selection ring that slides between plans,
                        // so switching reads as moving a choice.
                        if isSelected {
                            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                                .strokeBorder(AppColor.accentPrimary, lineWidth: 2)
                                .matchedGeometryEffect(id: "planSelection", in: planSelection)
                        }
                    }
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.985))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .transition(.opacity)
    }

    private func planTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(AppFont.scaled(16, weight: .bold))
            .foregroundStyle(AppColor.textPrimary)
            .lineLimit(1)
    }

    private func planPrice(_ price: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(price)
                .font(AppFont.scaled(20, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
            Text(unit)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
        }
        .lineLimit(1)
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
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func savingsPill(_ text: String, isEmphasized: Bool) -> some View {
        let label = Text(text)
            .font(AppFont.scaled(11, weight: .heavy))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 2)
        if isEmphasized {
            label
                .foregroundStyle(AppColor.onAccent)
                .background {
                    Capsule()
                        .fill(AppColor.accentFill)
                }
                .shadow(color: AppColor.accentGlow, radius: 6, y: 2)
        } else {
            label
                .foregroundStyle(AppColor.textSecondary)
                .background {
                    Capsule()
                        .strokeBorder(AppColor.glassBorder, lineWidth: 1)
                }
        }
    }

    /// Secondary line under the billed yearly price: "7 days free · €2.08/mo"
    /// while the intro offer is live, "Just €2.08/mo" once the user is no
    /// longer eligible (already redeemed an intro in this group).
    private func yearlySubtitle(for product: Product) -> String {
        let perMonth = perMonthEquivalent(for: product).map { String(localized: "\($0)/mo") }
        if storeService.isEligibleForAnnualTrial,
           let trial = storeService.annualTrialDisplay {
            guard let perMonth else { return trial }
            return "\(trial) · \(perMonth)"
        }
        guard let perMonth else { return String(localized: "Billed yearly") }
        return String(localized: "Just \(perMonth)")
    }

    private func monthlySubtitle(for product: Product) -> String {
        let priceLine = String(localized: "Billed \(product.displayPrice)/mo")
        if storeService.isEligibleForMonthlyTrial,
           let trial = storeService.monthlyTrialDisplay {
            return String(localized: "\(priceLine) after \(trial)")
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

    /// "1 month", "1 year" — the subscription length, localised.
    private func periodLength(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        var components = DateComponents()
        switch period.unit {
        case .year:  components.year = period.value
        case .month: components.month = period.value
        case .week:  components.weekOfMonth = period.value
        case .day:   components.day = period.value
        @unknown default: return ""
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        return formatter.string(from: components) ?? ""
    }

    /// "/yr", "/mo" — read from the product's own renewal period rather
    /// than its identifier, so a future weekly plan can't render as a
    /// yearly one.
    private func periodSuffix(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        switch period.unit {
        case .year:  return String(localized: "/yr")
        case .month: return String(localized: "/mo")
        case .week:  return String(localized: "/wk")
        case .day:   return String(localized: "/day")
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
        return percent >= 5 ? String(localized: "SAVE \(percent)%") : nil
    }

    // MARK: - Pinned purchase footer

    private var purchaseFooter: some View {
        VStack(spacing: Spacing.sm) {
            if let notice {
                noticeView(notice)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            primaryCTA

            autoRenewDisclosure

            footerLinks
        }
        .appAnimation(AppAnimation.springSnappy, value: notice)
        // VoiceOver focus returns to the CTA after the purchase sheet
        // closes, so the notice has to be spoken to be noticed.
        .onChange(of: notice) { _, newNotice in
            guard let newNotice else { return }
            AccessibilityNotification.Announcement(newNotice.announcement).post()
        }
    }

    /// Two-line CTA: the action on top, the money underneath.
    ///
    /// The old label was "Continue", which is the weakest thing a paywall
    /// button can say — it names the gesture, not what the user gets, and it
    /// hides the one fact that removes the risk of tapping it. The top line
    /// now states the offer ("Start my 7-day free trial") and the bottom line
    /// states the charge in the user's own currency ("$0.00 today, then
    /// $49.99/yr"). Both halves matter: trial-first framing is what lifts
    /// tap-through, and the explicit price is what stops the day-0 cancel
    /// from someone who tapped without knowing what came next.
    private var primaryCTA: some View {
        Button {
            // A running restore may dismiss or set its own notice; don't
            // race a purchase against it.
            guard let product = selectedProduct, !isPurchasing, !isRestoring else { return }
            Task { await purchase(product) }
        } label: {
            VStack(spacing: 2) {
                if didPurchase {
                    Label("Welcome to Atlas Pro", systemImage: "checkmark.circle.fill")
                        .font(AppFont.scaled(16, weight: .bold))
                        .symbolEffect(.bounce, value: reduceMotion ? false : didPurchase)
                        .transition(.opacity)
                } else if isPurchasing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppColor.inverseInk)
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
            .primaryCTAChrome()
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.97))
        // Not disabled while purchasing: the action's guard already blocks a
        // second tap, and the disabled dim would fade the spinner.
        .disabled(selectedProduct == nil)
        .accessibilityLabel(ctaAccessibilityLabel)
    }

    private var ctaTitle: String {
        guard let product = selectedProduct else { return String(localized: "Choose a plan") }
        guard product.type == .autoRenewable else { return String(localized: "Get lifetime access") }
        if let days = storeService.redeemableTrialDays(for: product) {
            return String(localized: "Start my \(days)-day free trial")
        }
        return String(localized: "Unlock Atlas Pro")
    }

    /// The money line. Never promises a free trial the user can't redeem —
    /// `redeemableTrialDays` is eligibility-gated, so a returning subscriber
    /// sees the real price on the button instead of a zero they won't get.
    private var ctaDetail: String? {
        guard let product = selectedProduct else { return nil }
        guard product.type == .autoRenewable else {
            return String(localized: "\(product.displayPrice) once · no subscription")
        }
        let price = "\(product.displayPrice)\(periodSuffix(for: product))"
        if storeService.redeemableTrialDays(for: product) != nil {
            return String(localized: "\(zeroPrice(for: product)) today, then \(price)")
        }
        return String(localized: "\(price) · cancel anytime")
    }

    /// The visible title, then the money line, so VoiceOver reads the
    /// same words the button shows.
    private var ctaAccessibilityLabel: String {
        guard let ctaDetail else { return ctaTitle }
        return "\(ctaTitle). \(ctaDetail)"
    }

    // MARK: - Footer

    /// One row when it fits; at large Dynamic Type the four links split
    /// into account actions and legal links, and at accessibility sizes
    /// into one link per line, so none is clipped and the footer never
    /// widens the screen past its Close button.
    private var footerLinks: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.md) {
                accountLinks
                legalLinks
            }
            VStack(spacing: 0) {
                HStack(spacing: Spacing.md) { accountLinks }
                HStack(spacing: Spacing.md) { legalLinks }
            }
            VStack(spacing: 0) {
                accountLinks
                legalLinks
            }
        }
        .font(AppFont.scaled(11))
        .foregroundStyle(AppColor.textSecondary)
    }

    @ViewBuilder
    private var accountLinks: some View {
        Button(action: restore) {
            Group {
                if isRestoring {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("Restoring purchases")
                } else {
                    Text("Restore purchases")
                }
            }
            .minimumHitArea()
        }
        .disabled(isRestoring || isPurchasing)

        Button {
            isRedeemingCode = true
        } label: {
            Text("Redeem code").minimumHitArea()
        }
        .disabled(isPurchasing)
    }

    @ViewBuilder
    private var legalLinks: some View {
        Link(destination: URL.staticHTTPS("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")) {
            Text("Terms of Use").minimumHitArea()
        }

        Link(destination: URL.staticHTTPS("https://wrexist.github.io/Atlas/privacy.html")) {
            Text("Privacy Policy").minimumHitArea()
        }
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
        if isOneTimePurchaseSelected {
            Text("One-time purchase, charged to your Apple Account. No subscription — nothing to renew or cancel.")
                .font(AppFont.scaled(11))
                .foregroundStyle(AppColor.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } else {
            Button {
                isShowingDisclosure = true
            } label: {
                (
                    Text(autoRenewLine)
                    + Text(" Details").foregroundStyle(AppColor.accentLight)
                )
                .font(AppFont.scaled(11))
                .foregroundStyle(AppColor.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: Spacing.minimumHitTarget)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    /// The renewal price and cancellation window, inline under the button so
    /// the user sees them without opening the Details sheet.
    private var autoRenewLine: String {
        guard let product = selectedProduct else {
            return String(localized: "Auto-renews unless canceled at least 24 hours before the period ends.")
        }
        let price = "\(product.displayPrice)\(periodSuffix(for: product))"
        return String(localized: "Auto-renews at \(price) unless canceled at least 24 hours before the period ends.")
    }

    private var disclosureSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Subscription Terms")
                        .font(AppFont.title2)
                        .foregroundStyle(AppColor.textPrimary)

                    Text("Payment is charged to your Apple Account. Subscription auto-renews at the same price unless canceled at least 24 hours before the end of the current period. You can manage or cancel your subscription in Settings → your name → Subscriptions.")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let monthly = storeService.monthlyProduct {
                        termRow(for: monthly)
                    }
                    if let annual = storeService.annualProduct {
                        termRow(for: annual)
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

    /// Product title from App Store Connect, its length and its price —
    /// the three facts Guideline 3.1.2 asks for on each auto-renewable plan.
    /// Length and price period come from the product itself, so this sheet
    /// can't disagree with what App Store Connect will charge.
    private func termRow(for product: Product) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(verbatim: product.displayName)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(verbatim: periodLength(for: product))
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            Text(verbatim: "\(product.displayPrice)\(periodSuffix(for: product))")
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.accentLight)
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceElevated)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private var selectedProduct: Product? {
        guard let id = selectedProductID else { return nil }
        return storeService.products.first { $0.id == id }
    }

    private func loadPlans() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        await storeService.loadProducts()
        if selectedProductID == nil {
            selectedProductID = storeService.annualProduct?.id
                ?? storeService.monthlyProduct?.id
        }
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
                didConvert = true
                OnboardingFunnelTracker.recordEvent(source.purchasedEvent)
                Haptics.success()
                AppAnimation.with(AppAnimation.springSnappy) { didPurchase = true }
                try? await Task.sleep(for: .milliseconds(900))
                dismiss()
            case .pending:
                notice = .pending
            case .userCancelled:
                break // no UI noise on explicit cancel
            }
        } catch {
            notice = .purchaseFailed(String(localized: "Purchase failed. Try again or restore."))
        }
    }

    private func restore() {
        // Guard against concurrent restores: the footer button and the
        // error-banner "Restore purchases" shortcut can both fire AppStore.sync().
        guard !isRestoring, !isPurchasing else { return }
        isRestoring = true
        Task {
            defer { isRestoring = false }
            do {
                guard try await storeService.restorePurchases() == .completed else { return }
                if storeService.isProUser {
                    didConvert = true
                    dismiss()
                } else {
                    notice = .nothingToRestore
                }
            } catch {
                notice = .restoreFailed(String(localized: "Restore failed. Check your internet connection and try again."))
            }
        }
    }

    /// Apple's redemption sheet completes the transaction itself; it reaches
    /// `Transaction.updates`, but re-reading entitlements here closes the
    /// paywall without waiting on that listener.
    private func finishCodeRedemption() async {
        await storeService.checkProAccess()
        guard storeService.isProUser else { return }
        didConvert = true
        OnboardingFunnelTracker.recordEvent(source.redeemedEvent)
        dismiss()
    }
}

#Preview {
    PaywallView(source: .protocolLimit)
        .environment(DataStore(seedSampleData: true))
        .preferredColorScheme(.dark)
}

/// What the paywall footer reports after a purchase or restore attempt.
private enum PurchaseNotice: Equatable {
    case purchaseFailed(String)
    case restoreFailed(String)
    case pending
    case nothingToRestore

    var announcement: String {
        switch self {
        case .purchaseFailed(let message):
            String(localized: "Purchase didn't go through") + ". " + message
        case .restoreFailed(let message):
            String(localized: "Restore didn't go through") + ". " + message
        case .pending:
            String(localized: "Waiting for approval") + ". "
                + String(localized: "We'll unlock Pro automatically when the purchase is approved.")
        case .nothingToRestore:
            String(localized: "No previous purchase found to restore.")
        }
    }
}
