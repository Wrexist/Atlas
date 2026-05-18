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
                        // Pro biomarkers stay in profile.biologyConfig
                        // after a subscription lapse so the user's
                        // selection is preserved across re-up — but
                        // we filter them out of the visible list when
                        // !isProUser (audit Biology MED 11).
                        // EditBiomarkersSheet already blocks adding
                        // new Pro entries; this closes the rendering
                        // side of the gate.
                        visibleBiomarkers: dataStore.profile.biologyConfig.visibleBiomarkers
                            .filter { storeService.isProUser || !$0.requiresPro },
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
        }
        .task { await refreshState() }
        .onChange(of: storeService.isProUser) { _, _ in
            Task { await refreshState() }
        }
        .onChange(of: dataStore.profile.age) { _, _ in
            Task { await refreshState() }
        }
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
        // Calendar-day cutoff so DST flips don't shift the boundary an
        // hour and so the window is "30 days ago" rather than "30 ×
        // 86,400 seconds ago" (audit Biology L17).
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cutoff = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        // Pick the entry closest to (but on/after) the cutoff so the
        // delta represents the actual 30-day window rather than the
        // first-ever measurement when the cutoff happens to predate
        // the user's whole history.
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
        // Fetch the 14-day initial snapshot so the sheet has
        // something to render the moment it mounts. The sheet
        // upgrades to the 90-day chart on its own .task via the
        // historicalFetcher closure below.
        Task {
            let snapshot = await snapshot(for: biomarker, days: BiomarkerSeriesService.windowDays)
            detailItem = BiomarkerDetailItem(biomarker: biomarker, snapshot: snapshot)
        }
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
