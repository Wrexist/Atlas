import SwiftUI

struct AchievementToastView: View {
    let achievement: Achievement
    @Binding var isShowing: Bool

    var body: some View {
        if isShowing {
            VStack {
                HStack(spacing: Spacing.md) {
                    Image(systemName: achievement.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(AppColor.accentLight)
                        .frame(width: 40, height: 40)
                        .background {
                            Circle()
                                .fill(AppColor.accentPrimary.opacity(0.2))
                        }

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Achievement Unlocked!")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.accentLight)
                        Text(achievement.title)
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                    }

                    Spacer()

                    Button {
                        withAnimation(AppAnimation.springSnappy) { isShowing = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }
                .padding(Spacing.lg)
                .background {
                    RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                        .fill(AppColor.surfaceSecondary.opacity(0.95))
                        .overlay {
                            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                                .strokeBorder(AppColor.glassBorderActive, lineWidth: 0.5)
                        }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .transition(.move(edge: .top).combined(with: .opacity))

                Spacer()
            }
            .padding(.top, Spacing.sm)
            .task {
                try? await Task.sleep(for: .seconds(4))
                withAnimation(AppAnimation.springSmooth) { isShowing = false }
            }
        }
    }
}
