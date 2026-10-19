import SwiftUI

/// "Biomarkers" list on the Biology tab. Section header with an
/// Edit affordance; below it, one
/// `BiomarkerRow` per visible biomarker in the user's curated
/// order.
///
/// Loads snapshots async via `BiomarkerSeriesService` so the view
/// body stays synchronous. Refreshes on appear + when the user
/// returns from Edit; intentionally not on every scene-phase
/// transition (the 14-day series doesn't change minute-to-minute
/// and HealthKit reads cost main-thread time).
struct BiomarkerListSection: View {
    @Environment(DataStore.self) private var dataStore

    /// Which biomarkers to render, in order, from the user's
    /// `BiologyConfig`.
    let visibleBiomarkers: [Biomarker]
    /// Bumped by the parent's pull-to-refresh to force a re-read.
    var reloadID = 0
    var onEditTapped: (() -> Void)?
    var onSelectBiomarker: ((BiomarkerSnapshot) -> Void)?

    @State private var snapshots: [BiomarkerSnapshot] = []
    /// True until the first HealthKit read lands, so rows render as a
    /// shimmering placeholder instead of a column of em-dashes that reads
    /// as "no data". Later refreshes keep the previous values on screen.
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                BiologySectionHeader(title: "Biomarkers")
                if onEditTapped != nil {
                    Button {
                        onEditTapped?()
                    } label: {
                        Text("Edit")
                            .font(AppFont.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.accentLight)
                            .minimumHitArea()
                    }
                    .buttonStyle(.plain)
                }
            }

            if visibleBiomarkers.isEmpty {
                emptyState
            } else if isLoading {
                rows
                    .redacted(reason: .placeholder)
                    .shimmer()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            } else {
                rows
                    .transition(.opacity)
            }
        }
        // Re-key on a hashed identity rather than the full array. Without
        // this, dismissing the Edit sheet re-fires the HealthKit fan-out
        // even when the visible set didn't actually change — the parent
        // re-evaluates `biologyConfig.visibleBiomarkers` and SwiftUI sees
        // a structurally equal array with a fresh identity each time.
        .task(id: LoadKey(biomarkers: visibleBiomarkers.hashValue, reloadID: reloadID)) {
            await refresh()
        }
    }

    private var rows: some View {
        VStack(spacing: Spacing.sm) {
            ForEach(Array(visibleBiomarkers.enumerated()), id: \.element) { index, biomarker in
                let rowSnapshot = snapshot(for: biomarker)
                BiomarkerRow(
                    snapshot: rowSnapshot,
                    onTap: { onSelectBiomarker?(rowSnapshot) }
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                .staggeredAppear(index: index)
            }
        }
        .appAnimation(AppAnimation.springSnappy, value: visibleBiomarkers)
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
        let biomarkers: Int
        let reloadID: Int
    }

    private func snapshot(for biomarker: Biomarker) -> BiomarkerSnapshot {
        snapshots.first { $0.biomarker == biomarker } ?? .empty(biomarker)
    }

    private func refresh() async {
        // LatestLabSummaries returns most-recent-per-panel; the
        // lab tile binds to the very latest sample so any panel
        // wins — the user-facing label still reads the specific
        // panel name (Total testosterone, IGF-1, …).
        let latestLab = dataStore.latestLabSummaries
            .max(by: { $0.latest.date < $1.latest.date })?
            .latest
        let fresh = await BiomarkerSeriesService.snapshots(
            for: visibleBiomarkers,
            weightHistory: dataStore.profile.weightHistory,
            latestLab: latestLab,
            unit: dataStore.profile.bodyMetrics.unit
        )
        AppAnimation.with(AppAnimation.fadeIn) {
            snapshots = fresh
            isLoading = false
        }
    }
}
