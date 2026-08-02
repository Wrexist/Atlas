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
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColor.accentPrimary.opacity(0.35),
                                    AppColor.accentLight.opacity(0.20),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    Image(systemName: "dumbbell.fill")
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                }
                .shadow(color: AppColor.accentPrimary.opacity(0.25), radius: 6, y: 3)

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
                    .font(AppFont.scaled(11, weight: .bold))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassControl(.rect(cornerRadius: Spacing.cardCornerRadius))
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
