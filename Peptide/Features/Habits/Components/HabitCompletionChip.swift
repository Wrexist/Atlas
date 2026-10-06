import SwiftUI

/// One tappable habit pill — completion ring/checkmark + name + optional
/// weekly progress + streak flame. Presentational: the parent supplies the
/// current state and the tap handler, which routes through
/// `DataStore.toggleHabitEntry` where the completion celebration fires.
struct HabitCompletionChip: View {
    let habit: Habit
    let isCompleted: Bool
    let currentStreak: Int
    /// Set only for `.timesPerWeek` habits — shows "X/N" for the week.
    let weeklyCount: Int?
    let weeklyTarget: Int?
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var completionTrigger = 0

    var body: some View {
        Button {
            withAnimation(AppAnimation.motionAware(AppAnimation.springSnappy, reduceMotion: reduceMotion)) { onTap() }
        } label: {
            HStack(spacing: 6) {
                marker
                    .completionPulse(trigger: completionTrigger, isActive: isCompleted)
                Text(habit.name)
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(isCompleted ? AppColor.textSecondary : AppColor.textPrimary)
                    .lineLimit(1)
                if let weeklyCount, let weeklyTarget {
                    Text("\(weeklyCount)/\(weeklyTarget)")
                        .font(AppFont.scaled(11, weight: .bold, design: .rounded))
                        .foregroundStyle(habit.tint)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                if currentStreak >= 3 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(AppFont.scaled(8))
                        Text("\(currentStreak)")
                            .font(AppFont.scaled(11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(AppColor.streak)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(isCompleted ? habit.tint.opacity(0.12) : AppColor.surfaceSecondary.opacity(0.7))
            )
            .overlay(
                Capsule().strokeBorder(isCompleted ? habit.tint.opacity(0.4) : AppColor.glassBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(habit.name)
        .accessibilityValue(accessibilityValue)
        .onChange(of: isCompleted) { _, completed in
            if completed { completionTrigger &+= 1 }
        }
    }

    private var marker: some View {
        ZStack {
            Circle()
                .strokeBorder(isCompleted ? habit.tint : habit.tint.opacity(0.45), lineWidth: 1.5)
                .frame(width: 18, height: 18)
            if isCompleted {
                Circle()
                    .fill(habit.tint)
                    .frame(width: 14, height: 14)
                Image(systemName: "checkmark")
                    .font(AppFont.scaled(8, weight: .bold))
                    .foregroundStyle(AppColor.background)
            } else {
                Image(systemName: habit.iconSymbol)
                    .font(AppFont.scaled(8, weight: .semibold))
                    .foregroundStyle(habit.tint)
            }
        }
    }

    private var accessibilityValue: String {
        var parts: [String] = [isCompleted ? "completed today" : "not yet completed"]
        if currentStreak >= 3 { parts.append("\(currentStreak) day streak") }
        return parts.joined(separator: ", ")
    }
}
