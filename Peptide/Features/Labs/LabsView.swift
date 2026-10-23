import SwiftUI

/// Top-level labs surface. Headline grid of every panel the user
/// has logged (latest value + trend arrow), grouped by category
/// (sex hormones / growth / thyroid / metabolic / lipids / organ
/// health / other). Tap a row → per-panel chart + history. "+" in
/// the toolbar → log a new value.
///
/// Empty state surfaces the value prop ("lipids, glucose, vitamin
/// D…") rather than a blank screen — first impression matters when
/// the feature has zero data on a fresh install.
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
    @State private var pendingDelete: LabValue?
    @State private var storeService = StoreService.shared
    @State private var scanningReport = false
    @State private var showScanPaywall = false
    @State private var showScanConsent = false

    private func byCategory(
        _ summaries: [LabDataLogic.LatestSummary]
    ) -> [(LabPanel.Category, [LabDataLogic.LatestSummary])] {
        let grouped = Dictionary(grouping: summaries) { $0.latest.panel.category }
        return LabPanel.Category.allCases.compactMap { cat in
            guard let rows = grouped[cat], !rows.isEmpty else { return nil }
            return (cat, rows)
        }
    }

    var body: some View {
        // Scans the whole lab history, so it runs once per update.
        let summaries = dataStore.latestLabSummaries
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    if summaries.isEmpty {
                        emptyState
                    } else {
                        introHeader(count: summaries.count)
                        ForEach(Array(byCategory(summaries).enumerated()), id: \.element.0) { index, group in
                            section(for: group.0, rows: group.1)
                                .sectionAppear(index: index)
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
                        Haptics.impact(.light)
                        startLabScan()
                    } label: {
                        Image(systemName: "doc.text.viewfinder")
                            .font(AppFont.scaled(20))
                            .foregroundStyle(AppColor.accentPrimary)
                    }
                    .accessibilityLabel("Scan a lab report")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Haptics.impact(.light)
                        creatingEntry = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(AppFont.scaled(20))
                            .foregroundStyle(AppColor.accentPrimary)
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
                    defaultPanel: mostRecentPanel(in: summaries),
                    sex: dataStore.profile.bodyMetrics.sex,
                    onSave: { value in
                        AppAnimation.with(AppAnimation.springSnappy) { dataStore.saveLabValue(value) }
                        creatingEntry = false
                    },
                    onDelete: nil,
                    onCancel: { creatingEntry = false }
                )
                .liquidGlassPresentation()
            }
            .sheet(isPresented: $scanningReport) {
                LabScanFlow(
                    sex: dataStore.profile.bodyMetrics.sex,
                    onSave: { values in
                        AppAnimation.with(AppAnimation.springSnappy) {
                            for value in values { dataStore.saveLabValue(value) }
                        }
                        scanningReport = false
                    },
                    onClose: { scanningReport = false }
                )
                .liquidGlassPresentation()
            }
            .sheet(isPresented: $showScanPaywall, onDismiss: continueLabScan) {
                PaywallView(source: .labScan)
                    .environment(dataStore)
                    .liquidGlassPresentation()
            }
            .sheet(isPresented: $showScanConsent, onDismiss: resumeAfterScanConsent) {
                AIConsentSheet(whatIsSent: "The photos or PDF pages of the lab report you scan.")
                    .liquidGlassPresentation()
            }
            .sheet(item: $editingEntry) { entry in
                LabEntryEditor(
                    initial: entry,
                    sex: dataStore.profile.bodyMetrics.sex,
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
                "Delete the latest entry?",
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
        }
        .presentationSizing(.page)
    }

    /// Lab scanning reads a report with Claude, so it sits behind the same
    /// Pro entitlement as the other AI features, then the one-time
    /// AI-sharing consent.
    private func startLabScan() {
        guard storeService.canAccessAIFeatures else {
            showScanPaywall = true
            return
        }
        continueLabScan()
    }

    /// Also resumes after the paywall closes; stops quietly if the user
    /// didn't upgrade.
    private func continueLabScan() {
        guard storeService.canAccessAIFeatures else { return }
        guard AIDataConsent.isGranted else {
            showScanConsent = true
            return
        }
        scanningReport = true
    }

    /// Opens the scanner only if the user allowed sharing.
    private func resumeAfterScanConsent() {
        if AIDataConsent.isGranted { scanningReport = true }
    }

    /// The panel the user logged most recently, so a new entry starts there.
    private func mostRecentPanel(in summaries: [LabDataLogic.LatestSummary]) -> LabPanel? {
        summaries.max(by: { $0.latest.date < $1.latest.date })?.latest.panel
    }

    // MARK: - Sections

    private func introHeader(count: Int) -> some View {
        Text("^[\(count) marker](inflect: true) tracked")
            .font(AppFont.subheadline)
            .foregroundStyle(AppColor.textSecondary)
            .contentTransition(.numericText())
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
                .padding(.horizontal, Spacing.xs)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: Spacing.xs) {
                ForEach(rows) { summary in
                    row(for: summary)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.95).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
        }
    }

    private func row(for summary: LabDataLogic.LatestSummary) -> some View {
        Button {
            detailPanel = summary.latest.panel
        } label: {
            LabSummaryRow(summary: summary, sex: dataStore.profile.bodyMetrics.sex)
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .contextMenu {
            Button {
                editingEntry = summary.latest
            } label: {
                Label("Edit latest", systemImage: "pencil")
            }
            Button(role: .destructive) {
                pendingDelete = summary.latest
            } label: {
                Label("Delete latest", systemImage: "trash")
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        EmptyStateView(
            icon: "testtube.2",
            title: "Track your blood work",
            message: "Lipids, glucose, vitamin D, iron and hormones. See how training and nutrition move your numbers.",
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
    /// Picks the sex-specific reference range for the status chip.
    let sex: BiologicalSex
    /// Grows the panel tile with Dynamic Type so its short name never
    /// has to shrink to fit.
    @ScaledMetric(relativeTo: .footnote) private var tileSize: CGFloat = 40

    private var panel: LabPanel { summary.latest.panel }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.dateTimeStyle = .named
        f.formattingContext = .beginningOfSentence
        return f
    }()

    /// "Today", "Yesterday", "3 days ago". The draw date is picked without
    /// a time, so it's compared by day; hours since it was logged would
    /// read "3 hr. ago" for a morning draw.
    private static func drawDay(_ date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let day = calendar.startOfDay(for: date)
        return day == today
            ? relative.localizedString(from: DateComponents(day: 0))
            : relative.localizedString(for: day, relativeTo: today)
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: Spacing.concentric(in: Spacing.cardCornerRadius, inset: Spacing.md),
                    style: .continuous
                )
                .fill(panel.tint.opacity(0.20))
                Text(panel.shortName)
                    .font(AppFont.scaled(11, weight: .heavy))
                    .foregroundStyle(panel.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, Spacing.xxs)
            }
            .frame(width: tileSize, height: tileSize)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(panel.displayName)
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                Text(Self.drawDay(summary.latest.date))
                    .font(AppFont.scaled(11))
                    .foregroundStyle(AppColor.textSecondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

            valueAndTrend

            Image(systemName: "chevron.right")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
        }
        .padding(Spacing.md)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var rangeStatus: LabRangeStatus? {
        LabRangeStatus(value: summary.latest.value, panel: panel, sex: sex)
    }

    /// Value and unit, then direction in neutral ink. Only the range
    /// status is coloured — whether "up" is good depends on the marker.
    private var valueAndTrend: some View {
        HStack(spacing: Spacing.xs) {
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(LabValueFormat.string(summary.latest.value))
                        .font(AppFont.scaled(16, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(rangeStatus?.tint ?? AppColor.textPrimary)
                    Text(panel.canonicalUnit)
                        .font(AppFont.badgeSmall)
                        .foregroundStyle(AppColor.textTertiary)
                }
                if let rangeStatus {
                    Text(rangeStatus.label)
                        .font(AppFont.badgeSmall)
                        .foregroundStyle(rangeStatus.tint)
                }
            }
            Image(systemName: trendSymbol)
                .font(AppFont.scaled(11, weight: .heavy))
                .foregroundStyle(AppColor.textSecondary)
                .padding(Spacing.xs)
                .background { Circle().fill(AppColor.textSecondary.opacity(0.12)) }
        }
    }

    private var trendSymbol: String {
        switch summary.trend {
        case .rising:  "arrow.up.right"
        case .falling: "arrow.down.right"
        case .stable:  "minus"
        }
    }

    private var accessibilityLabel: String {
        let v = LabValueFormat.string(summary.latest.value)
        let trendDesc: String
        switch summary.trend {
        case .rising:  trendDesc = String(localized: "trending up")
        case .falling: trendDesc = String(localized: "trending down")
        case .stable:  trendDesc = String(localized: "stable")
        }
        let status: String
        switch rangeStatus {
        case .within?: status = String(localized: "in range")
        case .below?:  status = String(localized: "below range")
        case .above?:  status = String(localized: "above range")
        case nil:      status = ""
        }
        return [
            "\(panel.displayName): \(v) \(panel.canonicalUnit)",
            status,
            trendDesc,
        ].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
