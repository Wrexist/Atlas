import SwiftUI

/// Top-level labs surface. Headline grid of every panel the user
/// has logged (latest value + trend arrow), grouped by category
/// (sex hormones / growth / thyroid / metabolic / lipids / organ
/// health / other). Tap a row → per-panel chart + history. "+" in
/// the toolbar → log a new value.
///
/// Empty state surfaces the value prop ("track testosterone, IGF-1,
/// thyroid…") rather than a blank screen — first impression
/// matters when the feature has zero data on a fresh install.
struct LabsView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    /// True when presented as a sheet (e.g. from Biology) — adds an
    /// explicit Done button so the user isn't left to discover the
    /// swipe-to-dismiss gesture.
    var presentedModally: Bool = false
    @State private var editingEntry: LabValue?
    @State private var creatingEntry: Bool = false
    @State private var detailPanel: LabPanel?

    private var summaries: [LabDataLogic.LatestSummary] {
        dataStore.latestLabSummaries
    }

    private var groupedSummaries: [(LabPanel.Category, [LabDataLogic.LatestSummary])] {
        let grouped = Dictionary(grouping: summaries) { $0.latest.panel.category }
        return LabPanel.Category.allCases.compactMap { cat in
            guard let rows = grouped[cat], !rows.isEmpty else { return nil }
            return (cat, rows)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    if summaries.isEmpty {
                        emptyState
                    } else {
                        introHeader
                        ForEach(groupedSummaries, id: \.0) { category, rows in
                            section(for: category, rows: rows)
                        }
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxxxl)
            }
            .scrollIndicators(.hidden)
            .background(AppColor.background)
            .navigationTitle("Labs")
            .toolbar {
                if presentedModally {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        creatingEntry = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AppColor.accentLight)
                    }
                    .accessibilityLabel("Log a new lab value")
                }
            }
            .navigationDestination(item: $detailPanel) { panel in
                LabPanelDetailView(panel: panel)
            }
            .sheet(isPresented: $creatingEntry) {
                LabEntryEditor(
                    initial: nil,
                    sex: dataStore.profile.bodyMetrics.sex,
                    onSave: { value in
                        dataStore.saveLabValue(value)
                        creatingEntry = false
                    },
                    onDelete: nil,
                    onCancel: { creatingEntry = false }
                )
            }
            .sheet(item: $editingEntry) { entry in
                LabEntryEditor(
                    initial: entry,
                    sex: dataStore.profile.bodyMetrics.sex,
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
        }
    }

    // MARK: - Sections

    private var introHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lab work")
                .font(AppFont.scaled(13, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.accentLight.opacity(0.85))
            Text("\(summaries.count) panels tracked")
                .font(AppFont.title2)
                .foregroundStyle(AppColor.textPrimary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(
        for category: LabPanel.Category,
        rows: [LabDataLogic.LatestSummary]
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(category.displayName)
                .font(AppFont.scaled(11, weight: .heavy))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.textTertiary)
                .padding(.horizontal, 4)

            VStack(spacing: Spacing.xs) {
                ForEach(rows) { summary in
                    row(for: summary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(for summary: LabDataLogic.LatestSummary) -> some View {
        Button {
            detailPanel = summary.latest.panel
        } label: {
            LabSummaryRow(summary: summary)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                editingEntry = summary.latest
            } label: {
                Label("Edit latest", systemImage: "pencil")
            }
            Button(role: .destructive) {
                dataStore.deleteLabValue(id: summary.latest.id)
            } label: {
                Label("Delete latest", systemImage: "trash")
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        EmptyStateView(
            icon: "testtube.2",
            title: "Track your biomarkers",
            message: "Testosterone, IGF-1, lipids, thyroid panels. Log a value to chart how your protocols are moving real numbers.",
            action: .init(title: "Log first lab", icon: "plus.circle.fill") {
                creatingEntry = true
            }
        )
        .padding(.top, Spacing.xxl)
    }
}

/// One row in the labs list — latest value, unit, date relative,
/// trend arrow. Compact enough to fit two-deep stacks on the
/// Labs page without forcing a List (the parent uses ScrollView
/// so it can compose freely with the empty-state).
struct LabSummaryRow: View {
    let summary: LabDataLogic.LatestSummary

    private var panel: LabPanel { summary.latest.panel }

    // Non-Sendable Foundation formatter; thread-safe for read-only
    // use after configuration.
    nonisolated(unsafe) private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(panel.tint.opacity(0.20))
                    .frame(width: 38, height: 38)
                Text(panel.shortName)
                    .font(AppFont.scaled(11, weight: .heavy))
                    .foregroundStyle(panel.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(panel.displayName)
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                Text(Self.relative.localizedString(for: summary.latest.date, relativeTo: Date()))
                    .font(AppFont.scaled(11))
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

            valueAndTrend
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var valueAndTrend: some View {
        HStack(spacing: 4) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(formatted(summary.latest.value))
                    .font(AppFont.scaled(16, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.textPrimary)
                Text(panel.canonicalUnit)
                    .font(AppFont.scaled(8, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
            }
            trendBadge
        }
    }

    @ViewBuilder
    private var trendBadge: some View {
        switch summary.trend {
        case .rising:
            Image(systemName: "arrow.up.right")
                .font(AppFont.scaled(11, weight: .heavy))
                .foregroundStyle(AppColor.positive)
                .padding(6)
                .background { Circle().fill(AppColor.positive.opacity(0.15)) }
        case .falling:
            Image(systemName: "arrow.down.right")
                .font(AppFont.scaled(11, weight: .heavy))
                .foregroundStyle(AppColor.negative)
                .padding(6)
                .background { Circle().fill(AppColor.negative.opacity(0.15)) }
        case .stable:
            Image(systemName: "minus")
                .font(AppFont.scaled(11, weight: .heavy))
                .foregroundStyle(AppColor.textSecondary)
                .padding(6)
                .background { Circle().fill(AppColor.textSecondary.opacity(0.12)) }
        }
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

    private var accessibilityLabel: String {
        let v = formatted(summary.latest.value)
        let trendDesc: String
        switch summary.trend {
        case .rising:  trendDesc = String(localized: "trending up")
        case .falling: trendDesc = String(localized: "trending down")
        case .stable:  trendDesc = String(localized: "stable")
        }
        return "\(panel.displayName): \(v) \(panel.canonicalUnit), \(trendDesc)"
    }
}
