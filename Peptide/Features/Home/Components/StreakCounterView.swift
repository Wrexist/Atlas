import SwiftUI

struct StreakCounterView: View {
    let currentStreak: Int
    let bestStreak: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseTrigger = 0
    @State private var milestoneScale: CGFloat = 1.0

    /// Streaks where the user crosses a meaningful threshold. Used to gate
    /// the celebration pulse so a routine increment from 4→5 doesn't feel
    /// the same as crossing 7 (the first weekly milestone).
    private static let milestones: Set<Int> = [7, 14, 30, 60, 90, 180, 365]

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
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(flameColor)
                    .symbolEffect(.bounce, value: pulseTrigger)
                    .modifier(ConditionalGlow(active: showGlow))
                    .scaleEffect(milestoneScale)

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
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            } else if bestStreak > currentStreak && bestStreak > 0 {
                Text("Best: \(bestStreak) days")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceOverLabel)
        .onChange(of: currentStreak) { oldValue, newValue in
            pulseTrigger &+= 1
            guard !reduceMotion, newValue > oldValue, Self.milestones.contains(newValue) else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                milestoneScale = 1.18
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(380))
                withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
                    milestoneScale = 1.0
                }
            }
        }
    }

    private var voiceOverLabel: String {
        if currentStreak == 0 {
            return bestStreak > 0
                ? "No active streak. Best streak \(bestStreak) days."
                : "No active streak. Log a dose today to start one."
        }
        if isNewBest && currentStreak > 1 {
            return "\(currentStreak) day streak. New personal best."
        }
        if bestStreak > currentStreak {
            return "\(currentStreak) day streak. Best streak \(bestStreak) days."
        }
        return "\(currentStreak) day streak."
    }
}

private struct ConditionalGlow: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.appShadow(AppShadow.glassElevated)
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
