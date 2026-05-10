import SwiftUI

/// "Never miss a protocol update." onboarding step. Captures an email
/// address and validates it client-side; the OnboardingView owns the
/// state + footer buttons so submit / skip / advance live in one place.
///
/// Backend wiring (Supabase email_subscribers insert, Resend welcome
/// email, 7-day pg_cron retargeting) doesn't ship in this PR — there's
/// no Supabase client in the app today. The captured address is stored
/// on the profile so the eventual sync job can replay it 1:1.
struct EmailCapturePage: View {
    @Binding var input: String
    let error: String?

    var body: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.sm) {
                Text("Never miss a protocol update.")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Drop your email for new compound profiles and exclusive Pro offers. No spam.")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                GlassTextField(
                    placeholder: "your@email.com",
                    text: $input,
                    icon: "envelope.fill"
                )
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .submitLabel(.done)

                if let error {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(error)
                            .font(AppFont.caption)
                    }
                    .foregroundStyle(AppColor.destructive)
                    .padding(.leading, Spacing.md)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}

extension String {
    /// Lightweight email format check — matches `local@domain.tld` shapes
    /// without trying to fully implement RFC 5322. The intent is to catch
    /// typos like a missing `@` or trailing dot, not to reject every
    /// pathological-but-technically-valid address.
    var looksLikeEmail: Bool {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}

#Preview("Idle") {
    StatefulPreviewWrapper(input: "")
}

#Preview("Error") {
    StatefulPreviewWrapper(input: "not-an-email", error: "That doesn't look like an email address.")
}

private struct StatefulPreviewWrapper: View {
    @State var input: String
    var error: String? = nil

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()
            EmailCapturePage(input: $input, error: error)
                .padding(.horizontal, Spacing.screenPadding)
        }
        .preferredColorScheme(.dark)
    }
}
