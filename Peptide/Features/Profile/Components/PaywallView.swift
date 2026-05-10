import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var storeService = StoreService.shared
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var selectedProductID: String?
    @State private var isShowingDisclosure = false
    @State private var recommendedGlow = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    hero
                    featuresCard
                    pricingTiles
                    purchaseCTA
                    restoreButton

                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.destructive)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.lg)
            }
            .background(AppColor.background)
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                compactDisclosureBar
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .task {
                await storeService.loadProducts()
                if selectedProductID == nil {
                    selectedProductID = defaultSelection
                }
                // Subtle pulse on the recommended tile so the eye lands on
                // it first when the paywall mounts.
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    recommendedGlow.toggle()
                }
            }
            .onChange(of: storeService.products.map(\.id)) { _, _ in
                if selectedProductID == nil {
                    selectedProductID = defaultSelection
                }
            }
            .sheet(isPresented: $isShowingDisclosure) {
                disclosureSheet
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColor.accentLight, AppColor.accentPrimary],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: AppColor.accentGlow, radius: 14, y: 4)

            Text("PeptideX Pro")
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)

            Text("Unlock the full potential of your protocols")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.accentLight)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Spacing.sm)
    }

    // MARK: - Features

    private var featuresCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                featureRow(icon: "infinity", title: "Unlimited Protocols", description: "Create as many protocols as you need")
                featureRow(icon: "chart.xyaxis.line", title: "Full Analytics", description: "All time ranges, HealthKit correlation, export")
                featureRow(icon: "brain.head.profile.fill", title: "AI Insights", description: "Smart recommendations and research assistant")
                featureRow(icon: "icloud.fill", title: "Cloud Sync", description: "Backup and sync across devices")
                featureRow(icon: "square.grid.2x2.fill", title: "All Widgets", description: "Every widget type + Apple Watch")
                featureRow(icon: "square.and.arrow.up", title: "Data Export", description: "CSV reports and JSON backups")
            }
        }
    }

    private func featureRow(icon: String, title: LocalizedStringKey, description: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(AppColor.accentLight)
                .frame(width: 32, height: 32)
                .background {
                    Circle().fill(AppColor.accentPrimary.opacity(0.18))
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                Text(description)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: - Pricing tiles

    private var pricingTiles: some View {
        VStack(spacing: Spacing.sm) {
            if let annual = storeService.annualProduct {
                pricingTile(
                    product: annual,
                    isBest: true,
                    badge: annualBadge,
                    perPeriodCaption: perMonthEquivalent(for: annual)
                )
            }
            if let monthly = storeService.monthlyProduct {
                pricingTile(
                    product: monthly,
                    isBest: false,
                    badge: monthlyTrialBadge,
                    perPeriodCaption: nil
                )
            }
            if let lifetime = storeService.lifetimeProduct {
                pricingTile(
                    product: lifetime,
                    isBest: false,
                    badge: "One-Time",
                    perPeriodCaption: "Pay once, yours forever"
                )
            }
        }
    }

    private func pricingTile(
        product: Product,
        isBest: Bool,
        badge: LocalizedStringKey?,
        perPeriodCaption: String?
    ) -> some View {
        let selected = selectedProductID == product.id
        return Button {
            if dataStoreHaptics {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                selectedProductID = product.id
            }
        } label: {
            VStack(spacing: 0) {
                if isBest {
                    recommendedRibbon
                }

                HStack(spacing: Spacing.md) {
                    radioMark(selected: selected)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: Spacing.xs) {
                            Text(displayName(for: product))
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)
                        }

                        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                            Text(product.displayPrice)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColor.textPrimary)
                                .monospacedDigit()
                            Text(priceSuffix(for: product))
                                .font(AppFont.subheadline)
                                .foregroundStyle(AppColor.textSecondary)

                            if let strike = strikethroughComparison(for: product) {
                                Text(strike)
                                    .font(AppFont.caption)
                                    .strikethrough()
                                    .foregroundStyle(AppColor.textTertiary)
                                    .monospacedDigit()
                                    .padding(.leading, Spacing.xs)
                            }
                        }

                        if let perPeriodCaption {
                            Text(perPeriodCaption)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textTertiary)
                        }
                    }

                    Spacer(minLength: Spacing.sm)

                    if let badge {
                        Text(badge)
                            .font(AppFont.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.accentLight)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 5)
                            .background {
                                Capsule().fill(AppColor.accentPrimary.opacity(0.22))
                            }
                            .overlay {
                                Capsule().strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                            }
                            .liquidGlass(.capsule)
                    }
                }
                .padding(Spacing.md)
            }
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.6))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .fill(selected ? AppColor.glassTint : AppColor.cardOverlay)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(
                                selected ? AppColor.accentPrimary : (isBest ? AppColor.accentLight.opacity(0.4) : AppColor.glassBorder),
                                lineWidth: selected ? 1.5 : (isBest ? 1.0 : 0.5)
                            )
                    }
            }
            .liquidGlass(.rect(cornerRadius: Spacing.cardCornerRadius))
            .shadow(
                color: shadowColor(selected: selected, isBest: isBest),
                radius: shadowRadius(selected: selected, isBest: isBest),
                y: selected || isBest ? 4 : 0
            )
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.985))
    }

    /// Pinned ribbon along the top edge of the recommended tile. Truthful copy
    /// — "Recommended" is a value judgment we're making, not a fabricated
    /// social-proof claim.
    private var recommendedRibbon: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
            Text("RECOMMENDED")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.5)
        }
        .foregroundStyle(AppColor.background)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [AppColor.accentLight, AppColor.accentPrimary],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: Spacing.cardCornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: Spacing.cardCornerRadius,
                style: .continuous
            )
        )
    }

    private func shadowColor(selected: Bool, isBest: Bool) -> Color {
        if selected { return AppColor.accentGlow }
        if isBest { return AppColor.accentPrimary.opacity(recommendedGlow ? 0.35 : 0.15) }
        return .clear
    }

    private func shadowRadius(selected: Bool, isBest: Bool) -> CGFloat {
        if selected { return 14 }
        if isBest { return recommendedGlow ? 18 : 8 }
        return 0
    }

    private func radioMark(selected: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(
                    selected ? AppColor.accentPrimary : AppColor.glassBorder,
                    lineWidth: selected ? 2 : 1
                )
                .frame(width: 22, height: 22)
            if selected {
                Circle()
                    .fill(AppColor.accentPrimary)
                    .frame(width: 12, height: 12)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    /// Yearly equivalent of the monthly product as a strikethrough caption,
    /// surfaced next to the annual price so the savings are visible without
    /// the user having to do mental math. Returns nil for monthly/lifetime.
    private func strikethroughComparison(for product: Product) -> String? {
        guard product.id == StoreService.annualID,
              let monthly = storeService.monthlyProduct else { return nil }
        let yearAtMonthly = monthly.price * 12
        // Defensive: only show the strikethrough when the comparison is real
        // savings — if annual is somehow ≥ 12× monthly, the comparison would
        // mislead.
        guard yearAtMonthly > product.price else { return nil }
        return yearAtMonthly.formatted(product.priceFormatStyle)
    }

    // MARK: - CTA

    private var purchaseCTA: some View {
        let product = selectedProduct
        return VStack(spacing: Spacing.xs) {
            GlassButton(
                title: ctaTitle,
                icon: isPurchasing ? nil : "arrow.right",
                style: .primary,
                isFullWidth: true
            ) {
                guard let product, !isPurchasing else { return }
                Task {
                    isPurchasing = true
                    _ = try? await storeService.purchase(product)
                    isPurchasing = false
                    if storeService.isProUser { dismiss() }
                }
            }
            .opacity(product != nil && !isPurchasing ? 1.0 : 0.55)
            .disabled(product == nil || isPurchasing)
            .overlay {
                if isPurchasing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppColor.accentLight)
                }
            }

            if let subtitle = ctaSubtitle {
                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
                    .id(subtitle)
            }

            trustSignalsRow
                .padding(.top, Spacing.xs)
        }
        .padding(.top, Spacing.xs)
    }

    /// Small, factual row of reassurance signals just under the CTA. The
    /// goal is to defuse the three most common abandonment reasons:
    /// "Will I get charged today?", "How do I cancel?", "Is this safe?".
    private var trustSignalsRow: some View {
        HStack(spacing: Spacing.lg) {
            trustSignal(icon: "lock.shield.fill", label: "Secured by Apple")
            trustSignal(icon: "xmark.circle.fill", label: "Cancel anytime")
            trustSignal(icon: "creditcard.fill", label: "No charge today")
        }
        .frame(maxWidth: .infinity)
    }

    private func trustSignal(icon: String, label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppColor.textTertiary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    /// Reinforcement copy directly under the CTA so the user understands
    /// the immediate billing impact. Wording tracks the selected tier and
    /// trial eligibility — "no charge today" only appears when accurate.
    private var ctaSubtitle: String? {
        guard let product = selectedProduct else { return nil }
        if product.id == StoreService.lifetimeID {
            return "One-time purchase. No subscription."
        }
        if product.id == StoreService.annualID,
           storeService.isEligibleForAnnualTrial,
           let display = storeService.annualTrialDisplay {
            return "No charge for \(display). Then \(product.displayPrice)/year."
        }
        if product.id == StoreService.monthlyID,
           storeService.isEligibleForMonthlyTrial,
           let display = storeService.monthlyTrialDisplay {
            return "No charge for \(display). Then \(product.displayPrice)/month."
        }
        return "Cancel anytime in Settings."
    }

    private var restoreButton: some View {
        Button("Restore Purchases") {
            Task {
                do {
                    try await storeService.restorePurchases()
                    if storeService.isProUser { dismiss() }
                } catch {
                    errorMessage = "Restore failed. Check your internet connection and try again."
                }
            }
        }
        .font(AppFont.subheadline)
        .foregroundStyle(AppColor.textSecondary)
        .padding(.top, Spacing.xs)
    }

    // MARK: - Compact disclosure bar

    private var compactDisclosureBar: some View {
        VStack(spacing: 6) {
            // The minimum required by Guideline 3.1.2(a) on a single line —
            // length, auto-renew, and where to cancel. The full paragraph is
            // one tap away in the disclosureSheet.
            (
                Text("Auto-renews unless cancelled. ")
                + Text("Details").foregroundColor(AppColor.accentLight)
            )
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textTertiary)
            .multilineTextAlignment(.center)
            .onTapGesture { isShowingDisclosure = true }

            HStack(spacing: Spacing.lg) {
                Link("Terms of Use",
                     destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("Privacy Policy",
                     destination: URL(string: "https://wrexist.github.io/Peptide-ai/privacy.html")!)
            }
            .font(AppFont.caption)
            .foregroundStyle(AppColor.accentLight)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColor.glassBorder)
                .frame(height: 0.5)
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
                        termRow("Monthly", price: monthly.displayPrice + "/month")
                    }
                    if let annual = storeService.annualProduct {
                        termRow("Annual", price: annual.displayPrice + "/year")
                    }
                    if let lifetime = storeService.lifetimeProduct {
                        termRow("Lifetime", price: lifetime.displayPrice + " · one-time")
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
        .liquidGlassPresentation(detents: [.medium, .large])
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

    // MARK: - Helpers

    private var dataStoreHaptics: Bool {
        // We don't have DataStore in this view's environment in every callsite
        // (PaywallView ships from screens that may or may not inject it), so
        // default to enabled — UISelectionFeedbackGenerator is a no-op when
        // the system silences haptics (e.g. low-power mode).
        true
    }

    private var defaultSelection: String? {
        storeService.annualProduct?.id
            ?? storeService.monthlyProduct?.id
            ?? storeService.lifetimeProduct?.id
    }

    private var selectedProduct: Product? {
        guard let id = selectedProductID else { return nil }
        return storeService.products.first { $0.id == id }
    }

    private var ctaTitle: LocalizedStringKey {
        if isPurchasing { return "Working…" }
        guard let product = selectedProduct else { return "Choose a Plan" }

        // Free-trial wording wins when the selected tier is eligible — that's
        // the lowest-friction CTA. Otherwise show "Subscribe" with the price
        // baked in so the user knows what they're committing to.
        if product.id == StoreService.annualID,
           storeService.isEligibleForAnnualTrial,
           let display = storeService.annualTrialDisplay {
            return LocalizedStringKey("Start \(display) trial")
        }
        if product.id == StoreService.monthlyID,
           storeService.isEligibleForMonthlyTrial,
           let display = storeService.monthlyTrialDisplay {
            return LocalizedStringKey("Start \(display) trial")
        }
        if product.id == StoreService.lifetimeID {
            return LocalizedStringKey("Buy Lifetime — \(product.displayPrice)")
        }
        return LocalizedStringKey("Subscribe — \(product.displayPrice)\(priceSuffix(for: product))")
    }

    private func displayName(for product: Product) -> String {
        switch product.id {
        case StoreService.annualID: return "Annual"
        case StoreService.monthlyID: return "Monthly"
        case StoreService.lifetimeID: return "Lifetime"
        default: return product.displayName
        }
    }

    private func priceSuffix(for product: Product) -> String {
        switch product.id {
        case StoreService.annualID: "/year"
        case StoreService.monthlyID: "/month"
        default: ""
        }
    }

    private func perMonthEquivalent(for annual: Product) -> String? {
        let monthly = annual.price / 12
        // Use the StoreKit-provided format style so the currency symbol /
        // locale match the live product (e.g. "kr" in SE, "$" in US).
        let formatted = monthly.formatted(annual.priceFormatStyle)
        return "≈ \(formatted)/month, billed yearly"
    }

    private var annualSavingsBadge: LocalizedStringKey? {
        guard
            let monthly = storeService.monthlyProduct,
            let annual = storeService.annualProduct
        else { return nil }
        let yearAtMonthly = monthly.price * 12
        guard yearAtMonthly > 0 else { return nil }
        let savings = (yearAtMonthly - annual.price) / yearAtMonthly
        let percent = Int((savings as NSDecimalNumber).doubleValue * 100)
        return percent > 0 ? "Save \(percent)%" : nil
    }

    private var annualBadge: LocalizedStringKey? {
        if storeService.isEligibleForAnnualTrial,
           let display = storeService.annualTrialDisplay {
            return LocalizedStringKey(display)
        }
        return annualSavingsBadge
    }

    private var monthlyTrialBadge: LocalizedStringKey? {
        guard storeService.isEligibleForMonthlyTrial,
              let display = storeService.monthlyTrialDisplay else { return nil }
        return LocalizedStringKey(display)
    }
}

#Preview {
    PaywallView()
        .preferredColorScheme(.dark)
}
