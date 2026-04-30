import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var storeService = StoreService.shared
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    // Hero
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AppColor.accentLight, AppColor.accentPrimary],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        Text("PeptideX Pro")
                            .font(AppFont.largeTitle)
                            .foregroundStyle(AppColor.textPrimary)

                        Text("Unlock the full potential of your protocols")
                            .font(AppFont.body)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AppColor.accentLight, AppColor.textSecondary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, Spacing.xxl)

                    // Features
                    GlassCard {
                        VStack(alignment: .leading, spacing: Spacing.lg) {
                            featureRow(icon: "infinity", title: "Unlimited Protocols", description: "Create as many protocols as you need")
                            featureRow(icon: "chart.xyaxis.line", title: "Full Analytics", description: "All time ranges, HealthKit correlation, export")
                            featureRow(icon: "brain.head.profile.fill", title: "AI Insights", description: "Smart recommendations and research assistant")
                            featureRow(icon: "icloud.fill", title: "Cloud Sync", description: "Backup and sync across devices")
                            featureRow(icon: "square.grid.2x2.fill", title: "All Widgets", description: "Every widget type + Apple Watch")
                            featureRow(icon: "square.and.arrow.up", title: "Data Export", description: "CSV reports and JSON backups")
                        }
                    }

                    // Pricing
                    VStack(spacing: Spacing.md) {
                        if let annual = storeService.annualProduct {
                            pricingCard(
                                product: annual,
                                label: "Annual",
                                badge: annualSavingsBadge,
                                isBest: true
                            )
                        }

                        if let monthly = storeService.monthlyProduct {
                            pricingCard(
                                product: monthly,
                                label: "Monthly",
                                badge: nil,
                                isBest: false
                            )
                        }

                        if let lifetime = storeService.lifetimeProduct {
                            pricingCard(
                                product: lifetime,
                                label: "Lifetime",
                                badge: "One-Time",
                                isBest: false
                            )
                        }
                    }

                    // Restore
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

                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.destructive)
                            .multilineTextAlignment(.center)
                    }

                    // Legal
                    Text("Payment will be charged to your Apple ID. Subscription auto-renews unless cancelled at least 24 hours before the end of the current period.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
            }
            .background(AppColor.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .task { await storeService.loadProducts() }
        }
    }

    private func featureRow(icon: String, title: LocalizedStringKey, description: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(AppColor.accentLight)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(AppColor.accentPrimary.opacity(0.15))
                }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(AppFont.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(AppColor.textPrimary)
                Text(description)
                    .font(AppFont.caption)
                    .foregroundStyle(Color(hex: 0xB0B0B0))
            }
            Spacer()
        }
    }

    private func pricingCard(product: Product, label: LocalizedStringKey, badge: LocalizedStringKey?, isBest: Bool) -> some View {
        Button {
            Task {
                isPurchasing = true
                _ = try? await storeService.purchase(product)
                isPurchasing = false
                if storeService.isProUser { dismiss() }
            }
        } label: {
            GlassCard(tinted: isBest) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        HStack(spacing: Spacing.sm) {
                            Text(label)
                                .font(AppFont.headline)
                                .foregroundStyle(AppColor.textPrimary)

                            if let badge {
                                Text(badge)
                                    .font(AppFont.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(AppColor.accentLight)
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, Spacing.xxs)
                                    .background {
                                        Capsule()
                                            .fill(AppColor.accentPrimary.opacity(0.2))
                                    }
                            }
                        }

                        Text(product.displayPrice + priceSuffix(for: product))
                            .font(AppFont.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    Spacer()

                    if isBest {
                        Text("Best Value")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.accentLight)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
    }

    private func priceSuffix(for product: Product) -> String {
        switch product.id {
        case StoreService.annualID: "/year"
        case StoreService.monthlyID: "/month"
        default: ""
        }
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
}

#Preview {
    PaywallView()
        .preferredColorScheme(.dark)
}
