import SwiftUI

/// GitHub-contribution-style heatmap of habit completion. 7 rows
/// (days of the week) × N columns (weeks). Each cell is a rounded
/// square tinted with the habit's accent color; uncompleted days
/// render as a desaturated track, off-schedule days as muted slots,
/// partial completions as the tint at reduced opacity.
///
/// The grid auto-sizes to the available width — cells shrink to fit
/// the column count so the heatmap reads cleanly on iPhone SE through
/// iPad Pro without a horizontal scrollview.
struct HabitHeatmap: View {
    let columns: [[HabitsService.HeatmapStatus?]]
    let tint: Color
    /// Show month labels above the grid (Oct / Nov / Dec …). The
    /// compact "today only" preview hides them.
    var showsMonthLabels: Bool = true
    /// Start date of the very first column — drives the month-label
    /// computation. Caller passes the same `endDate - dayCount + 1`
    /// they fed to `HabitsService.heatmap(...)`.
    var firstColumnStart: Date?

    private let cellSpacing: CGFloat = 3
    private let cornerRadius: CGFloat = 2.5

    /// Measured width of the heatmap. Cell size derives from it, and the
    /// view's height follows from the content — month row plus a grid of
    /// exactly `7 · cell + 6 · spacing` — so nothing overflows the card.
    @State private var availableWidth: CGFloat = 0

    private var cellSize: CGFloat {
        let count = CGFloat(max(1, columns.count))
        return max(4, (availableWidth - (count - 1) * cellSpacing) / count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Measured on an empty sibling, which takes the width offered
            // to the heatmap whatever the grid draws. Measuring the grid
            // itself fed its own width back into `cellSize`: a row a point
            // wider than the offer widened the next pass, without end, and
            // the Habits tab hung until the watchdog killed the app.
            Color.clear
                .frame(height: 0)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }

            VStack(alignment: .leading, spacing: 4) {
                if showsMonthLabels {
                    monthRow
                        .foregroundStyle(AppColor.textTertiary)
                        .font(AppFont.badgeSmall)
                }

                HStack(spacing: cellSpacing) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        VStack(spacing: cellSpacing) {
                            ForEach(0..<7, id: \.self) { row in
                                cell(for: row < column.count ? column[row] : nil, size: cellSize)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
    }

    private var monthRow: some View {
        let perColumnWidth = cellSize + cellSpacing
        let labels = Self.monthLabels(
            firstColumnStart: firstColumnStart,
            columnCount: columns.count,
            cellSize: cellSize,
            cellSpacing: cellSpacing,
            calendar: .current
        )
        return HStack(spacing: 0) {
            ForEach(labels, id: \.offset) { label in
                // A month that spans a single column (the partial first
                // or last) has no room for its name.
                Text(label.width > perColumnWidth ? label.text : "")
                    .lineLimit(1)
                    .frame(width: label.width, alignment: .leading)
            }
        }
    }

    struct MonthLabel: Equatable {
        let offset: Int
        let text: String
        let width: CGFloat
    }

    /// Hoisted out of `monthLabels` — it runs on every render of the
    /// heatmap, and a per-render DateFormatter allocation is the costly part.
    private static let monthAbbrevFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f
    }()

    /// One label per month the columns cross, each as wide as the columns
    /// it spans. The widths add up to exactly the grid's width — the last
    /// column has no trailing spacing — so the label row never sticks out
    /// past the cells under it.
    static func monthLabels(
        firstColumnStart: Date?,
        columnCount: Int,
        cellSize: CGFloat,
        cellSpacing: CGFloat,
        calendar: Calendar
    ) -> [MonthLabel] {
        guard let firstDate = firstColumnStart, columnCount > 0 else { return [] }
        let perColumnWidth = cellSize + cellSpacing
        let formatter = monthAbbrevFormatter

        var labels: [MonthLabel] = []
        var lastMonth: Int?
        var width: CGFloat = 0

        func closeLabel() {
            guard let open = labels.popLast() else { return }
            labels.append(MonthLabel(offset: open.offset, text: open.text, width: width))
        }

        for columnIdx in 0..<columnCount {
            guard let columnDate = calendar.date(byAdding: .weekOfYear, value: columnIdx, to: firstDate) else {
                continue
            }
            let month = calendar.component(.month, from: columnDate)
            if month != lastMonth {
                closeLabel()
                labels.append(MonthLabel(offset: columnIdx, text: formatter.string(from: columnDate), width: 0))
                width = 0
                lastMonth = month
            }
            width += perColumnWidth
        }
        width -= cellSpacing
        closeLabel()
        return labels
    }

    @ViewBuilder
    private func cell(for status: HabitsService.HeatmapStatus?, size: CGFloat) -> some View {
        switch status {
        case .none:
            // Padding cell for the first/last week's partial column.
            Color.clear.frame(width: size, height: size)
        case .notDue:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.35))
                .frame(width: size, height: size)
        case .due:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(tint.opacity(0.15), lineWidth: 0.5)
                )
                .frame(width: size, height: size)
        case .partial(let progress):
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tint.opacity(0.25 + 0.35 * progress))
                .frame(width: size, height: size)
        case .completed:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tint)
                .frame(width: size, height: size)
        }
    }

    private var accessibilityLabel: String {
        let completed = columns.flatMap { $0 }.compactMap { $0 }.filter {
            if case .completed = $0 { return true }
            return false
        }.count
        let total = columns.flatMap { $0 }.compactMap { $0 }.filter {
            switch $0 {
            case .due, .partial, .completed: return true
            case .notDue: return false
            }
        }.count
        return String(localized: "Habit heatmap. \(completed) of \(total) days completed.")
    }
}

#Preview {
    let calendar = Calendar.current
    let habit = Habit(
        name: "Morning Workout",
        iconSymbol: "figure.strengthtraining.traditional",
        tintHex: 0xCF7272
    )
    let today = Date()
    let entries: [HabitEntry] = (0..<160).compactMap { offset in
        guard offset.isMultiple(of: 2) || offset.isMultiple(of: 3) else { return nil }
        guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
        return HabitEntry(habitId: habit.id, date: day, value: 1)
    }
    let days = HabitsService.heatmap(for: habit, entries: entries, dayCount: 180)
    let columns = HabitsService.heatmapColumns(from: days)

    return ZStack {
        AppColor.background.ignoresSafeArea()
        HabitHeatmap(columns: columns, tint: habit.tint, firstColumnStart: days.first?.date)
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
