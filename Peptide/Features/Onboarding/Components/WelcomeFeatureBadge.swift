import SwiftUI

struct WelcomeFeatureBadge: View {
    let icon: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .frame(width: 40, height: 40)
                .background {
                    Circle()
                        .fill(AppColor.glassTint)
                        .overlay {
                            Circle().strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                        }
                }

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}
