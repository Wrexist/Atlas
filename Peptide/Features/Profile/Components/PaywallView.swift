import SwiftUI
import StoreKit

/// Full-rebuild paywall presented from the upgrade entry points (Home,
/// Analytics, Protocols, PeptideDetail, ExportSection, ProBadge). The
/// onboarding `TrialOfferView` is intentionally separate — that lives
/// inside the onboarding TabView and renders without dismiss chrome.
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
                        .padding(.top, Spacing.xxl)

                    PaywallPhoneMockupRow()

                    featureList

                    if let attribution = creatorAttribution {
                        creatorBanner(attribution)
                    }

                    pricingCardsRow

                    primaryCTA

                    subCTA

                    if let errorMessage {
                        purchaseErrorBanner(message: errorMessage)
                    }

                    footerLinks
                        .padding(.top, Spacing.sm)

                    autoRenewDisclosure
                        .padding(.bottom, Spacing.lg)
                }
                .padding(.horizontal, Spacing.screenPadding)
            }
            .scrollBounceBehavior(.basedOnSize)

            closeButton
                .padding(Spacing.lg)
        }
        .preferredColorScheme(.dark)
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
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "flask.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppColor.accentLight, AppColor.accentPrimary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(AppColor.surfaceElevated)
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                            }
                    }

                Text("Atlas")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
            }

            Text("Unlock your full protocol")
                .font(AppFont.scaled(16))
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(AppFont.scaled(14, weight: .bold))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(AppColor.surfaceSecondary.opacity(0.85))
                        .overlay {
                            Circle().strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                        }
                }
                // 44pt tap target while the visible circle stays 32pt
                // (Deep Audit II B4 — the dismiss control was sub-HIG).
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Close")
    }

    // MARK: - Feature list

    private var featureList: some View {
        VStack(spacing: Spacing.md) {
            featureRow("Unlimited peptide stacks & cycles")
            featureRow("Half-life decay overlays for any stack")
            featureRow("Reconstitution calculator for every vial")
            featureRow("Protocol insights & shareable cycle cards")
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

    private func featureRow(_ label: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(AppFont.scaled(22, weight: .bold))
                .foregroundStyle(AppColor.accentPrimary)

            Text(label)
                .font(AppFont.scaled(17, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
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
                .font(AppFont.scaled(14, weight: .bold))
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
                    subtitle: "Billed \(monthly.displayPrice)/mo",
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
                    badge: "BEST VALUE"
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

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Spacing.xs) {
                        Text(title)
                            .font(AppFont.scaled(17, weight: .bold))
                            .foregroundStyle(AppColor.textPrimary)
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
                        .font(AppFont.scaled(22, weight: .bold, design: .rounded))
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
                .frame(width: 22, height: 22)
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
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AppColor.accentPrimary, AppColor.accentLight],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .shadow(color: AppColor.accentGlow, radius: 6, y: 2)
    }

    /// "Billed €24.99/yr after 3-day free trial" when intro offer is live;
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

    /// Localised per-month string for the annual product. Uses StoreKit's
    /// `priceFormatStyle` so the currency symbol / grouping match the live
    /// product (€, kr, $, ¥ all render correctly).
    private func perMonthEquivalent(for annual: Product) -> String? {
        guard annual.price > 0 else { return nil }
        let monthly = annual.price / 12
        return monthly.formatted(annual.priceFormatStyle)
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
        return percent >= 5 ? "\(percent)% OFF" : nil
    }

    // MARK: - CTA

    private var primaryCTA: some View {
        Button {
            guard let product = selectedProduct, !isPurchasing else { return }
            Task { await purchase(product) }
        } label: {
            HStack(spacing: Spacing.sm) {
                if isPurchasing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppColor.onAccent)
                } else {
                    Text(ctaTitle)
                        .font(AppFont.scaled(17, weight: .bold))
                    Image(systemName: "arrow.right")
                        .font(AppFont.scaled(14, weight: .bold))
                }
            }
            .foregroundStyle(AppColor.onAccent)
            .frame(maxWidth: .infinity)
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
    }

    private var ctaTitle: LocalizedStringKey {
        guard let product = selectedProduct else { return "Choose a Plan" }
        if product.id == StoreService.annualID,
           storeService.isEligibleForAnnualTrial {
            return "Get started for free"
        }
        if product.id == StoreService.monthlyID,
           storeService.isEligibleForMonthlyTrial {
            return "Get started for free"
        }
        return "Continue"
    }

    private var subCTA: some View {
        Text(subCTAText)
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textTertiary)
            .multilineTextAlignment(.center)
    }

    private var subCTAText: String {
        guard let product = selectedProduct else { return "Cancel any time" }
        // Lifetime is a one-time non-consumable — never claim it can be
        // cancelled or that it auto-renews (App Store 3.1.2(a)).
        guard product.type == .autoRenewable else {
            return "One-time purchase · no subscription"
        }
        if product.id == StoreService.annualID,
           storeService.isEligibleForAnnualTrial,
           let trial = storeService.annualTrialDisplay {
            return "\(trial) · Cancel any time"
        }
        if product.id == StoreService.monthlyID,
           storeService.isEligibleForMonthlyTrial,
           let trial = storeService.monthlyTrialDisplay {
            return "\(trial) · Cancel any time"
        }
        return "Cancel any time"
    }

    // MARK: - Footer

    private var footerLinks: some View {
        HStack(spacing: Spacing.xl) {
            Button("Restore Purchases", action: restore)
                .disabled(isRestoring)

            Link("Terms",
                 destination: URL.staticHTTPS("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"))

            Link("Privacy",
                 destination: URL.staticHTTPS("https://wrexist.github.io/Peptide-ai/privacy.html"))
        }
        .font(AppFont.caption)
        .foregroundStyle(AppColor.textSecondary)
    }

    /// Required by App Store guideline 3.1.2(a) — for a subscription the user
    /// must see length, auto-renewal, and where to cancel before they tap
    /// purchase. The Lifetime plan is a one-time non-consumable, so the
    /// auto-renew/cancel copy must NOT apply to it (showing it on a one-time
    /// purchase is itself a 3.1.2(a) accuracy problem).
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
        .preferredColorScheme(.dark)
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
