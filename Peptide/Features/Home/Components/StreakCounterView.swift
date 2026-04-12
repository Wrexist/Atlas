import SwiftUI

struct StreakCounterView: View {
    let currentStreak: Int
    let bestStreak: Int

    private var flameColor: Color {
        switch currentStreak {
        case 0: return AppColor.textTertiary
        case 1...6: return AppColor.accentPrimary
        case 7...13: return AppColor.accentLight
        default: return AppColor.warning
        }
    }

    private var showGlow: Bool {
        currentStreak >= 7
    }

    private var isNewBest: Bool {
        currentStreak > 0 && currentStreak >= bestStreak
    }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(flameColor)
                    .symbolEffect(.bounce, value: currentStreak)
                    .modifier(ConditionalGlow(active: showGlow))

                if currentStreak > 0 {
                    Text("\(currentStreak)")
                        .font(AppFont.title2)
                        .foregroundStyle(AppColor.textPrimary)
                        .contentTransition(.numericText())

                    Text("day streak")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                } else {
                    Text("Start your streak!")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textTertiary)
                }
            }

            if isNewBest && currentStreak > 1 {
                Text("New personal best!")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.accentLight)
            } else if bestStreak > currentStreak && bestStreak > 0 {
                Text("Best: \(bestStreak) days")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
    }
}

private struct ConditionalGlow: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.appShadow(AppShadow.accentGlow)
        } else {
            content
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        VStack(spacing: Spacing.xxxl) {
            StreakCounterView(currentStreak: 12, bestStreak: 18)
            StreakCounterView(currentStreak: 12, bestStreak: 12)
            StreakCounterView(currentStreak: 0, bestStreak: 5)
            StreakCounterView(currentStreak: 3, bestStreak: 3)
        }
    }
    .preferredColorScheme(.dark)
}
