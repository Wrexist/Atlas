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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsMonthLabels {
                monthRow
                    .foregroundStyle(AppColor.textTertiary)
                    .font(.system(size: 9, weight: .semibold))
            }

            GeometryReader { proxy in
                let cellSize = max(4, (proxy.size.width - CGFloat(columns.count - 1) * cellSpacing) / CGFloat(max(1, columns.count)))
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
            .frame(height: 7 * 11 + 6 * cellSpacing) // 11pt avg cell + spacing — clamps min height
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
    }

    private var monthRow: some View {
        HStack(spacing: 0) {
            ForEach(monthLabels, id: \.offset) { label in
                Text(label.text)
                    .frame(width: label.width, alignment: .leading)
            }
        }
    }

    private struct MonthLabel {
        let offset: Int
        let text: String
        let width: CGFloat
    }

    /// Pre-computes month labels and the column-widths each one
    /// spans. Falls back to evenly-spaced quarters when the caller
    /// doesn't supply a `firstColumnStart`.
    private var monthLabels: [MonthLabel] {
        guard let firstDate = firstColumnStart, !columns.isEmpty else {
            return []
        }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        var labels: [MonthLabel] = []
        var lastMonth: Int = -1
        var widthAccumulator: CGFloat = 0

        for columnIdx in 0..<columns.count {
            guard let columnDate = calendar.date(byAdding: .weekOfYear, value: columnIdx, to: firstDate) else {
                continue
            }
            let month = calendar.component(.month, from: columnDate)
            if month != lastMonth {
                if lastMonth != -1 {
                    // Close the previous label's width
                    labels[labels.count - 1] = MonthLabel(
                        offset: labels[labels.count - 1].offset,
                        text:   labels[labels.count - 1].text,
                        width:  widthAccumulator
                    )
                }
                labels.append(MonthLabel(offset: columnIdx, text: formatter.string(from: columnDate), width: 0))
                widthAccumulator = 0
                lastMonth = month
            }
            widthAccumulator += 14
        }
        // Close the final label
        if !labels.isEmpty {
            labels[labels.count - 1] = MonthLabel(
                offset: labels[labels.count - 1].offset,
                text:   labels[labels.count - 1].text,
                width:  widthAccumulator
            )
        }
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
        return "Habit heatmap. \(completed) of \(total) days completed."
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
