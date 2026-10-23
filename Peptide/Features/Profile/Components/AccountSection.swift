import SwiftUI

struct AccountSection: View {
    @State private var authService = AuthService.shared
    @State private var isConfirmingDeletion = false
    @State private var isConfirmingDataErase = false
    @State private var needsManualAppleRevoke = false
    @State private var isConfirmingSignOut = false
    @State private var isDeleting = false
    @State private var cloudSyncState: CloudSyncState?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                syncStatusRow
                Group {
                    if authService.isSignedIn {
                        signedInContent
                    } else {
                        signedOutContent
                    }
                }
                .transition(.opacity)
                .appAnimation(AppAnimation.springSmooth, value: authService.isSignedIn)
                deleteAllDataButton
            }
            .disabled(isDeleting)
        }
        .overlay {
            if isDeleting {
                deletingOverlay
            }
        }
        .task { cloudSyncState = await SwiftDataRepository.shared.refinedCloudSyncState() }
        .alert("Delete account?", isPresented: $isConfirmingDeletion) {
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteAccountMessage)
        }
        .alert("Account deleted", isPresented: $needsManualAppleRevoke) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your data is erased. To finish, remove Atlas in Settings → your name → Sign-In & Security → Sign in with Apple.")
        }
        .confirmationDialog("Sign out?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Haptics.impact(.medium)
                authService.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your data stays on this device.")
        }
        .alert("Delete all data?", isPresented: $isConfirmingDataErase) {
            Button("Delete all data", role: .destructive) {
                authService.deleteAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(dataEraseMessage)
        }
        .alert(
            authService.lastError?.title ?? "",
            isPresented: Binding(
                get: { authService.lastError != nil },
                set: { if !$0 { authService.clearLastError() } }
            ),
            presenting: authService.lastError
        ) { _ in
            Button("Try Again") {
                authService.clearLastError()
                authService.signIn()
            }
            Button("Dismiss", role: .cancel) {
                authService.clearLastError()
            }
        } message: { error in
            Text(error.message)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Account", systemImage: "person.crop.circle.fill")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)

            Spacer()

            HStack(spacing: Spacing.xs) {
                // Signed in is a static fact, not live activity — no pulse.
                Circle()
                    .fill(authService.isSignedIn ? AppColor.accentPrimary : AppColor.textTertiary)
                    .frame(width: 8, height: 8)

                Text(authService.isSignedIn ? "Signed in" : "Not signed in")
                    .font(AppFont.caption2)
                    .foregroundStyle(authService.isSignedIn ? AppColor.accentLight : AppColor.textTertiary)
            }
        }
    }

    // MARK: - iCloud sync status

    /// Passive iCloud sync indicator (audit 3.1). Reflects whether
    /// the SwiftData store actually opened CloudKit-backed, refined
    /// by CKAccountStatus so "no account" reads differently from a
    /// real failure. Driven by the repository, not AuthService —
    /// Sign in with Apple and iCloud sync are independent.
    @ViewBuilder
    private var syncStatusRow: some View {
        if let state = cloudSyncState {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: state == .active ? "icloud.fill" : "icloud.slash.fill")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(state == .active ? AppColor.accentLight : AppColor.textTertiary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud Sync")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(syncCaption(for: state))
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func syncCaption(for state: CloudSyncState) -> String {
        switch state {
        case .active:
            return String(localized: "On — syncing through your private iCloud database.")
        case .noAccount:
            return String(localized: "Off — sign in to iCloud in Settings to sync across devices.")
        case .restricted:
            return String(localized: "Unavailable — iCloud is restricted on this device.")
        case .unavailable:
            return String(localized: "Unavailable right now — your data stays safe on this device.")
        }
    }

    // MARK: - Signed Out

    private var signedOutContent: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            ZStack {
                AppleSignInButton {
                    authService.signIn()
                }
                .frame(height: 50)
                .opacity(authService.isSigningIn ? 0.5 : 1)
                .allowsHitTesting(!authService.isSigningIn)

                if authService.isSigningIn {
                    // The in-flight label sits on top of the Apple button,
                    // which is white in dark mode and black in light mode —
                    // so the ink is the inverse of the app's normal ink.
                    HStack(spacing: Spacing.sm) {
                        ProgressView().tint(AppColor.background)
                        Text("Signing in…")
                            .font(AppFont.subheadline)
                            .foregroundStyle(AppColor.background)
                    }
                    .allowsHitTesting(false)
                }
            }

            Text("Optional — all features work without signing in")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Signed In

    private var signedInContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let email = authService.userEmail {
                accountRow(icon: "envelope.fill", label: email)
            }

            if let name = authService.userDisplayName {
                accountRow(icon: "person.fill", label: name)
            }

            Divider()
                .overlay(AppColor.glassBorder)

            GlassButton(title: "Sign out", icon: "rectangle.portrait.and.arrow.right",
                        style: .secondary, isFullWidth: true) {
                isConfirmingSignOut = true
            }

            GlassButton(title: "Delete account", icon: "trash.fill",
                        style: .destructive, isFullWidth: true) {
                isConfirmingDeletion = true
            }
        }
    }

    // MARK: - Account deletion

    /// Covers the card while the revoke round-trip runs, so the wait reads
    /// as work in progress rather than a dead tap.
    private var deletingOverlay: some View {
        HStack(spacing: Spacing.sm) {
            ProgressView()
            Text("Deleting…")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            AppColor.background.opacity(0.7),
            in: RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private func deleteAccount() async {
        isDeleting = true
        let outcome = await authService.deleteAccountRevokingApple()
        isDeleting = false
        switch outcome {
        case .deleted: Haptics.success()
        case .deletedRevokeManually: needsManualAppleRevoke = true
        case .cancelled: break
        }
    }

    // MARK: - Delete All Data

    /// Shown to every user, guest or signed in — erasing your data must
    /// not depend on having an account.
    private var deleteAllDataButton: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Divider()
                .overlay(AppColor.glassBorder)

            GlassButton(title: "Delete all data", icon: "xmark.bin.fill",
                        style: .destructive, isFullWidth: true) {
                isConfirmingDataErase = true
            }
        }
    }

    private var dataEraseMessage: String {
        let erase = String(localized: "This permanently erases all your workouts, meals, protocols, dose entries, progress photos, and profile data from this device. Data in Apple Health is not touched. If iCloud sync is on, the copies in your iCloud are removed too.")
        let signOut = authService.isSignedIn ? " " + String(localized: "You will also be signed out.") : ""
        return erase + signOut + " " + String(localized: "This cannot be undone.") + subscriptionNotice
    }

    private var deleteAccountMessage: String {
        String(localized: "This permanently removes the Apple Account link from this device and erases all your workouts, meals, protocols, dose entries, progress photos, and profile data. Data in Apple Health is not touched. If iCloud sync is on, the deletion propagates to your other devices. This cannot be undone.")
            + subscriptionNotice
    }

    /// Erasing data doesn't cancel an App Store subscription.
    private var subscriptionNotice: String {
        guard StoreService.shared.hasAutoRenewingSubscription else { return "" }
        return " " + String(localized: "Your Atlas Pro subscription is billed by Apple and keeps renewing until you cancel it in Settings → your name → Subscriptions.")
    }

    // MARK: - Helpers

    private func accountRow(icon: String, label: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(AppFont.scaled(13))
                .foregroundStyle(AppColor.textTertiary)
                .frame(width: 20)

            Text(label)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textPrimary)
        }
    }
}

#Preview("Signed Out") {
    ZStack {
        AppColor.background.ignoresSafeArea()
        AccountSection()
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
