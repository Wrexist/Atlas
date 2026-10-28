import SwiftUI

/// The shown day's Health step count against the daily goal — a ring in
/// the hero trio's visual language beside "6 240 / 8 000 steps". Display
/// only: steps fill from Health, and the goal is edited in Profile.
struct TodayStepsCard: View {
    let steps: Double
    let goal: Int
    var isPastDay = false

    private var stepCount: Int { Int(steps) }
    private var progress: Double { StepGoalEngine.progress(steps: steps, goal: goal) }
    private var isMet: Bool { StepGoalEngine.isMet(steps: steps, goal: goal) }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HomeSectionHeader(eyebrow: "Movement", title: "Steps")

            GlassCard {
                HStack(spacing: Spacing.lg) {
                    MetricRing(
                        progress: progress,
                        diameter: 64,
                        strokeWidth: 7,
                        gradient: [AppColor.metricActivity, AppColor.accentLight],
                        celebrateAtCompletion: !isPastDay
                    ) {
                        Image(systemName: isMet ? "checkmark" : "figure.walk")
                            .font(AppFont.scaled(20, weight: .bold))
                            .foregroundStyle(isMet ? AppColor.accentPrimary : AppColor.textSecondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("\(stepCount.formatted()) / \(goal.formatted()) steps")
                            .font(AppFont.scaled(16, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColor.textPrimary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(caption)
                            .font(AppFont.caption2)
                            .foregroundStyle(isMet ? AppColor.accentPrimary : AppColor.textTertiary)
                    }

                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .appAnimation(AppAnimation.springSmooth, value: steps)
    }

    private var caption: String {
        if isMet { return String(localized: "Step goal reached") }
        let left = max(0, goal - stepCount)
        return isPastDay
            ? String(localized: "\(left.formatted()) short of the goal")
            : String(localized: "\(left.formatted()) to go")
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        TodayStepsCard(steps: 6_240, goal: 8_000)
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
