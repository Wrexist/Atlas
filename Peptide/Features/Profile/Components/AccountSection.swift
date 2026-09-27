import SwiftUI

struct AccountSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var authService = AuthService.shared
    @State private var isConfirmingDeletion = false
    @State private var isConfirmingDataErase = false
    @State private var cloudSyncState: CloudSyncState?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                syncStatusRow
                if authService.isSignedIn {
                    signedInContent
                } else {
                    signedOutContent
                }
                deleteAllDataButton
            }
        }
        .task { cloudSyncState = await SwiftDataRepository.shared.refinedCloudSyncState() }
        .alert("Delete Account?", isPresented: $isConfirmingDeletion) {
            Button("Delete Account", role: .destructive) {
                authService.deleteAccount()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the Apple ID linkage from this device and erases all your workouts, meals, protocols, dose entries, progress photos, and profile data. Data in Apple Health is not touched. If iCloud sync is on, the deletion propagates to your other devices. This cannot be undone.")
        }
        .alert("Delete All Data?", isPresented: $isConfirmingDataErase) {
            Button("Delete All Data", role: .destructive) {
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
                if authService.isSignedIn {
                    PulsatingDot(color: AppColor.accentPrimary, size: 8)
                } else {
                    Circle()
                        .fill(AppColor.textTertiary)
                        .frame(width: 8, height: 8)
                }

                Text(authService.isSignedIn ? "Signed In" : "Not Signed In")
                    .font(AppFont.caption)
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
                        .font(AppFont.caption)
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
            (Text("Sign in with your ")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            + Text("Apple ID")
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
            + Text(" to keep your Atlas account associated with your device. All your protocols, entries, and settings stay on this device.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary))
                .lineSpacing(3)

            ZStack {
                AppleSignInButton(cornerRadius: Spacing.smallCornerRadius) {
                    authService.signIn()
                }
                .frame(height: 50)
                .opacity(authService.isSigningIn ? 0.5 : 1)
                .allowsHitTesting(!authService.isSigningIn)
                // The button's style is baked in at init; re-identify it so
                // SwiftUI rebuilds the UIView when the scheme flips.
                .id(colorScheme)

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
                .font(AppFont.caption)
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

            GlassButton(title: "Sign Out", icon: "rectangle.portrait.and.arrow.right",
                        style: .secondary, isFullWidth: true) {
                authService.signOut()
            }

            GlassButton(title: "Delete Account", icon: "trash.fill",
                        style: .destructive, isFullWidth: true) {
                isConfirmingDeletion = true
            }
        }
    }

    // MARK: - Delete All Data

    /// Shown to every user, guest or signed in — erasing your data must
    /// not depend on having an account.
    private var deleteAllDataButton: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Divider()
                .overlay(AppColor.glassBorder)

            GlassButton(title: "Delete All Data", icon: "xmark.bin.fill",
                        style: .destructive, isFullWidth: true) {
                isConfirmingDataErase = true
            }
        }
    }

    private var dataEraseMessage: String {
        let erase = String(localized: "This permanently erases all your workouts, meals, protocols, dose entries, progress photos, and profile data from this device. Data in Apple Health is not touched. If iCloud sync is on, the copies in your iCloud are removed too.")
        let signOut = authService.isSignedIn ? " " + String(localized: "You will also be signed out.") : ""
        return erase + signOut + " " + String(localized: "This cannot be undone.")
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
