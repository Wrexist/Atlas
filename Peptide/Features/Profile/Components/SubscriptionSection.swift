import StoreKit
import SwiftUI

/// Subscription management for Pro members.
///
/// The app previously only ever told users to go to "Settings → Apple ID →
/// Subscriptions" in fine print, with no affordance anywhere in the UI —
/// which reads as a dark pattern even when it isn't. `manageSubscriptionsSheet`
/// presents Apple's own management UI in place, so upgrading, downgrading and
/// cancelling are all one tap from where the subscription is shown.
struct SubscriptionSection: View {
    @State private var storeService = StoreService.shared
    @State private var showManageSubscriptions = false
    @State private var isRestoring = false
    @State private var restoreError: String?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    Label("Subscription", systemImage: "crown.fill")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    ProBadge()
                    Spacer(minLength: 0)
                }

                Text(planCaption)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                GlassButton(
                    title: "Manage subscription",
                    icon: "creditcard",
                    style: .secondary,
                    isFullWidth: true
                ) {
                    showManageSubscriptions = true
                }

                GlassButton(
                    title: isRestoring ? "Restoring…" : "Restore purchases",
                    icon: "arrow.clockwise",
                    style: .ghost,
                    isFullWidth: true
                ) {
                    Task { await restore() }
                }
                .disabled(isRestoring)
            }
        }
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        .alert("Restore Failed", isPresented: Binding(
            get: { restoreError != nil },
            set: { if !$0 { restoreError = nil } }
        )) {
            Button("OK") { restoreError = nil }
        } message: {
            Text(restoreError ?? "")
        }
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await storeService.restorePurchases()
        } catch {
            restoreError = "Couldn't reach the App Store. Check your connection and try again."
        }
    }

    /// Lifetime buyers have nothing to renew, so they get a different line —
    /// showing them a renewal date they don't have was the App Store 3.1.2(a)
    /// wording problem flagged in the audit.
    private var planCaption: LocalizedStringKey {
        storeService.hasLifetimeAccess
            ? "You own Atlas Pro for life. Nothing renews and there's nothing to cancel."
            : "Change plan, or cancel any time. Cancelling keeps Pro active until the end of the period you've paid for."
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        SubscriptionSection()
            .padding(Spacing.screenPadding)
    }
}
