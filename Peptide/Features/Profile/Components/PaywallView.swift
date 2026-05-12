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
                        Text(errorMessage)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.destructive)
                            .multilineTextAlignment(.center)
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

                Text("PeptideX")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
            }

            Text("Unlock your full protocol")
                .font(.system(size: 16))
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(AppColor.surfaceSecondary.opacity(0.85))
                        .overlay {
                            Circle().strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                        }
                }
        }
        .accessibilityLabel("Close")
    }

    // MARK: - Feature list

    private var featureList: some View {
        VStack(spacing: Spacing.md) {
            featureRow("Unlimited peptide stacks & cycles")
            featureRow("Half-life decay overlays for any stack")
            featureRow("AI reconstitution calculator for every vial")
            featureRow("Protocol insights & shareable cycle cards")
        }
    }

    private func featureRow(_ label: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppColor.accentPrimary)

            Text(label)
                .font(.system(size: 17, weight: .semibold))
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
    /// step. The actual discount-on-purchase wiring is a follow-up — it
    /// requires either RevenueCat (not in this app) or App-Store-Connect
    /// signed promo offers. The banner is present so the attribution
    /// shows up the moment the user reaches the paywall; copy will read
    /// honestly once the price actually changes.
    private func creatorBanner(_ attribution: CreatorAttribution) -> some View {
        let bannerGreen = Color(red: 0.063, green: 0.725, blue: 0.506) // #10B981
        return HStack(spacing: Spacing.sm) {
            Image(systemName: "tag.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(bannerGreen)
                .accessibilityHidden(true)              // Text alongside carries the discount label

            Text("\(attribution.discountPercent)% off applied — thanks to \(attribution.creatorName)!")
                .font(AppFont.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

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

    // MARK: - Pricing cards

    private var pricingCardsRow: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            if let annual = storeService.annualProduct {
                pricingCard(
                    product: annual,
                    title: "Yearly",
                    primaryPrice: perMonthEquivalent(for: annual) ?? annual.displayPrice,
                    primaryUnit: "/mo",
                    subtitle: yearlySubtitle(for: annual),
                    badge: savingsBadge,
                    isYearly: true
                )
            }
            if let monthly = storeService.monthlyProduct {
                pricingCard(
                    product: monthly,
                    title: "Monthly",
                    primaryPrice: monthly.displayPrice,
                    primaryUnit: "/mo",
                    subtitle: "Billed \(monthly.displayPrice)/mo",
                    badge: nil,
                    isYearly: false
                )
            }
        }
    }

    private func pricingCard(
        product: Product,
        title: LocalizedStringKey,
        primaryPrice: String,
        primaryUnit: String,
        subtitle: String,
        badge: String?,
        isYearly: Bool
    ) -> some View {
        let isSelected = selectedProductID == product.id
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                selectedProductID = product.id
            }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    radioMark(isSelected: isSelected)
                }

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(primaryPrice)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .monospacedDigit()
                    Text(primaryUnit)
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.6))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(
                                isSelected ? AppColor.accentPrimary : AppColor.glassBorder,
                                lineWidth: isSelected ? 2 : 0.5
                            )
                    }
            }
            .overlay(alignment: .top) {
                if isYearly, let badge {
                    savingsPill(badge)
                        .offset(y: -12)
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
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColor.accentPrimary)
            }
        }
        .contentTransition(.symbolEffect(.replace))
    }

    private func savingsPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(.white)
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
        let percent = Int((saved as NSDecimalNumber).doubleValue * 100)
        return percent > 0 ? "\(percent)% OFF" : nil
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
                        .tint(.white)
                } else {
                    Text(ctaTitle)
                        .font(.system(size: 17, weight: .bold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.310, green: 0.275, blue: 0.898), // #4F46E5
                                Color(red: 0.486, green: 0.227, blue: 0.929), // #7C3AED
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

            Link("Terms",
                 destination: URL.staticHTTPS("https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"))

            Link("Privacy",
                 destination: URL.staticHTTPS("https://wrexist.github.io/Peptide-ai/privacy.html"))
        }
        .font(AppFont.caption)
        .foregroundStyle(AppColor.textSecondary)
    }

    /// Required by App Store guideline 3.1.2(a) — the user must see length,
    /// auto-renewal, and where to cancel before they tap purchase. Tap
    /// expands the full term details into a sheet.
    private var autoRenewDisclosure: some View {
        Button {
            isShowingDisclosure = true
        } label: {
            (
                Text("Auto-renews unless cancelled. ")
                + Text("Details").foregroundColor(AppColor.accentLight)
            )
            .font(.system(size: 11))
            .foregroundStyle(AppColor.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
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
            _ = try await storeService.purchase(product)
            if storeService.isProUser { dismiss() }
        } catch {
            errorMessage = "Purchase failed. Try again or restore."
        }
    }

    private func restore() {
        Task {
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
