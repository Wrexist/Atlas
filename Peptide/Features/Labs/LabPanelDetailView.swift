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
    @State private var creatingEntry = false
    @State private var pendingDelete: LabValue?
    /// The date the user is scrubbing on the chart.
    @State private var selectedDate: Date?

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Haptics.impact(.light)
                    creatingEntry = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(AppFont.scaled(20))
                        .foregroundStyle(AppColor.accentPrimary)
                }
                .accessibilityLabel(Text("Log a new \(panel.displayName) value"))
            }
        }
        .sheet(isPresented: $creatingEntry) {
            LabEntryEditor(
                initial: nil,
                defaultPanel: panel,
                sex: userSex,
                onSave: { value in
                    AppAnimation.with(AppAnimation.springSnappy) { dataStore.saveLabValue(value) }
                    creatingEntry = false
                },
                onDelete: nil,
                onCancel: { creatingEntry = false }
            )
            .liquidGlassPresentation()
        }
        .sheet(item: $editingEntry) { entry in
            LabEntryEditor(
                initial: entry,
                sex: userSex,
                onSave: { value in
                    AppAnimation.with(AppAnimation.springSnappy) { dataStore.saveLabValue(value) }
                    editingEntry = nil
                },
                onDelete: { id in
                    AppAnimation.with(AppAnimation.springSnappy) { dataStore.deleteLabValue(id: id) }
                    editingEntry = nil
                },
                onCancel: { editingEntry = nil }
            )
            .liquidGlassPresentation()
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { entry in
            Button("Delete", role: .destructive) {
                Haptics.warning()
                AppAnimation.with(AppAnimation.springSnappy) { dataStore.deleteLabValue(id: entry.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone. The trend chart will skip the deleted point.")
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
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Latest")
                            .font(AppFont.eyebrow)
                            .tracking(0.6)
                            .textCase(.uppercase)
                            .foregroundStyle(AppColor.textSecondary)
                        if let latest {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(LabValueFormat.string(latest.value))
                                    .font(AppFont.scaled(34, weight: .heavy, design: .rounded, relativeTo: .largeTitle))
                                    .monospacedDigit()
                                    .foregroundStyle(AppColor.textPrimary)
                                    .contentTransition(.numericText())
                                Text(panel.canonicalUnit)
                                    .font(AppFont.scaled(13, weight: .semibold))
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                            Text(Self.dateFormatter.string(from: latest.date))
                                .font(AppFont.scaled(11))
                                .foregroundStyle(AppColor.textTertiary)
                                .monospacedDigit()
                            if let change = changeSincePrevious {
                                Text(change)
                                    .font(AppFont.scaled(13, weight: .semibold))
                                    .foregroundStyle(AppColor.textSecondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    if let latest, let status = LabRangeStatus(value: latest.value, panel: panel, sex: userSex) {
                        rangePill(status)
                    }
                }
            }
        }
    }

    /// "↑ 12% since 3 Mar", against the draw before the latest.
    private var changeSincePrevious: String? {
        guard entries.count >= 2, let latest else { return nil }
        let previous = entries[entries.count - 2]
        guard previous.value != 0 else { return nil }
        let fraction = (latest.value - previous.value) / abs(previous.value)
        let arrow = fraction > 0 ? "↑" : (fraction < 0 ? "↓" : "→")
        let percent = abs(fraction).formatted(.percent.precision(.fractionLength(0)))
        let date = previous.date.formatted(.dateTime.day().month(.abbreviated))
        return String(localized: "\(arrow) \(percent) since \(date)")
    }

    private func rangePill(_ status: LabRangeStatus) -> some View {
        Text(status.label)
            .font(AppFont.scaled(11, weight: .heavy))
            .foregroundStyle(status.tint)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background {
                Capsule().fill(status.tint.opacity(0.18))
            }
    }

    // MARK: - Chart

    private var chartCard: some View {
        GlassCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Trend")
                    .font(AppFont.eyebrow)
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
                // A RectangleMark with only y bounds spans the whole
                // plot width, so the band needs no x-axis bounds.
                RectangleMark(
                    yStart: .value("Low ref", range.lowerBound),
                    yEnd: .value("High ref", range.upperBound)
                )
                .foregroundStyle(AppColor.positive.opacity(0.08))
                .annotation(position: .overlay, alignment: .topLeading) {
                    Text("Typical range")
                        .font(AppFont.badgeSmall)
                        .foregroundStyle(AppColor.textTertiary)
                        .padding(Spacing.xs)
                }
            }

            ForEach(entries) { entry in
                LineMark(
                    x: .value("Date", entry.date),
                    y: .value("Value", entry.value)
                )
                .foregroundStyle(panel.tint)
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("Date", entry.date),
                    y: .value("Value", entry.value)
                )
                .foregroundStyle(pointTint(for: entry))
                .symbolSize(60)
            }

            if let selected = selectedEntry {
                RuleMark(x: .value("Date", selected.date))
                    .foregroundStyle(AppColor.textTertiary)
                    .lineStyle(.init(lineWidth: 1))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        selectionCallout(selected)
                    }
            }
        }
        .chartXSelection(value: $selectedDate)
        .appSensoryFeedback(.selection, trigger: selectedEntry?.id)
        .frame(height: 200)
        .chartXAxis {
            AxisMarks(values: .stride(by: chartXStride.component, count: chartXStride.count)) { _ in
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

    /// Colours a draw by where it sits against the typical range, so an
    /// out-of-range point reads at a glance.
    private func pointTint(for entry: LabValue) -> Color {
        LabRangeStatus(value: entry.value, panel: panel, sex: userSex)?.tint ?? panel.tint
    }

    /// The draw nearest the scrubbed date.
    private var selectedEntry: LabValue? {
        guard let selectedDate else { return nil }
        return entries.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private func selectionCallout(_ entry: LabValue) -> some View {
        VStack(spacing: Spacing.xxs) {
            Text("\(LabValueFormat.string(entry.value)) \(panel.canonicalUnit)")
                .font(AppFont.scaled(13, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
            Text(entry.date.formatted(.dateTime.day().month(.abbreviated).year()))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .glassSurface(cornerRadius: Spacing.chipCornerRadius)
    }

    /// Picks an x-axis stride from the date span so the axis never
    /// becomes a wall of labels: weekly under 45 days, monthly up to
    /// six months, quarterly beyond.
    private var chartXStride: (component: Calendar.Component, count: Int) {
        guard let first = entries.first, let last = entries.last else { return (.month, 1) }
        let days = Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 0
        if days < 45 { return (.weekOfYear, 1) }
        if days <= 180 { return (.month, 1) }
        return (.month, 3)
    }

    // MARK: - History list

    private var historyCard: some View {
        GlassCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("History")
                    .font(AppFont.eyebrow)
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
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .monospacedDigit()
                    if let source = entry.source, !source.isEmpty {
                        Text(source)
                            .font(AppFont.scaled(11))
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(1)
                    } else if let note = entry.note, !note.isEmpty {
                        Text(note)
                            .font(AppFont.scaled(11))
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(LabValueFormat.string(entry.value))
                        .font(AppFont.scaled(16, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                    Text(panel.canonicalUnit)
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                }
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.35))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityHint("Opens this entry to edit")
        .contextMenu {
            Button { editingEntry = entry } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                pendingDelete = entry
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

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}

/// Where a reading sits against its panel's typical range. This, not the
/// direction of change, is what a lab row colours: a rising LDL and a
/// rising HDL mean opposite things.
enum LabRangeStatus {
    case below, within, above

    init?(value: Double, panel: LabPanel, sex: BiologicalSex) {
        guard let range = panel.typicalRange(for: sex) else { return nil }
        if value < range.lowerBound {
            self = .below
        } else if value > range.upperBound {
            self = .above
        } else {
            self = .within
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .within: "In range"
        case .below:  "Below range"
        case .above:  "Above range"
        }
    }

    var tint: Color {
        switch self {
        case .within: AppColor.positive
        case .below:  AppColor.belowRange
        case .above:  AppColor.negative
        }
    }
}

/// One way to print a lab value everywhere: whole numbers bare, small
/// values to two places, the rest to one — with the locale's separator.
enum LabValueFormat {
    static func string(_ value: Double) -> String {
        let digits: ClosedRange<Int> = value.truncatingRemainder(dividingBy: 1) == 0 ? 0...0 : (abs(value) < 10 ? 0...2 : 0...1)
        return value.formatted(.number.precision(.fractionLength(digits)).grouping(.never))
    }
}
