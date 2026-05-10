import SwiftUI

struct WelcomeFeatureBadge: View {
    let icon: String
    let label: LocalizedStringKey
    var animationDelay: Double = 0

    @State private var didAppear = false

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(AppColor.glassTint)
                        .overlay {
                            Circle().strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                        }
                }
                .liquidGlass(.circle)
                .symbolEffect(.bounce, value: didAppear)
                .shadow(color: AppColor.accentPrimary.opacity(didAppear ? 0.35 : 0), radius: 10, y: 2)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 16)
        .scaleEffect(didAppear ? 1 : 0.85)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(animationDelay)) {
                didAppear = true
            }
        }
    }
}
