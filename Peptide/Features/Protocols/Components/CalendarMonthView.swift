import SwiftUI

/// 6-row monthly calendar grid. In `.schedule` mode each cell paints a
/// dose-dot row underneath the date; in `.cycle` mode the per-day dots
/// are suppressed and a thin coloured band per active protocol is
/// drawn across the full week row instead. The wrapping
/// `TrackCalendarSection` adds month chevrons, the filter shelf, and
/// the per-day detail panel below.
struct CalendarMonthView: View {
    let monthDate: Date
    let dosesByDay: [Date: [CalendarDoseMark]]
    let displayMode: CalendarDisplayMode
    let bandsPerRow: [[CycleBand]]
    @Binding var selectedDay: Date

    init(
        monthDate: Date,
        dosesByDay: [Date: [CalendarDoseMark]],
        displayMode: CalendarDisplayMode = .schedule,
        bandsPerRow: [[CycleBand]] = Array(repeating: [], count: 6),
        selectedDay: Binding<Date>
    ) {
        self.monthDate = monthDate
        self.dosesByDay = dosesByDay
        self.displayMode = displayMode
        self.bandsPerRow = bandsPerRow
        self._selectedDay = selectedDay
    }

    private let calendar: Calendar = .current
    private static let maxDots = 3
    private static let maxBands = 4
    private static let rowHeight: CGFloat = 52

    private var firstWeekday: Int { calendar.firstWeekday }
    private var grid: [Date] { CalendarMonth.grid(for: monthDate, firstWeekday: firstWeekday, calendar: calendar) }
    private var weekdays: [String] { CalendarMonth.weekdaySymbols(firstWeekday: firstWeekday, calendar: calendar) }

    var body: some View {
        VStack(spacing: 0) {
            weekdayHeader
                .padding(.bottom, Spacing.sm)

            Rectangle()
                .fill(AppColor.glassBorder)
                .frame(height: 0.5)
                .padding(.bottom, Spacing.xs)

            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { row in
                    weekRow(at: row)
                }
            }
        }
    }

    private func weekRow(at row: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { col in
                    let date = grid[row * 7 + col]
                    dayCell(for: date)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: Self.rowHeight)

            if displayMode == .cycle {
                bandStrip(for: bandsPerRow[safe: row] ?? [])
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Weekday header

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdays.enumerated()), id: \.offset) { _, symbol in
                Text(symbol.prefix(3).uppercased())
                    .font(AppFont.scaled(11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(AppColor.textTertiary)
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
            Haptics.selection()
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(AppColor.accentPrimary)
                            .frame(width: 34, height: 34)
                    } else if isToday {
                        Circle()
                            .fill(AppColor.accentPrimary.opacity(0.14))
                            .frame(width: 34, height: 34)
                    }
                    Text(dayNumber(for: date))
                        .font(AppFont.scaled(15, weight: dayWeight(isSelected: isSelected, isToday: isToday), design: .rounded))
                        .foregroundStyle(dateColor(isCurrentMonth: isCurrentMonth, isSelected: isSelected, isToday: isToday))
                        .monospacedDigit()
                }
                .frame(height: 34)

                if displayMode == .schedule {
                    dotRow(for: marks, isSelected: isSelected)
                        .frame(height: 6)
                } else {
                    // Reserve the same vertical space so cells don't
                    // jitter when the user toggles between modes.
                    Color.clear.frame(height: 6)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: date, marks: marks))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func dotRow(for marks: [CalendarDoseMark], isSelected: Bool) -> some View {
        HStack(spacing: 3) {
            let visible = Array(marks.prefix(Self.maxDots))
            ForEach(visible) { mark in
                doseDot(for: mark, dimmed: isSelected)
            }
            if marks.count > Self.maxDots {
                Text("+\(marks.count - Self.maxDots)")
                    .font(AppFont.scaled(8, weight: .bold))
                    .foregroundStyle(isSelected ? AppColor.onAccent.opacity(0.8) : AppColor.textTertiary)
                    .monospacedDigit()
            }
        }
    }

    private func doseDot(for mark: CalendarDoseMark, dimmed: Bool) -> some View {
        let palette = VialPalette.colors(for: mark.peptideName)
        let tint = dimmed ? AppColor.onAccent.opacity(0.9) : palette.fill
        return Group {
            switch mark.kind {
            case .logged:
                Circle().fill(tint)
            case .scheduled:
                Circle().strokeBorder(tint, lineWidth: 1.2)
            }
        }
        .frame(width: 5, height: 5)
    }

    // MARK: - Cycle bands

    private func bandStrip(for bands: [CycleBand]) -> some View {
        VStack(spacing: 2) {
            let visible = Array(bands.prefix(Self.maxBands))
            ForEach(visible) { band in
                Capsule()
                    .fill(band.color.opacity(0.85))
                    .frame(height: 3)
                    .accessibilityLabel(Text("\(band.name) active this week"))
            }
            if bands.isEmpty {
                // Reserved sliver so weeks without bands don't collapse
                // and re-flow the grid as the user pages through months.
                Color.clear.frame(height: 3)
            }
        }
    }

    // MARK: - Helpers

    private func dayNumber(for date: Date) -> String {
        String(calendar.component(.day, from: date))
    }

    private func dayWeight(isSelected: Bool, isToday: Bool) -> Font.Weight {
        if isSelected { return .bold }
        if isToday { return .bold }
        return .medium
    }

    private func dateColor(isCurrentMonth: Bool, isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .white }
        if !isCurrentMonth { return AppColor.textTertiary.opacity(0.4) }
        if isToday { return AppColor.accentLight }
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
