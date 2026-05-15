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
                .font(.system(size: 13, weight: .semibold))
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
                .font(.system(size: 11, weight: .heavy))
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
        VStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColor.accentPrimary.opacity(0.35),
                                AppColor.accentLight.opacity(0.15),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                Image(systemName: "testtube.2")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.top, Spacing.xxl)

            Text("Track your biomarkers")
                .font(AppFont.title2)
                .foregroundStyle(AppColor.textPrimary)

            Text("Testosterone, IGF-1, lipids, thyroid panels. Log a value to chart how your protocols are moving real numbers.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)

            Button {
                creatingEntry = true
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "plus.circle.fill")
                    Text("Log first lab")
                }
                .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.accentPrimary)
            .padding(.top, Spacing.sm)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One row in the labs list — latest value, unit, date relative,
/// trend arrow. Compact enough to fit two-deep stacks on the
/// Labs page without forcing a List (the parent uses ScrollView
/// so it can compose freely with the empty-state).
struct LabSummaryRow: View {
    let summary: LabDataLogic.LatestSummary

    private var panel: LabPanel { summary.latest.panel }

    private static let relative: RelativeDateTimeFormatter = {
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
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(panel.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(panel.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                Text(Self.relative.localizedString(for: summary.latest.date, relativeTo: Date()))
                    .font(.system(size: 11))
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
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.textPrimary)
                Text(panel.canonicalUnit)
                    .font(.system(size: 9, weight: .medium))
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
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color(red: 0.40, green: 0.78, blue: 0.55))
                .padding(6)
                .background { Circle().fill(Color(red: 0.40, green: 0.78, blue: 0.55).opacity(0.15)) }
        case .falling:
            Image(systemName: "arrow.down.right")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color(red: 0.92, green: 0.45, blue: 0.45))
                .padding(6)
                .background { Circle().fill(Color(red: 0.92, green: 0.45, blue: 0.45).opacity(0.15)) }
        case .stable:
            Image(systemName: "minus")
                .font(.system(size: 11, weight: .heavy))
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
