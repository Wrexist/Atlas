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
    @State private var restoreState = RestoreState.idle
    @State private var restoreError: String?

    private enum RestoreState: Equatable {
        case idle, restoring, restored
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    Label("Subscription", systemImage: "crown.fill")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    if storeService.isProUser {
                        ProBadge()
                    }
                    Spacer(minLength: 0)
                }

                if storeService.isInBillingRetry && !storeService.hasLifetimeAccess {
                    billingRetryBanner
                }

                Text(planCaption)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if hasSubscriptionToManage {
                    GlassButton(
                        title: "Manage subscription",
                        icon: "creditcard",
                        style: .secondary,
                        isFullWidth: true
                    ) {
                        showManageSubscriptions = true
                    }
                }

                restoreControl
                    .appAnimation(AppAnimation.fadeIn, value: restoreState)
            }
        }
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        .alert("Restore didn't go through", isPresented: Binding(
            get: { restoreError != nil },
            set: { if !$0 { restoreError = nil } }
        )) {
            Button("OK") { restoreError = nil }
        } message: {
            Text(restoreError ?? "")
        }
    }

    /// A restore that succeeds changes nothing visible for someone who is
    /// already Pro, so it says so rather than silently resetting.
    @ViewBuilder
    private var restoreControl: some View {
        switch restoreState {
        case .idle:
            GlassButton(
                title: "Restore purchases",
                icon: "arrow.clockwise",
                style: .ghost,
                isFullWidth: true
            ) {
                Task { await restore() }
            }
            .transition(.opacity)
        case .restoring:
            HStack(spacing: Spacing.sm) {
                ProgressView()
                Text("Restoring…")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: Spacing.minimumHitTarget)
            .accessibilityElement(children: .combine)
            .transition(.opacity)
        case .restored:
            Label("Purchases restored", systemImage: "checkmark.circle.fill")
                .font(AppFont.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.positive)
                .frame(maxWidth: .infinity, minHeight: Spacing.minimumHitTarget)
                .transition(.opacity)
        }
    }

    /// Apple is retrying a failed renewal. Telling the user — and putting the
    /// fix one tap away — is Apple's own recommendation for billing retry;
    /// left silent, the subscription lapses on a card they'd have updated.
    private var billingRetryBanner: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label {
                Text("Your payment didn't go through. Update your payment method to keep Atlas Pro.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColor.warning)
            }

            GlassButton(
                title: "Update payment method",
                icon: "creditcard",
                style: .primary,
                isFullWidth: true
            ) {
                showManageSubscriptions = true
            }
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(
                cornerRadius: Spacing.concentric(in: Spacing.cardCornerRadius, inset: Spacing.cardPadding),
                style: .continuous
            )
            .fill(AppColor.warning.opacity(0.12))
        }
    }

    private func restore() async {
        restoreState = .restoring
        do {
            guard try await storeService.restorePurchases() == .completed else {
                restoreState = .idle
                return
            }
        } catch {
            restoreState = .idle
            restoreError = "Couldn't reach the App Store. Check your connection and try again."
            return
        }
        Haptics.success()
        restoreState = .restored
        try? await Task.sleep(for: .seconds(2))
        restoreState = .idle
    }

    /// A lifetime owner who bought while a monthly or annual plan was live
    /// still has that plan renewing, and Manage subscription is the only
    /// in-app route to cancel it.
    private var hasLiveSubscription: Bool {
        !storeService.purchasedProductIDs.isDisjoint(with: [StoreService.monthlyID, StoreService.annualID])
    }

    private var hasSubscriptionToManage: Bool {
        !storeService.hasLifetimeAccess || hasLiveSubscription
    }

    /// Lifetime buyers have nothing to renew, so they get a different line —
    /// showing them a renewal date they don't have was the App Store 3.1.2(a)
    /// wording problem flagged in the audit. Past the grace period, billing
    /// retry has already removed Pro, so the caption says it is paused.
    private var planCaption: LocalizedStringKey {
        if storeService.hasLifetimeAccess {
            return hasLiveSubscription
                ? "You own Atlas Pro for life. Your subscription still renews, so cancel it to stop being charged."
                : "You own Atlas Pro for life. Nothing renews and there's nothing to cancel."
        }
        if !storeService.isProUser {
            return "Atlas Pro is paused until your payment goes through."
        }
        return "Change plan, or cancel anytime. Cancelling keeps Pro active until the end of the period you've paid for."
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        SubscriptionSection()
            .padding(Spacing.screenPadding)
    }
}
