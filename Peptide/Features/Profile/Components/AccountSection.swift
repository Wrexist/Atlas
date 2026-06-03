import SwiftUI

struct AccountSection: View {
    @State private var authService = AuthService.shared
    @State private var isConfirmingDeletion = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                if authService.isSignedIn {
                    signedInContent
                } else {
                    signedOutContent
                }
            }
        }
        .alert("Delete Account?", isPresented: $isConfirmingDeletion) {
            Button("Delete Account", role: .destructive) {
                authService.deleteAccount()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the Apple ID linkage from this device and erases all your protocols, dose entries, and profile data. If iCloud sync is on, the deletion propagates to your other devices. This cannot be undone.")
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

    // MARK: - Signed Out

    private var signedOutContent: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            (Text("Sign in with your ")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            + Text("Apple ID")
                .font(.system(size: 15, weight: .medium))
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

                if authService.isSigningIn {
                    HStack(spacing: Spacing.sm) {
                        ProgressView().tint(.black)
                        Text("Signing in…")
                            .font(AppFont.subheadline)
                            .foregroundStyle(.black)
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

    // MARK: - Helpers

    private func accountRow(icon: String, label: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14))
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
