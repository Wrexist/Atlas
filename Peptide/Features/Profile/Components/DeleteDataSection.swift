import SwiftUI

/// The two irreversible actions — Delete account and Delete all data —
/// in their own card at the foot of Settings, away from Sign out and the
/// everyday toggles, so a slip of the thumb never lands on them.
struct DeleteDataSection: View {
    @State private var authService = AuthService.shared
    @State private var isConfirmingDeletion = false
    @State private var isConfirmingDataErase = false
    @State private var needsManualAppleRevoke = false
    @State private var isDeleting = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Label("Delete your data", systemImage: "exclamationmark.triangle.fill")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("These can't be undone.")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textTertiary)
                }

                if authService.isSignedIn {
                    GlassButton(title: "Delete account", icon: "trash.fill",
                                style: .destructive, isFullWidth: true) {
                        isConfirmingDeletion = true
                    }
                }

                // Shown to every user, guest or signed in — erasing your data
                // must not depend on having an account.
                GlassButton(title: "Delete all data", icon: "xmark.bin.fill",
                            style: .destructive, isFullWidth: true) {
                    isConfirmingDataErase = true
                }
            }
            .disabled(isDeleting)
        }
        .overlay {
            if isDeleting {
                deletingOverlay
            }
        }
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
        .alert("Delete all data?", isPresented: $isConfirmingDataErase) {
            Button("Delete all data", role: .destructive) {
                authService.deleteAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(dataEraseMessage)
        }
    }

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
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        DeleteDataSection()
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
