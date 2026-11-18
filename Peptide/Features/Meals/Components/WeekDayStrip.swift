import SwiftUI

/// The week holding the selected meal day, starting on the locale's first
/// weekday. A filled pill marks the selection and slides between cells;
/// today's date is tinted and a dot marks every day with meals logged, as
/// Calendar marks days with events, so gaps in the diary show at a glance.
/// Days after today or past the lookback floor are dimmed and inert.
/// Speaks the same day offsets as `MealDaySwitcher`.
struct WeekDayStrip: View {
    @Binding var offset: Int

    @Environment(DataStore.self) private var dataStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var pillNamespace
    @State private var hasAppeared = false
    /// The week last drawn, so a new week knows which side to slide in from.
    @State private var shownWeekStart: Int?

    private static let selectableOffsets = -LifestyleDataLogic.maxMealDayLookback...0
    /// Past AX2 two-digit dates outgrow a seventh of the screen; the
    /// numerals stop growing there rather than scaling into each other.
    private static let typeSizeLimit = DynamicTypeSize.accessibility2
    /// `AppFont.scaled` reads the app's content size, not the SwiftUI
    /// environment, so the cap has to be passed to each font explicitly.
    private var stripTypeSize: DynamicTypeSize { min(dynamicTypeSize, Self.typeSizeLimit) }

    var body: some View {
        let week = Self.weekOffsets(containing: offset)
        let fromLater = week.lowerBound > (shownWeekStart ?? week.lowerBound)
        let logged = Self.loggedOffsets(in: week, profile: dataStore.profile)
        // One weekday format for the whole row, decided against the row's
        // ideal width: per-cell choices mixed "S M T W T Fri S". Narrow
        // letters win whenever the short names or the numerals wouldn't
        // all fit, which covers every accessibility size.
        ViewThatFits(in: .horizontal) {
            row(week, logged: logged, narrow: false)
            row(week, logged: logged, narrow: true)
        }
        .dynamicTypeSize(...Self.typeSizeLimit)
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

    private func row(
        _ week: Range<Int>,
        logged: Set<Int>,
        narrow: Bool
    ) -> some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(week, id: \.self) { dayOffset in
                cell(dayOffset, hasLogged: logged.contains(dayOffset), narrow: narrow)
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
    }

    private func cell(_ dayOffset: Int, hasLogged: Bool, narrow: Bool) -> some View {
        let day = Self.date(for: dayOffset)
        let isSelected = dayOffset == offset
        let isSelectable = Self.selectableOffsets.contains(dayOffset)
        let isToday = dayOffset == 0
        let hasMeals = isSelectable && hasLogged
        return Button { select(dayOffset) } label: {
            VStack(spacing: Spacing.xxs) {
                Text(day, format: .dateTime.weekday(narrow ? .narrow : .abbreviated))
                    .font(AppFont.scaled(11, weight: .semibold, relativeTo: .caption1, in: stripTypeSize))
                    .foregroundStyle(ink(AppColor.textSecondary, isSelected: isSelected, isSelectable: isSelectable))
                Text(day, format: .dateTime.day())
                    .font(AppFont.scaled(16, weight: .medium, relativeTo: .headline, in: stripTypeSize))
                    .monospacedDigit()
                    .foregroundStyle(ink(AppColor.textPrimary, isSelected: isSelected, isSelectable: isSelectable))
                Circle()
                    .fill(isSelected ? AppColor.inverseInk : AppColor.accentPrimary)
                    .frame(width: Spacing.xs, height: Spacing.xs)
                    .opacity(hasMeals ? 1 : 0)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            // Inside the cell, so the glyphs keep clear of the selected
            // pill's rounded ends and neighbouring numerals keep a gap even
            // when each is scaled down to fill its seventh. Counted in the
            // row's ideal width, so a row whose short names wouldn't fit
            // with this inset falls back to single letters.
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            // `minWidth: 0` caps a cell at its seventh of the row; without
            // it the frame grew to its content and the strip pushed the
            // whole Today stack past both screen edges at AX sizes.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: Spacing.minimumHitTarget)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(AppColor.textPrimary)
                        // One id per row variant: `ViewThatFits` builds both
                        // rows, and two sources under one id would clash.
                        .matchedGeometryEffect(id: narrow ? "selectedDayNarrow" : "selectedDay", in: pillNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.94))
        .disabled(!isSelectable)
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(Self.spokenState(isToday: isToday, hasMeals: hasMeals))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private static func spokenState(isToday: Bool, hasMeals: Bool) -> Text {
        switch (isToday, hasMeals) {
        case (true, true): Text("Today, meals logged")
        case (true, false): Text("Today")
        case (false, true): Text("Meals logged")
        case (false, false): Text("")
        }
    }

    private func ink(_ base: Color, isSelected: Bool, isSelectable: Bool) -> Color {
        if isSelected { return AppColor.inverseInk }
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

    /// The offsets in `week` with meals logged: one pass over the meal
    /// history for the whole week, plus a keyed bucket lookup per day for
    /// legacy totals, instead of two full-history scans per cell.
    nonisolated static func loggedOffsets(
        in week: Range<Int>,
        profile: UserProfile,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Set<Int> {
        let todayStart = calendar.startOfDay(for: today)
        guard let start = calendar.date(byAdding: .day, value: week.lowerBound, to: todayStart),
              let end = calendar.date(byAdding: .day, value: week.count, to: start) else { return [] }
        var offsets = Set<Int>()
        for entry in profile.mealHistory where entry.date >= start && entry.date < end {
            if let offset = calendar.dateComponents([.day], from: todayStart, to: calendar.startOfDay(for: entry.date)).day {
                offsets.insert(offset)
            }
        }
        for offset in week where !offsets.contains(offset) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: todayStart) else { continue }
            let bucket = profile.dailyConsumption[LifestyleDataLogic.consumptionKey(for: day, calendar: calendar)]
            if (bucket?.caloriesKcal ?? 0) > 0 { offsets.insert(offset) }
        }
        return offsets
    }

    /// Unlike `LifestyleDataLogic.mealDay`, doesn't clamp — future cells
    /// still need their real date to render.
    private static func date(for offset: Int, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }
}
