import SwiftUI

/// 6-row monthly calendar grid with dose dots painted per day. Pure
/// presentation — owns no data, accepts a `DoseDayMap`-style dictionary
/// keyed by start-of-day. Designed to be dropped into any scrollable
/// surface; the wrapping `TrackCalendarSection` adds month chevrons,
/// the filter shelf, and the per-day detail panel below.
struct CalendarMonthView: View {
    let monthDate: Date
    let dosesByDay: [Date: [CalendarDoseMark]]
    @Binding var selectedDay: Date

    private let calendar: Calendar = .current
    private static let maxDots = 3

    private var firstWeekday: Int { calendar.firstWeekday }
    private var grid: [Date] { CalendarMonth.grid(for: monthDate, firstWeekday: firstWeekday, calendar: calendar) }
    private var weekdays: [String] { CalendarMonth.weekdaySymbols(firstWeekday: firstWeekday, calendar: calendar) }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            weekdayHeader

            VStack(spacing: 4) {
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { col in
                            let date = grid[row * 7 + col]
                            dayCell(for: date)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Weekday header

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdays, id: \.self) { symbol in
                Text(symbol)
                    .font(AppFont.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Day cell

    private func dayCell(for date: Date) -> some View {
        let isCurrentMonth = calendar.isDate(date, equalTo: monthDate, toGranularity: .month)
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDay)
        let marks = dosesByDay[calendar.startOfDay(for: date)] ?? []

        return Button {
            selectedDay = calendar.startOfDay(for: date)
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AppColor.accentPrimary, AppColor.accentLight],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 30, height: 30)
                    } else if isToday {
                        Circle()
                            .strokeBorder(AppColor.accentPrimary, lineWidth: 1.5)
                            .frame(width: 30, height: 30)
                    }
                    Text(dayNumber(for: date))
                        .font(.system(size: 15, weight: isCurrentMonth ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(dateColor(isCurrentMonth: isCurrentMonth, isSelected: isSelected, isToday: isToday))
                        .monospacedDigit()
                }

                dotRow(for: marks)
                    .frame(height: 6)
            }
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: date, marks: marks))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func dotRow(for marks: [CalendarDoseMark]) -> some View {
        HStack(spacing: 3) {
            let visible = Array(marks.prefix(Self.maxDots))
            ForEach(visible) { mark in
                doseDot(for: mark)
            }
            if marks.count > Self.maxDots {
                Text("+\(marks.count - Self.maxDots)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(AppColor.textTertiary)
                    .monospacedDigit()
            }
        }
    }

    private func doseDot(for mark: CalendarDoseMark) -> some View {
        let palette = VialPalette.colors(for: mark.peptideName)
        return Group {
            switch mark.kind {
            case .logged:
                Circle().fill(palette.fill)
            case .scheduled:
                Circle().strokeBorder(palette.fill, lineWidth: 1.2)
            }
        }
        .frame(width: 6, height: 6)
    }

    // MARK: - Helpers

    private func dayNumber(for date: Date) -> String {
        String(calendar.component(.day, from: date))
    }

    private func dateColor(isCurrentMonth: Bool, isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .white }
        if !isCurrentMonth { return AppColor.textTertiary.opacity(0.5) }
        if isToday { return AppColor.accentPrimary }
        return AppColor.textPrimary
    }

    private func accessibilityLabel(for date: Date, marks: [CalendarDoseMark]) -> Text {
        let dateString = date.formatted(.dateTime.weekday(.wide).day(.defaultDigits).month(.wide))
        if marks.isEmpty { return Text(dateString) }
        let logged = marks.filter { $0.kind == .logged }.count
        let scheduled = marks.filter { $0.kind == .scheduled }.count
        return Text("\(dateString), \(logged) logged, \(scheduled) scheduled")
    }
}
