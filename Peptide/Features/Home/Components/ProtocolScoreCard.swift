import SwiftUI

struct ProtocolScoreCard: View {
    let score: Double
    let completed: Int
    let total: Int
    let streak: Int
    let bestStreak: Int
    let weeklyCompletion: [WeekDayStatus]

    var body: some View {
        GlassCard(tinted: true) {
            VStack(spacing: Spacing.lg) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("PROTOCOL SCORE")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .tracking(1.5)

                        Text("Today's Progress")
                            .font(AppFont.headline)
                            .foregroundStyle(AppColor.textPrimary)
                    }

                    Spacer()

                    Text("\(completed)/\(total)")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }

                GlassProgressRing(progress: score, size: 180, lineWidth: 14)
                    .frame(height: 180)

                StreakCounterView(currentStreak: streak, bestStreak: bestStreak)

                WeeklyProgressCircles(days: weeklyCompletion)
                    .padding(.horizontal, Spacing.sm)
            }
        }
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        ProtocolScoreCard(
            score: 0.5,
            completed: 2,
            total: 4,
            streak: 12,
            bestStreak: 18,
            weeklyCompletion: [
                WeekDayStatus(id: 1, dayLabel: "Mon", status: .completed),
                WeekDayStatus(id: 2, dayLabel: "Tue", status: .completed),
                WeekDayStatus(id: 3, dayLabel: "Wed", status: .partial),
                WeekDayStatus(id: 4, dayLabel: "Thu", status: .missed),
                WeekDayStatus(id: 5, dayLabel: "Fri", status: .today),
                WeekDayStatus(id: 6, dayLabel: "Sat", status: .future),
                WeekDayStatus(id: 7, dayLabel: "Sun", status: .noSchedule),
            ]
        )
        .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
