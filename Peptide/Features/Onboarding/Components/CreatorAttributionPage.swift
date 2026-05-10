import SwiftUI

/// "Did a creator send you?" onboarding step. Captures a referral code,
/// validates it locally against `CreatorCodeService.seeded`, and surfaces
/// an inline success / error state. The OnboardingView owns the state +
/// footer buttons so the apply / skip / continue flow can be expressed in
/// the same place as every other step.
struct CreatorAttributionPage: View {
    @Binding var input: String
    let attribution: CreatorAttribution?
    let error: String?

    var body: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.sm) {
                Text("Did a creator send you?")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Enter their code to support them and unlock an exclusive offer.")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }

            if let attribution {
                successCard(attribution)
            } else {
                inputBlock
            }
        }
    }

    private var inputBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            GlassTextField(
                placeholder: "Enter creator code…",
                text: $input,
                icon: "person.text.rectangle"
            )
            .textInputAutocapitalization(.characters)
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

    private func successCard(_ attribution: CreatorAttribution) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppColor.accentPrimary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Code applied!")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(successMessage(for: attribution))
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.accentPrimary.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.accentPrimary.opacity(0.45), lineWidth: 1)
                }
        }
        .transition(.scale(scale: 0.94).combined(with: .opacity))
    }

    private func successMessage(for attribution: CreatorAttribution) -> String {
        "\(attribution.creatorName) gets credit + you get \(attribution.discountPercent)% off."
    }
}

#Preview("Idle") {
    StatefulPreviewWrapper(input: "")
}

#Preview("Success") {
    StatefulPreviewWrapper(
        input: "LUCAS50",
        attribution: CreatorCodeService.seeded.first
    )
}

#Preview("Error") {
    StatefulPreviewWrapper(
        input: "WRONG",
        error: "Code not found — double-check and try again"
    )
}

private struct StatefulPreviewWrapper: View {
    @State var input: String
    var attribution: CreatorAttribution? = nil
    var error: String? = nil

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()
            CreatorAttributionPage(
                input: $input,
                attribution: attribution,
                error: error
            )
            .padding(.horizontal, Spacing.screenPadding)
        }
        .preferredColorScheme(.dark)
    }
}
