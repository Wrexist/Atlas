import SwiftUI

/// Root of the Biology tab. Resolves the Bio Age state — locked /
/// building baseline / unlocked — against the user's Pro
/// entitlement + HealthKit history. Hosts the cosmic backdrop,
/// the hero, the upsell card (only when locked), the biomarker
/// list, the edit sheet, and the per-biomarker detail sheet.
struct BiologyView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    @State private var storeService = StoreService.shared

    @State private var resolved: BioAgeStateResolver.Resolved = .init(
        state: .locked,
        chronologicalAge: BioAgeStateResolver.chronologicalAgeFallback
    )
    @State private var showPaywall = false
    @State private var showEditSheet = false
    @State private var showLabs = false
    /// Drives the per-biomarker detail sheet. Identifiable wrapper
    /// so `.sheet(item:)` lifecycle is clean across taps.
    @State private var detailItem: BiomarkerDetailItem?

    private struct BiomarkerDetailItem: Identifiable {
        let biomarker: Biomarker
        let snapshot: BiomarkerSnapshot
        var id: Biomarker { biomarker }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    BioAgeHeroSection(
                        state: resolved.state,
                        chronologicalAge: resolved.chronologicalAge,
                        asOfDate: Date(),
                        onUnlockTapped: { presentPaywall() }
                    )

                    if case .locked = resolved.state {
                        PremiumPromoCard(
                            eyebrow: "ATLAS PRO",
                            title: "View Your Biological Age",
                            subtitle: "Track how you're aging and discover which habits move your Bio Age.",
                            ctaLabel: "View",
                            qualifier: "Available for users 18+",
                            onTap: { presentPaywall() }
                        )
                    }

                    BiomarkerListSection(
                        visibleBiomarkers: dataStore.profile.biologyConfig.visibleBiomarkers,
                        onEditTapped: { showEditSheet = true },
                        onSelectBiomarker: { biomarker in openDetail(for: biomarker) }
                    )

                    disclaimerFootnote
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
            }
            .background {
                CosmicBackdrop(intensity: 0.55)
                    .ignoresSafeArea()
            }
            .navigationTitle("Biology")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .liquidGlassPresentation()
            }
            .sheet(isPresented: $showEditSheet, onDismiss: persistConfigChanges) {
                EditBiomarkersSheet(
                    config: editConfigBinding,
                    isPro: storeService.isProUser,
                    onDismiss: persistConfigChanges
                )
                .liquidGlassPresentation()
            }
            .sheet(item: $detailItem) { item in
                BiomarkerDetailSheet(
                    biomarker: item.biomarker,
                    initialSnapshot: item.snapshot,
                    historicalFetcher: { await fetchHistorical(for: item.biomarker) }
                )
                .liquidGlassPresentation()
            }
            .sheet(isPresented: $showLabs) {
                LabsView()
                    .environment(dataStore)
            }
            .onAppear { consumePendingLabsDeepLink() }
            .onChange(of: appState.pendingLabsOpen) { _, _ in
                consumePendingLabsDeepLink()
            }
        }
        .task { await refreshState() }
        .onChange(of: storeService.isProUser) { _, _ in
            Task { await refreshState() }
        }
        .onChange(of: dataStore.profile.age) { _, _ in
            Task { await refreshState() }
        }
    }

    /// Consumes the cross-tab "open Labs" deep-link flag set by the
    /// Home overview card's latest-lab insight tap. Cleared the
    /// moment we present the sheet so re-appearing the tab doesn't
    /// re-fire. Mirrors the consumer that lived on the retired
    /// `InsightsView` so the deep-link from `HomeView.onTapInsight`
    /// still lands on the right surface after the Insights → Biology
    /// rename.
    private func consumePendingLabsDeepLink() {
        guard appState.pendingLabsOpen else { return }
        appState.pendingLabsOpen = false
        showLabs = true
    }

    // MARK: - Bio Age resolution

    private func refreshState() async {
        let weightDelta = computeWeightDelta30d()
        resolved = await BioAgeStateResolver.resolve(
            chronologicalAge: dataStore.profile.age,
            weightDeltaKg30d: weightDelta,
            isPro: storeService.isProUser
        )
    }

    private func computeWeightDelta30d() -> Double? {
        let history = dataStore.profile.weightHistory.sorted { $0.date < $1.date }
        guard history.count >= 2, let latest = history.last else { return nil }
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let baseline = history.first { $0.date >= cutoff } ?? history.first!
        guard baseline.id != latest.id else { return nil }
        return latest.kg - baseline.kg
    }

    // MARK: - BiologyConfig persistence

    /// Binding into the editable sheet. Reads from
    /// `dataStore.profile.biologyConfig` and writes back through
    /// the same path. The `onDismiss` save batches mutations so
    /// a reorder + show + hide session lands as one persist call.
    private var editConfigBinding: Binding<BiologyConfig> {
        Binding(
            get: { dataStore.profile.biologyConfig },
            set: { dataStore.profile.biologyConfig = $0 }
        )
    }

    private func persistConfigChanges() {
        dataStore.persistProfile()
    }

    // MARK: - Detail sheet routing

    private func openDetail(for biomarker: Biomarker) {
        if dataStore.profile.hapticFeedbackEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        // Present the sheet immediately with an empty snapshot, then
        // let it fill in via `historicalFetcher`. Fetching before
        // setting `detailItem` raced on rapid taps: the second tap
        // would overwrite the first `detailItem`, and SwiftUI's
        // `.sheet(item:)` dismisses the first sheet mid-flight on
        // an Identifiable change.
        detailItem = BiomarkerDetailItem(
            biomarker: biomarker,
            snapshot: .empty(biomarker)
        )
    }

    /// 90-day fetcher passed to the detail sheet. Same code path
    /// as `openDetail`, just with the long-window day count so
    /// the chart can show seasonal trends.
    private func fetchHistorical(for biomarker: Biomarker) async -> BiomarkerSnapshot? {
        await snapshot(for: biomarker, days: BiomarkerSeriesService.detailWindowDays)
    }

    private func snapshot(for biomarker: Biomarker, days: Int) async -> BiomarkerSnapshot {
        let latestLab = dataStore.latestLabSummaries
            .max(by: { $0.latest.date < $1.latest.date })?
            .latest
        let snapshots = await BiomarkerSeriesService.snapshots(
            for: [biomarker],
            weightHistory: dataStore.profile.weightHistory,
            latestLab: latestLab,
            days: days
        )
        return snapshots.first ?? .empty(biomarker)
    }

    // MARK: - Paywall

    private func presentPaywall() {
        if dataStore.profile.hapticFeedbackEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        showPaywall = true
    }

    private var disclaimerFootnote: some View {
        Text("Atlas estimates based on your personal biometrics. Not medical advice.")
            .font(.system(size: 11))
            .foregroundStyle(AppColor.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.lg)
    }
}

#Preview {
    BiologyView()
        .environment(DataStore(seedSampleData: true))
        .environment(AppState())
        .preferredColorScheme(.dark)
}
