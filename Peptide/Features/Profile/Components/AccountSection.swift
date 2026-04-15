import AuthenticationServices
import SwiftUI

struct AccountSection: View {
    @State private var authService = AuthService.shared

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
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Account", systemImage: "person.crop.circle.fill")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)

            Spacer()

            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(authService.isSignedIn ? AppColor.accentPrimary : AppColor.textTertiary)
                    .frame(width: 8, height: 8)

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
            + Text(" to enable ")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            + Text("cloud sync")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColor.accentLight)
            + Text(" across your devices. Your data stays ")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            + Text("private and encrypted")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColor.accentLight)
            + Text(".")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary))
                .lineSpacing(3)

            featurePreview

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                // onCompletion is @escaping @Sendable — hop to MainActor explicitly
                Task { @MainActor in
                    authService.handleAuthorization(result)
                }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.smallCornerRadius))

            Text("Optional — all features work without signing in")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Feature Preview

    private var featurePreview: some View {
        HStack(spacing: Spacing.md) {
            featureItem(icon: "icloud",                         label: "Cloud\nBackup")
            featureItem(icon: "arrow.triangle.2.circlepath",    label: "Multi-\nDevice")
            featureItem(icon: "lock.shield",                    label: "Encrypted\nSync")
        }
    }

    private func featureItem(icon: String, label: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(AppColor.accentLight)
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
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

            HStack(spacing: Spacing.md) {
                Image(systemName: "checkmark.icloud.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.accentPrimary)

                Text("Cloud sync ready")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)

                Spacer()

                Text("Coming soon")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xxs)
                    .background(AppColor.glassBorder.opacity(0.3))
                    .clipShape(Capsule())
            }

            Divider()
                .overlay(AppColor.glassBorder)

            GlassButton(title: "Sign Out", icon: "rectangle.portrait.and.arrow.right",
                        style: .destructive, isFullWidth: true) {
                authService.signOut()
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
