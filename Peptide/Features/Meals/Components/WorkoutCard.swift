import SwiftUI

/// Single-row summary of today's training sessions; tapping opens Train.
struct WorkoutCard: View {
    let sessionCountToday: Int
    let durationMinutesToday: Int
    let onTap: () -> Void
    /// A browsed past day: an empty day reads as a record, not a prompt.
    var isPastDay = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                IconTile("dumbbell.fill", size: 40)
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
            return isPastDay ? String(localized: "No training logged") : String(localized: "Log today's training")
        }
        let sessionLabel = String(AttributedString(localized: "^[\(sessionCountToday) workout](inflect: true)").characters)
        if durationMinutesToday <= 0 {
            return sessionLabel
        }
        return String(localized: "\(sessionLabel) · \(durationMinutesToday) min",
                      comment: "Workout card subtitle: session count, then total minutes.")
    }
}
