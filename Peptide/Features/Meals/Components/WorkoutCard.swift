import SwiftUI

/// Single-row summary of today's training sessions; tapping opens Train.
struct WorkoutCard: View {
    let sessionCountToday: Int
    let durationMinutesToday: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "dumbbell.fill")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.accentLight)
                    .frame(width: 40, height: 40)
                    .background {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .fill(AppColor.accentPrimary.opacity(0.18))
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's training")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11, weight: .bold))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassControl(.rect(cornerRadius: Spacing.cardCornerRadius))
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityHint("Opens Train")
    }

    private var subtitle: String {
        if sessionCountToday == 0 {
            return "Log today's training"
        }
        let sessionLabel = sessionCountToday == 1 ? "1 workout" : "\(sessionCountToday) workouts"
        if durationMinutesToday <= 0 {
            return sessionLabel
        }
        return "\(sessionLabel) · \(durationMinutesToday) min"
    }
}
