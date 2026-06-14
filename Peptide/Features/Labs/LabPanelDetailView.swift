import SwiftUI
import Charts

/// Per-panel chart + history list. Drill-in from a `LabSummaryRow`
/// tap. Shows the trend over time with the typical reference range
/// shaded, then a chronological list of every draw with edit /
/// delete affordances.
///
/// Empty state would never render — the detail page is only
/// reachable from a row that exists, which implies at least one
/// entry. If a user deletes the last entry while on the page,
/// `entries.isEmpty` is true and we pop back to the parent.
struct LabPanelDetailView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    let panel: LabPanel

    @State private var editingEntry: LabValue?

    private var entries: [LabValue] {
        dataStore.labEntries(for: panel)
    }

    private var latest: LabValue? { entries.last }

    /// The reference-range overlay is sex-specific for hormone /
    /// hematology panels — read the user's sex so women don't see
    /// male bands.
    private var userSex: BiologicalSex { dataStore.profile.bodyMetrics.sex }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if entries.isEmpty {
                    emptyShim
                } else {
                    headlineCard
                    chartCard
                    historyCard
                }
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xxxxl)
        }
        .scrollIndicators(.hidden)
        .background(AppColor.background)
        .navigationTitle(panel.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingEntry) { entry in
            LabEntryEditor(
                initial: entry,
                sex: userSex,
                onSave: { value in
                    dataStore.saveLabValue(value)
                    editingEntry = nil
                },
                onDelete: { id in
                    dataStore.deleteLabValue(id: id)
                    editingEntry = nil
                },
                onCancel: { editingEntry = nil }
            )
        }
        .onChange(of: entries.count) { _, newCount in
            // If the user deleted the last entry while on this
            // page, the parent's row vanished too — pop back so
            // they don't sit on an empty detail view.
            if newCount == 0 { dismiss() }
        }
    }

    // MARK: - Headline

    private var headlineCard: some View {
        GlassCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Latest")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(0.6)
                            .textCase(.uppercase)
                            .foregroundStyle(panel.tint.opacity(0.85))
                        if let latest {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(formatted(latest.value))
                                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(AppColor.textPrimary)
                                    .contentTransition(.numericText())
                                Text(panel.canonicalUnit)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                            Text(Self.dateFormatter.string(from: latest.date))
                                .font(.system(size: 11))
                                .foregroundStyle(AppColor.textTertiary)
                                .monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                    if let range = panel.typicalRange(for: userSex) {
                        rangePill(range: range, value: latest?.value)
                    }
                }
            }
        }
    }

    private func rangePill(range: ClosedRange<Double>, value: Double?) -> some View {
        let status: RangeStatus = {
            guard let value else { return .unknown }
            if value < range.lowerBound { return .below }
            if value > range.upperBound { return .above }
            return .within
        }()
        let (label, tint): (LocalizedStringKey, Color) = {
            switch status {
            case .within:  return ("In range", Color(red: 0.40, green: 0.78, blue: 0.55))
            case .below:   return ("Below range", Color(red: 0.55, green: 0.78, blue: 0.92))
            case .above:   return ("Above range", Color(red: 0.92, green: 0.55, blue: 0.30))
            case .unknown: return ("No reference", AppColor.textSecondary)
            }
        }()
        return Text(label)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(tint)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background {
                Capsule().fill(tint.opacity(0.18))
            }
    }

    // MARK: - Chart

    private var chartCard: some View {
        GlassCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Trend")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.textTertiary)
                chart
            }
        }
    }

    private var chart: some View {
        Chart {
            if let range = panel.typicalRange(for: userSex) {
                // Subtle band for the typical adult reference range.
                // RuleMark + AreaMark would require axis bounds we
                // don't know in advance; RectangleMark in a chart
                // with a value axis won't render the way we want.
                // Use two RuleMarks (low + high) so the user reads
                // the band as "between these lines".
                RuleMark(y: .value("Low ref", range.lowerBound))
                    .foregroundStyle(AppColor.textTertiary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .leading, alignment: .leading) {
                        Text("ref")
                            .font(.system(size: 9))
                            .foregroundStyle(AppColor.textTertiary)
                    }
                RuleMark(y: .value("High ref", range.upperBound))
                    .foregroundStyle(AppColor.textTertiary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            ForEach(entries) { entry in
                LineMark(
                    x: .value("Date", entry.date),
                    y: .value("Value", entry.value)
                )
                .foregroundStyle(panel.tint.gradient)
                .interpolationMethod(.monotone)
                .symbol(.circle)
                .symbolSize(60)
            }
        }
        .frame(height: 200)
        .chartXAxis {
            AxisMarks(values: .stride(by: chartXStride)) { value in
                AxisGridLine().foregroundStyle(AppColor.glassBorder)
                AxisTick().foregroundStyle(AppColor.glassBorder)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(AppColor.glassBorder)
                AxisValueLabel()
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    /// Picks a sensible x-axis stride based on the date span.
    /// Single draws and 1-month spans get monthly ticks; longer
    /// spans get quarterly — both keep the chart from being a wall
    /// of labels.
    private var chartXStride: Calendar.Component {
        guard let first = entries.first, let last = entries.last else { return .month }
        let days = Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 0
        return days > 180 ? .month : .weekOfYear
    }

    // MARK: - History list

    private var historyCard: some View {
        GlassCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("History")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.textTertiary)
                VStack(spacing: Spacing.xs) {
                    ForEach(entries.reversed()) { entry in
                        historyRow(entry)
                    }
                }
            }
        }
    }

    private func historyRow(_ entry: LabValue) -> some View {
        Button {
            editingEntry = entry
        } label: {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.dateFormatter.string(from: entry.date))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .monospacedDigit()
                    if let source = entry.source, !source.isEmpty {
                        Text(source)
                            .font(.system(size: 11))
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(1)
                    } else if let note = entry.note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(formatted(entry.value))
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                    Text(panel.canonicalUnit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.35))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { editingEntry = entry } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                dataStore.deleteLabValue(id: entry.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var emptyShim: some View {
        Text("No entries")
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textSecondary)
            .padding(.top, Spacing.xxl)
    }

    private func formatted(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        if value < 10 {
            return String(format: "%.2f", value)
        }
        return String(format: "%.1f", value)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private enum RangeStatus {
        case within
        case below
        case above
        case unknown
    }
}
