import SwiftUI

/// One-time disclosure shown before anything the user submits leaves the
/// device for a third-party AI (App Store Guideline 5.1.2(i)). "Allow"
/// records consent in `AIDataConsent`; "Not now" and swipe-down both leave
/// it unset. Presenters check `AIDataConsent.isGranted` in the sheet's
/// `onDismiss` to decide whether to carry on with the request.
///
/// Copy is deliberately limited to what Atlas controls — no claim about how
/// long Anthropic keeps a request.
struct AIConsentSheet: View {
    /// What this feature sends, in the user's terms — "Your messages in
    /// this chat", "The meal photo you take or pick".
    let whatIsSent: LocalizedStringKey

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Spacing.lg) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        ConsentRow(icon: "arrow.up.doc", text: whatIsSent)
                        ConsentRow(
                            icon: "server.rack",
                            text: "Goes to Claude, an AI model made by Anthropic, through Atlas's server."
                        )
                        ConsentRow(
                            icon: "checkmark.shield",
                            text: "Used only to answer your request. Atlas holds no account for you and never sells your data."
                        )
                        ConsentRow(
                            icon: "hand.raised",
                            text: "Nothing is sent until you allow it. You can turn this off in Profile › About › Privacy at a glance."
                        )
                    }

                    Link(destination: URL.staticHTTPS("https://wrexist.github.io/Peptide-ai/privacy.html")) {
                        Text("Privacy Policy").minimumHitArea()
                    }
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.accentLight)
                }
                .padding(.top, Spacing.xl)
            }

            VStack(spacing: Spacing.sm) {
                PrimaryCTAButton(title: "Allow") {
                    AIDataConsent.grant()
                    dismiss()
                }
                GlassButton(title: "Not now", style: .ghost, isFullWidth: true) {
                    dismiss()
                }
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.bottom, Spacing.lg)
        .background(AppColor.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Image(systemName: "sparkles")
                .font(AppFont.scaled(24, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .accessibilityHidden(true)
            Text("Share with an AI service?")
                .font(AppFont.title2)
                .foregroundStyle(AppColor.textPrimary)
            Text("This feature uses a third-party AI to answer you.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ConsentRow: View {
    let icon: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(AppColor.accentPrimary)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            AIConsentSheet(whatIsSent: "Your messages in this chat, including earlier ones in the conversation.")
                .liquidGlassPresentation()
        }
        .preferredColorScheme(.dark)
}
