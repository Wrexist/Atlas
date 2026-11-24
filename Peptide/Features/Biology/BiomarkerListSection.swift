import SwiftUI

/// "Biomarkers" on the Biology tab. Section header with an Edit
/// affordance; below it, one `BiomarkerTile` per visible biomarker in
/// the user's curated order, two small cards to a row. Wearable
/// biomarkers with no data yet sit under the cards as compact, dimmed
/// tiles, or as one line when they all wait for the same thing.
///
/// Loads snapshots async via `BiomarkerSeriesService` so the view
/// body stays synchronous. Refreshes on appear + when the user
/// returns from Edit; intentionally not on every scene-phase
/// transition (the 14-day series doesn't change minute-to-minute
/// and HealthKit reads cost main-thread time).
struct BiomarkerListSection: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Which biomarkers to render, in order, from the user's
    /// `BiologyConfig`.
    let visibleBiomarkers: [Biomarker]
    /// Bumped by the parent's pull-to-refresh to force a re-read.
    var reloadID = 0
    var onEditTapped: (() -> Void)?
    var onSelectBiomarker: ((BiomarkerSnapshot) -> Void)?
    var tileSizes: [Biomarker: BiomarkerTileSize] = [:]
    var onResize: ((Biomarker, BiomarkerTileSize) -> Void)?

    @State private var snapshots: [BiomarkerSnapshot] = []
    /// True until the first HealthKit read lands, so rows render as a
    /// shimmering placeholder instead of a column of em-dashes that reads
    /// as "no data". Later refreshes keep the previous values on screen.
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                HomeSectionHeader(title: "Biomarkers")
                if onEditTapped != nil {
                    Button {
                        onEditTapped?()
                    } label: {
                        Text("Edit")
                            .font(AppFont.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.accentPrimary)
                            // Trailing, so the word ends on the card edge
                            // instead of centring inside a 44 pt target.
                            .frame(
                                minWidth: Spacing.minimumHitTarget,
                                minHeight: Spacing.minimumHitTarget,
                                alignment: .trailing
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            }

            if visibleBiomarkers.isEmpty {
                emptyState
            } else if isLoading {
                rows(visibleBiomarkers)
                    .redacted(reason: .placeholder)
                    .shimmer()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            } else {
                let split = Biomarker.splitAwaitingWearable(visibleBiomarkers) { snapshot(for: $0).latest != nil }
                if !split.tiles.isEmpty {
                    rows(split.tiles)
                        .transition(.opacity)
                }
                if !split.awaitingWearable.isEmpty {
                    awaitingWearableTiles(split.awaitingWearable)
                        .transition(.opacity)
                }
            }
        }
        // Keyed on every input the snapshots read, compared by value: a
        // weigh-in, a new lab or a unit switch re-reads, while an Edit
        // sheet that didn't change the visible set does not.
        .task(id: LoadKey(
            biomarkers: visibleBiomarkers,
            weightHistory: dataStore.profile.weightHistory,
            latestLab: latestLab,
            unit: dataStore.profile.bodyMetrics.unit,
            reloadID: reloadID
        )) {
            await refresh()
        }
    }

    /// One calm line when every waiting metric waits for the same thing;
    /// identical ghost tiles in a row only repeated it. Per-tile ghosts
    /// stay when the reasons differ.
    @ViewBuilder
    private func awaitingWearableTiles(_ biomarkers: [Biomarker]) -> some View {
        let reasons = Set(biomarkers.map { awaitingReason(for: $0) })
        if biomarkers.count > 1, reasons.count == 1, let reason = reasons.first {
            awaitingSummary(biomarkers, reason: reason)
        } else {
            awaitingGrid(biomarkers)
        }
    }

    private func awaitingSummary(_ biomarkers: [Biomarker], reason: AwaitingReason) -> some View {
        let names = biomarkers.map(\.shortName).formatted(.list(type: .and))
        return HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: reason == .needsWatch ? "applewatch" : "heart.text.square")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textTertiary)
                .accessibilityHidden(true)
            Text(reason == .needsWatch
                ? String(localized: "\(names) appear here once data arrives.")
                : String(localized: "\(names) appear here once Apple Health is connected."))
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        .accessibilityElement(children: .combine)
    }

    /// Three to a row; one per row at accessibility sizes, where a
    /// third of the width can't hold the name.
    private func awaitingGrid(_ biomarkers: [Biomarker]) -> some View {
        let columnCount = dynamicTypeSize.isAccessibilitySize ? 1 : 3
        let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: columnCount)
        return LazyVGrid(columns: columns, spacing: Spacing.sm) {
            ForEach(biomarkers, id: \.self) { biomarker in
                AwaitingBiomarkerTile(
                    biomarker: biomarker,
                    caption: awaitingReason(for: biomarker) == .needsWatch
                        ? String(localized: "Needs Watch")
                        : String(localized: "No data yet"),
                    onTap: { onSelectBiomarker?(.empty(biomarker)) }
                )
            }
        }
    }

    private enum AwaitingReason: Hashable {
        case needsWatch
        case noData
    }

    /// Steps also come from the iPhone, so only the Watch-only metrics
    /// say they need one.
    private func awaitingReason(for biomarker: Biomarker) -> AwaitingReason {
        dataStore.profile.healthConnected && biomarker != .stepsBaseline ? .needsWatch : .noData
    }

    private func rows(_ biomarkers: [Biomarker]) -> some View {
        let layout = BiomarkerTileSize.rows(for: biomarkers, sizes: tileSizes)
        return VStack(spacing: Spacing.sm) {
            ForEach(Array(layout.enumerated()), id: \.element) { index, row in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    ForEach(row, id: \.self) { biomarker in
                        tile(for: biomarker)
                    }
                    // A small card without a partner keeps its half, so
                    // the column lines up with the pairs above it. Alone
                    // in the section there is no column to keep, and the
                    // empty half read as a missing card.
                    if row.count == 1, layout.count > 1, tileSize(for: row[0]) == .small {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                    }
                }
                // Both cards of a row take the taller one's height, so
                // the glass edges line up.
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .staggeredAppear(index: index)
            }
        }
        .appAnimation(AppAnimation.springSnappy, value: layout)
    }

    private func tile(for biomarker: Biomarker) -> some View {
        let tileSnapshot = snapshot(for: biomarker)
        return BiomarkerTile(
            snapshot: tileSnapshot,
            size: tileSize(for: biomarker),
            unit: dataStore.profile.bodyMetrics.unit,
            healthConnected: dataStore.profile.healthConnected,
            onTap: { onSelectBiomarker?(tileSnapshot) },
            onResize: { onResize?(biomarker, $0) }
        )
    }

    private func tileSize(for biomarker: Biomarker) -> BiomarkerTileSize {
        tileSizes[biomarker] ?? .default
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "list.bullet.rectangle",
            title: "No biomarkers showing",
            message: "You've hidden every biomarker.",
            action: .init(title: "Choose biomarkers") { onEditTapped?() },
            style: .compact
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }

    private struct LoadKey: Equatable {
        let biomarkers: [Biomarker]
        let weightHistory: [WeightEntry]
        let latestLab: LabValue?
        let unit: MeasurementUnit
        let reloadID: Int
    }

    /// LatestLabSummaries returns most-recent-per-panel; the lab tile
    /// binds to the very latest sample so any panel wins — the
    /// user-facing label still reads the specific panel name (Total
    /// testosterone, IGF-1, …).
    private var latestLab: LabValue? {
        dataStore.latestLabSummaries
            .max(by: { $0.latest.date < $1.latest.date })?
            .latest
    }

    private func snapshot(for biomarker: Biomarker) -> BiomarkerSnapshot {
        snapshots.first { $0.biomarker == biomarker } ?? .empty(biomarker)
    }

    private func refresh() async {
        let fresh = await BiomarkerSeriesService.snapshots(
            for: visibleBiomarkers,
            weightHistory: dataStore.profile.weightHistory,
            latestLab: latestLab,
            unit: dataStore.profile.bodyMetrics.unit
        )
        // A superseded refresh must not overwrite a newer row list.
        guard !Task.isCancelled else { return }
        AppAnimation.with(AppAnimation.fadeIn) {
            snapshots = fresh
            isLoading = false
        }
    }
}
