import SwiftUI

/// The week holding the selected meal day, starting on the locale's first
/// weekday. A filled pill marks the selection and slides between cells;
/// today carries a dot. Days after today or past the lookback floor are
/// dimmed and inert. Speaks the same day offsets as `MealDaySwitcher`.
struct WeekDayStrip: View {
    @Binding var offset: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pillNamespace
    @State private var hasAppeared = false
    /// The week last drawn, so a new week knows which side to slide in from.
    @State private var shownWeekStart: Int?

    private static let selectableOffsets = -LifestyleDataLogic.maxMealDayLookback...0

    var body: some View {
        let week = Self.weekOffsets(containing: offset)
        let fromLater = week.lowerBound > (shownWeekStart ?? week.lowerBound)
        HStack(spacing: Spacing.xxs) {
            ForEach(week, id: \.self) { dayOffset in
                cell(dayOffset)
                    .opacity(hasAppeared ? 1 : 0)
                    .animation(
                        AppAnimation.motionAware(
                            AppAnimation.staggered(index: dayOffset - week.lowerBound),
                            reduceMotion: reduceMotion
                        ),
                        value: hasAppeared
                    )
            }
        }
        // A new week slides in from the side time moved toward; the old
        // one fades rather than guessing a direction it was drawn without.
        .id(week.lowerBound)
        .transition(.asymmetric(
            insertion: reduceMotion ? .opacity : .move(edge: fromLater ? .trailing : .leading).combined(with: .opacity),
            removal: .opacity
        ))
        .onAppear {
            hasAppeared = true
            shownWeekStart = week.lowerBound
        }
        .onChange(of: week.lowerBound) { _, start in shownWeekStart = start }
    }

    private func cell(_ dayOffset: Int) -> some View {
        let day = Self.date(for: dayOffset)
        let isSelected = dayOffset == offset
        let isSelectable = Self.selectableOffsets.contains(dayOffset)
        return Button { select(dayOffset) } label: {
            VStack(spacing: Spacing.xxs) {
                Text(day, format: .dateTime.weekday(.abbreviated))
                    .font(AppFont.scaled(11, weight: .semibold, relativeTo: .caption1))
                    .foregroundStyle(ink(AppColor.textSecondary, isSelected: isSelected, isSelectable: isSelectable))
                Text(day, format: .dateTime.day())
                    .font(AppFont.scaled(16, weight: .bold, relativeTo: .headline))
                    .monospacedDigit()
                    .foregroundStyle(ink(AppColor.textPrimary, isSelected: isSelected, isSelectable: isSelectable))
                Circle()
                    .fill(AppColor.accentPrimary)
                    .frame(width: Spacing.xs, height: Spacing.xs)
                    .opacity(dayOffset == 0 && !isSelected ? 1 : 0)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: Spacing.minimumHitTarget)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(AppColor.accentFill)
                        .matchedGeometryEffect(id: "selectedDay", in: pillNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.94))
        .disabled(!isSelectable)
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(dayOffset == 0 ? Text("Today") : Text(""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func ink(_ base: Color, isSelected: Bool, isSelectable: Bool) -> Color {
        if isSelected { return AppColor.onAccent }
        return isSelectable ? base : AppColor.textTertiary
    }

    private func select(_ dayOffset: Int) {
        guard dayOffset != offset else { return }
        Haptics.selection()
        withAnimation(AppAnimation.motionAware(AppAnimation.springSnappy, reduceMotion: reduceMotion)) {
            offset = dayOffset
        }
    }

    /// The seven day offsets of the week containing `offset`. Integer maths
    /// on the weekday rather than date arithmetic, so DST shifts can't skew it.
    static func weekOffsets(containing offset: Int, calendar: Calendar = .current) -> Range<Int> {
        let weekday = calendar.component(.weekday, from: date(for: offset, calendar: calendar))
        let start = offset - (weekday - calendar.firstWeekday + 7) % 7
        return start..<(start + 7)
    }

    /// Unlike `LifestyleDataLogic.mealDay`, doesn't clamp — future cells
    /// still need their real date to render.
    private static func date(for offset: Int, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }
}
