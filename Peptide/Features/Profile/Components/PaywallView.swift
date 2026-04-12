import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    private var storeService: StoreService { StoreService.shared }
    @State private var isPurchasing = false

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
                            .foregroundStyle(AppColor.textSecondary)
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
                                badge: "Save 40%",
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
                    }

                    // Restore
                    Button("Restore Purchases") {
                        Task { await storeService.restorePurchases() }
                    }
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)

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

    private func featureRow(icon: String, title: String, description: String) -> some View {
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
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
        }
    }

    private func pricingCard(product: Product, label: String, badge: String?, isBest: Bool) -> some View {
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

                        Text(product.displayPrice + (label == "Annual" ? "/year" : "/month"))
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
}

#Preview {
    PaywallView()
        .preferredColorScheme(.dark)
}
