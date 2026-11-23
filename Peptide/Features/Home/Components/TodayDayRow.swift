import SwiftUI

/// Today's date as one row, with a step back and forward through earlier
/// days. Replaces the week-strip card Today shared with Meals: the strip
/// took two rows of chrome above any data, and Meals keeps it. Speaks the
/// same day offsets (0 = today, -1 = yesterday) and never selects the future.
struct TodayDayRow: View {
    @Binding var offset: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var day: Date { TodayDayEngine.day(offset: offset) }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .contentTransition(.interpolate)
                .frame(maxWidth: .infinity, alignment: .leading)

            chevron("chevron.left", label: "Previous day",
                    isDisabled: offset <= -LifestyleDataLogic.maxMealDayLookback) { step(-1) }
            chevron("chevron.right", label: "Next day",
                    isDisabled: TodayDayEngine.isToday(offset: offset)) { step(1) }
        }
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
        .buttonStyle(ScalePressStyle(pressedScale: 0.9))
        .disabled(isDisabled)
        .accessibilityLabel(label)
    }

    private func step(_ delta: Int) {
        Haptics.selection()
        withAnimation(AppAnimation.motionAware(AppAnimation.springSnappy, reduceMotion: reduceMotion)) {
            offset = min(0, max(-LifestyleDataLogic.maxMealDayLookback, offset + delta))
        }
    }
}

#Preview {
    TodayDayRow(offset: .constant(0))
        .padding(Spacing.screenPadding)
        .background(AppColor.background)
}
