import SwiftUI

/// Compact day stepper for the Meals tab: chevrons walk back and
/// forward a day, tapping the title jumps back to today. Driven by a
/// day offset (0 = today, -1 = yesterday) so a screen left open past
/// midnight keeps meaning "today". Never steps into the future.
struct MealDaySwitcher: View {
    @Binding var offset: Int

    private var day: Date { LifestyleDataLogic.mealDay(offset: offset) }
    private var isToday: Bool { offset >= 0 }
    private var isAtOldest: Bool { offset <= -LifestyleDataLogic.maxMealDayLookback }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            chevron(
                "chevron.left",
                label: "Previous day",
                isDisabled: isAtOldest
            ) { step(-1) }

            Button {
                guard !isToday else { return }
                Haptics.selection()
                withAnimation(AppAnimation.springSnappy) { offset = 0 }
            } label: {
                VStack(spacing: 0) {
                    Text(Self.title(for: day))
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    if !isToday {
                        Text("Tap for today")
                            .font(AppFont.scaled(11, weight: .semibold))
                            .foregroundStyle(AppColor.accentLight)
                    }
                }
                .frame(maxWidth: .infinity)
                .minimumHitArea()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(Self.title(for: day)))
            .accessibilityHint(isToday ? Text("") : Text("Jumps back to today."))

            chevron(
                "chevron.right",
                label: "Next day",
                isDisabled: isToday
            ) { step(1) }
        }
        .padding(.horizontal, Spacing.xs)
        .glassControl(
            .rect(cornerRadius: Spacing.controlCornerRadius),
            tint: AppColor.accentPrimary.opacity(0.08),
            border: AppColor.glassBorder
        )
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

    private func step(_ delta: Int) {
        Haptics.selection()
        withAnimation(AppAnimation.springSnappy) {
            offset = min(0, max(-LifestyleDataLogic.maxMealDayLookback, offset + delta))
        }
    }

    /// "Today", "Yesterday", or a short weekday + date. Shared with the
    /// log buttons so "Add to Yesterday" names the same day the switcher does.
    static func title(for day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) {
            return String(localized: "Today", comment: "Meals day switcher — the current day")
        }
        if calendar.isDateInYesterday(day) {
            return String(localized: "Yesterday", comment: "Meals day switcher — the previous day")
        }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}
