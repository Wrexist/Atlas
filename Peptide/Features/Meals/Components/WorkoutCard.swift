import SwiftUI

/// Single-row summary of the shown day's training sessions; on today,
/// tapping opens Train. It is Today's one answer to "did I train?": a
/// logged workout or a planned rest day reads as done, so the daily
/// checklist leaves its training row out while this card shows.
struct WorkoutCard: View {
    let sessionCountToday: Int
    let durationMinutesToday: Int
    /// False on a planned rest day, which turns the empty state from a
    /// prompt into a done rest day.
    var isTrainingDay = true
    /// Nil on a browsed past day, which is a read-only record.
    var onTap: (() -> Void)?
    /// A browsed past day: an empty day reads as a record, not a prompt.
    var isPastDay = false

    var body: some View {
        if let onTap {
            Button(action: onTap) {
                row(showsChevron: true)
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.98))
            .accessibilityHint("Opens Train")
        } else {
            row(showsChevron: false)
                .accessibilityElement(children: .combine)
        }
    }

    private func row(showsChevron: Bool) -> some View {
        HStack(spacing: Spacing.md) {
            IconTile(isRestDay ? "bed.double.fill" : "dumbbell.fill", size: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(subtitle)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer(minLength: 0)

            if isDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Done")
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11, weight: .bold))
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassControl(.rect(cornerRadius: Spacing.cardCornerRadius))
        .appAnimation(AppAnimation.springSmooth, value: isDone)
    }

    /// A logged workout, or a planned rest day — the same rule the
    /// checklist's training row used.
    private var isDone: Bool {
        sessionCountToday > 0 || isRestDay
    }

    private var isRestDay: Bool {
        sessionCountToday == 0 && !isTrainingDay
    }

    private var title: LocalizedStringKey {
        if isRestDay { return "Rest day" }
        return isPastDay ? "Workouts" : "Today's training"
    }

    private var subtitle: String {
        if isRestDay { return String(localized: "Recovery counts too") }
        if sessionCountToday == 0 {
            return isPastDay
                ? String(localized: "No training logged")
                : String(localized: "On the plan today — tap to start")
        }
        let sessionLabel = String(AttributedString(localized: "^[\(sessionCountToday) workout](inflect: true)").characters)
        if durationMinutesToday <= 0 {
            return sessionLabel
        }
        return String(localized: "\(sessionLabel) · \(durationMinutesToday) min",
                      comment: "Workout card subtitle: session count, then total minutes.")
    }
}
