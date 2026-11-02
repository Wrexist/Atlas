import SwiftUI

/// The one headline treatment for every onboarding step after Welcome:
/// a 32pt rounded title over an optional subheadline, centred, with the
/// title marked as a header so VoiceOver's rotor lands on it. Welcome
/// keeps its own display size; every other step reads through this so
/// the flow doesn't jump between six title sizes and two alignments.
struct OnboardingHeader: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Text(title)
                .font(AppFont.scaled(32, weight: .light, relativeTo: .largeTitle))
                .foregroundStyle(AppColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }
}
