import SwiftUI

/// Day picker for the Meals tab and Today: a week strip to tap any day, chevrons
/// to page a week back or forward, and a title that jumps back to today.
/// Driven by a day offset (0 = today, -1 = yesterday) so a screen left
/// open past midnight keeps meaning "today". Never selects the future.
struct MealDaySwitcher: View {
    @Binding var offset: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var day: Date { LifestyleDataLogic.mealDay(offset: offset) }
    private var isToday: Bool { offset >= 0 }
    private var week: Range<Int> { WeekDayStrip.weekOffsets(containing: offset) }
    private var isAtOldestWeek: Bool { week.lowerBound <= -LifestyleDataLogic.maxMealDayLookback }
    private var isAtCurrentWeek: Bool { week.contains(0) }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            header
            WeekDayStrip(offset: $offset)
                .simultaneousGesture(weekSwipe)
        }
        .padding(Spacing.xs)
        .glassControl(
            .rect(cornerRadius: Spacing.controlCornerRadius),
            tint: AppColor.accentPrimary.opacity(0.08),
            border: AppColor.glassBorder
        )
    }

    private var header: some View {
        HStack(spacing: Spacing.xs) {
            Button {
                guard !isToday else { return }
                Haptics.selection()
                withAnimation(motion) { offset = 0 }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Self.title(for: day))
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .contentTransition(.interpolate)
                    if !isToday {
                        Text("Tap for today")
                            .font(AppFont.scaled(11, weight: .semibold))
                            .foregroundStyle(AppColor.accentLight)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .minimumHitArea()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(Self.title(for: day)))
            .accessibilityHint(isToday ? Text("") : Text("Jumps back to today."))

            chevron(
                "chevron.left",
                label: "Previous week",
                isDisabled: isAtOldestWeek
            ) { step(-7) }

            chevron(
                "chevron.right",
                label: "Next week",
                isDisabled: isAtCurrentWeek
            ) { step(7) }
        }
        .padding(.leading, Spacing.sm)
    }

    /// A horizontal swipe on the strip pages weeks like the chevrons do;
    /// mostly-vertical drags are left to the scroll view.
    private var weekSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > abs(value.translation.height) * 1.5, abs(dx) > 40 else { return }
                if dx < 0, !isAtCurrentWeek {
                    step(7)
                } else if dx > 0, !isAtOldestWeek {
                    step(-7)
                }
            }
    }

    private var motion: Animation? {
        AppAnimation.motionAware(AppAnimation.springSnappy, reduceMotion: reduceMotion)
    }

    private func chevron(
        _ icon: String,
        label: LocalizedStringKey,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(isDisabled ? AppColor.textTertiary : AppColor.accentLight)
                .minimumHitArea()
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(label)
    }

    /// Pages by a week but keeps the weekday, clamped to the lookback floor
    /// and today — the clamped day always lands in the adjacent week.
    private func step(_ delta: Int) {
        Haptics.selection()
        withAnimation(motion) {
            offset = min(0, max(-LifestyleDataLogic.maxMealDayLookback, offset + delta))
        }
    }

    /// "Today", "Yesterday", or a short weekday + date. Shared with the
    /// log buttons (via `inlineTitle`) so "Add to yesterday" names the
    /// same day the switcher does.
    static func title(for day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) {
            return String(localized: "Today", comment: "Meals day switcher — the current day")
        }
        if calendar.isDateInYesterday(day) {
            return String(localized: "Yesterday", comment: "Meals day switcher — the previous day")
        }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// Sentence-case `title` for use mid-sentence: "Add to yesterday".
    static func inlineTitle(for day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) {
            return String(localized: "today", comment: "Mid-sentence name of the current day, as in “Add to today”")
        }
        if calendar.isDateInYesterday(day) {
            return String(localized: "yesterday", comment: "Mid-sentence name of the previous day, as in “Add to yesterday”")
        }
        return title(for: day, calendar: calendar)
    }
}
