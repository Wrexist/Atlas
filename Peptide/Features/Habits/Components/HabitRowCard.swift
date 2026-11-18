import SwiftUI

/// One habit as a checklist row: icon, name, schedule and streak in a
/// line under it, and the check button. The half-year heatmap and the
/// best/total stats live in the habit's editor, so a list of five
/// habits reads as five things to tick, not five dashboards.
struct HabitRowCard: View {
    let habit: Habit
    let summary: HabitsService.Summary
    let onToggleToday: () -> Void
    /// Takes one off a countable habit's count for today.
    let onRemoveOne: () -> Void
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var completionTrigger = 0

    private static let todayButtonSize: CGFloat = 28

    var body: some View {
        Button(action: onTap) {
            header
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
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        // A sibling of the card's Button rather than nested in its label,
        // so its taps don't route through the card. Drawn over the
        // header's reserved slot.
        .overlayPreferenceValue(TodayButtonSlotKey.self) { slot in
            GeometryReader { proxy in
                if let slot {
                    let rect = proxy[slot]
                    todayButton.position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(habit.name). \(todayStatus). \(streakLabel), \(totalDaysLabel).")
        .accessibilityAddTraits(.isButton)
        // The combined card swallows `todayButton`, so expose its toggle
        // as a custom action or VoiceOver can only open the editor.
        .accessibilityAction(named: summary.isCompletedToday ? Text("Mark incomplete") : Text("Mark complete")) {
            onToggleToday()
        }
        .accessibilityActions {
            if canRemoveOne {
                Button("Remove one", action: onRemoveOne)
            }
        }
        .onChange(of: summary.isCompletedToday) { _, completed in
            guard completed else { return }
            completionTrigger &+= 1
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
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(habit.name)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                Text(detailLine)
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(2)
                    .contentTransition(.numericText())
            }
            .layoutPriority(1)
            Spacer(minLength: Spacing.sm)
            Color.clear
                .frame(width: Self.todayButtonSize, height: Self.todayButtonSize)
                .anchorPreference(key: TodayButtonSlotKey.self, value: .bounds) { $0 }
        }
    }

    /// A tap past the target resets a countable habit to zero, so an
    /// over-tap needs its own way back down. The row's context menu
    /// offers the same action.
    private var canRemoveOne: Bool {
        habit.isCountable && summary.todayValue > 0
    }

    private var todayStatus: String {
        summary.isCompletedToday
            ? String(localized: "Done today")
            : String(localized: "Not done today")
    }

    private var streakLabel: String {
        habit.schedule.countsStreakInWeeks
            ? String(localized: "\(summary.currentStreak) week streak")
            : String(localized: "\(summary.currentStreak) day streak")
    }

    private var totalDaysLabel: String {
        String(localized: "\(summary.totalCompletedDays) days total")
    }

    /// "Daily · 5 day streak" — the schedule as plain text instead of a
    /// tinted badge, with the streak only once there is one.
    private var detailLine: String {
        guard summary.currentStreak > 0 else { return habit.schedule.displayName }
        return "\(habit.schedule.displayName) · \(streakLabel)"
    }

    private var todayButton: some View {
        Button {
            // The completing tap gets DataStore's success haptic instead.
            if summary.isCompletedToday || summary.todayValue + 1 < (habit.targetValue ?? 1) {
                Haptics.impact(.soft)
            }
            withAnimation(AppAnimation.motionAware(AppAnimation.springSnappy, reduceMotion: reduceMotion)) { onToggleToday() }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(
                        summary.isCompletedToday ? habit.tint : AppColor.glassBorderActive,
                        lineWidth: 1.5
                    )
                    .frame(width: Self.todayButtonSize, height: Self.todayButtonSize)
                if summary.isCompletedToday {
                    Circle()
                        .fill(habit.tint)
                        .frame(width: 22, height: 22)
                        .transition(.scale.combined(with: .opacity))
                    Image(systemName: "checkmark")
                        .font(AppFont.scaled(11, weight: .bold))
                        .foregroundStyle(AppColor.background)
                        .symbolEffect(.bounce, value: summary.isCompletedToday)
                        .transition(.scale.combined(with: .opacity))
                } else if summary.todayProgress > 0 {
                    Circle()
                        .trim(from: 0, to: summary.todayProgress)
                        .stroke(habit.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees(-90))
                }
            }
            // Grow the hit area to 44pt without growing the header row.
            .contentShape(Circle().inset(by: -(Spacing.minimumHitTarget - Self.todayButtonSize) / 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(todayButtonLabel)
        .accessibilityValue(todayButtonValue)
    }

    /// A tap on a countable habit adds one toward the target rather than
    /// completing it, so say so.
    private var todayButtonLabel: Text {
        if summary.isCompletedToday { return Text("Completed today") }
        return habit.isCountable ? Text("Add one") : Text("Mark complete for today")
    }

    private var todayButtonValue: Text {
        guard let target = habit.targetValue else { return Text("") }
        return Text("\(summary.todayValue) of \(target)")
    }
}

/// Bounds of the header slot `todayButton` is drawn over.
private struct TodayButtonSlotKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}
