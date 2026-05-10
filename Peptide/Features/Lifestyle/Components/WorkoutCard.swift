import SwiftUI

/// Single-row card linking out to the workout-tracker drill-in. The
/// drill-in itself is a stub in this iteration — the card surface and
/// affordance are spec'd, the in-depth gym-log experience is tracked
/// as a separate work item.
struct WorkoutCard: View {
    let exerciseCountToday: Int
    let durationMinutesToday: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: 36, height: 36)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(AppColor.accentPrimary.opacity(0.15))
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout Tracker")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.6))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
    }

    private var subtitle: String {
        if exerciseCountToday == 0 {
            return "Log today's training"
        }
        let exerciseLabel = exerciseCountToday == 1 ? "1 exercise" : "\(exerciseCountToday) exercises"
        if durationMinutesToday <= 0 {
            return exerciseLabel
        }
        return "\(exerciseLabel) · \(durationMinutesToday) min"
    }
}
