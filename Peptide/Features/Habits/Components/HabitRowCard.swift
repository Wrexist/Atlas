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
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(habit.tint.opacity(0.18))
                    .frame(width: 28, height: 28)
                Image(systemName: habit.iconSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(habit.tint)
            }
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
            .font(.system(size: 11, weight: .bold))
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
            withAnimation(AppAnimation.springSnappy) { onToggleToday() }
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
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColor.background)
                } else if summary.todayProgress > 0 {
                    Circle()
                        .trim(from: 0, to: summary.todayProgress)
                        .stroke(habit.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees(-90))
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(summary.isCompletedToday ? "Completed today" : "Mark complete for today")
    }

    private var statRow: some View {
        HStack(spacing: Spacing.md) {
            statChip(icon: "flame.fill",       value: "\(summary.currentStreak)", label: "streak", tint: Color(hex: 0xFFB347))
            statChip(icon: "trophy.fill",      value: "\(summary.bestStreak)",    label: "best",   tint: Color(hex: 0xD4A844))
            statChip(icon: "checkmark.circle", value: "\(summary.totalCompletedDays)", label: "days", tint: Color(hex: 0x5BC489))
            Spacer(minLength: 0)
        }
    }

    private func statChip(icon: String, value: String, label: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColor.textSecondary)
        }
    }
}
