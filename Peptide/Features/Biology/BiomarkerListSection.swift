import SwiftUI

/// "Other biomarkers" list on the Biology tab. Section header
/// with an Edit affordance (wires up in commit 8); below it, one
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

    /// Which biomarkers to render, in order. Sourced from the
    /// user's BiologyConfig in commit 7; for this commit, the
    /// caller passes `Biomarker.defaultVisible` so the list shows
    /// up without persistence wiring.
    let visibleBiomarkers: [Biomarker]
    var onEditTapped: (() -> Void)?
    var onSelectBiomarker: ((Biomarker) -> Void)?

    @State private var snapshots: [BiomarkerSnapshot] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Other biomarkers")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: 0)
                if onEditTapped != nil {
                    Button {
                        onEditTapped?()
                    } label: {
                        Text("Edit")
                            .font(AppFont.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.accentLight)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            }

            if visibleBiomarkers.isEmpty {
                emptyState
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(visibleBiomarkers, id: \.self) { biomarker in
                        BiomarkerRow(
                            snapshot: snapshot(for: biomarker),
                            onTap: { onSelectBiomarker?(biomarker) }
                        )
                    }
                }
            }
        }
        // Re-key on a hashed identity rather than the full array. Without
        // this, dismissing the Edit sheet re-fires the HealthKit fan-out
        // even when the visible set didn't actually change — the parent
        // re-evaluates `biologyConfig.visibleBiomarkers` and SwiftUI sees
        // a structurally equal array with a fresh identity each time.
        .task(id: visibleBiomarkers.hashValue) { await refresh() }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "list.bullet.rectangle.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AppColor.textTertiary)
            Text("You've hidden every biomarker.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            Button("Open Edit") { onEditTapped?() }
                .font(AppFont.caption)
                .foregroundStyle(AppColor.accentLight)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xl)
        .background {
            RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                .fill(AppColor.surfaceSecondary.opacity(0.45))
        }
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
            latestLab: latestLab
        )
        snapshots = fresh
    }
}
