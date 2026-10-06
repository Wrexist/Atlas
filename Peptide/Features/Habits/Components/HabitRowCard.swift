import SwiftUI

/// Full-width habit card matching the loggd.life layout — icon +
/// name + frequency badge on the header row, three stat chips
/// (streak / best / total), and the heatmap underneath. Tappable
/// surface advances to the habit detail.
struct HabitRowCard: View {
    let habit: Habit
    let summary: HabitsService.Summary
    let heatmapColumns: [[HabitsService.HeatmapStatus?]]
    let heatmapStart: Date?
    let onToggleToday: () -> Void
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var completionTrigger = 0

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                header
                statRow
                HabitHeatmap(
                    columns: heatmapColumns,
                    tint: habit.tint,
                    firstColumnStart: heatmapStart
                )
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .stroke(AppColor.glassBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(habit.name). \(summary.currentStreak) day streak, \(summary.totalCompletedDays) days total.")
        .accessibilityAddTraits(.isButton)
        .onChange(of: summary.isCompletedToday) { _, completed in
            if completed { completionTrigger &+= 1 }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            MilestoneArtwork(
                symbol: habit.iconSymbol,
                tint: habit.tint,
                size: 32,
                style: .symbol,
                trigger: completionTrigger,
                playsOnArrival: false
            )
            Text(habit.name)
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Spacing.sm)
            scheduleBadge
            todayButton
        }
    }

    private var scheduleBadge: some View {
        Text(habit.schedule.displayName)
            .font(AppFont.scaled(11, weight: .bold))
            .foregroundStyle(AppColor.accentLight)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(AppColor.accentPrimary.opacity(0.15))
            )
    }

    private var todayButton: some View {
        Button {
            Haptics.impact(.soft)
            withAnimation(AppAnimation.motionAware(AppAnimation.springSnappy, reduceMotion: reduceMotion)) { onToggleToday() }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(
                        summary.isCompletedToday ? habit.tint : AppColor.glassBorderActive,
                        lineWidth: 1.5
                    )
                    .frame(width: 28, height: 28)
                if summary.isCompletedToday {
                    Circle()
                        .fill(habit.tint)
                        .frame(width: 22, height: 22)
                    Image(systemName: "checkmark")
                        .font(AppFont.scaled(11, weight: .bold))
                        .foregroundStyle(AppColor.background)
                } else if summary.todayProgress > 0 {
                    Circle()
                        .trim(from: 0, to: summary.todayProgress)
                        .stroke(habit.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees(-90))
                }
            }
            // Grow the hit area to 44pt without growing the header row.
            .contentShape(Circle().inset(by: -(Spacing.minimumHitTarget - 28) / 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(summary.isCompletedToday ? "Completed today" : "Mark complete for today")
    }

    private var statRow: some View {
        HStack(spacing: Spacing.md) {
            statChip(icon: "flame.fill",       value: "\(summary.currentStreak)", label: "streak", tint: AppColor.perceivedEffort)
            statChip(icon: "trophy.fill",      value: "\(summary.bestStreak)",    label: "best",   tint: AppColor.achievement)
            statChip(icon: "checkmark.circle", value: "\(summary.totalCompletedDays)", label: "days", tint: AppColor.positive)
            Spacer(minLength: 0)
        }
    }

    private func statChip(icon: String, value: String, label: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .monospacedDigit()
                .contentTransition(.numericText())
                .font(AppFont.scaled(11, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
            Text(label)
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
        }
    }
}
