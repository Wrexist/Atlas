import SwiftUI

/// Root of the Biology tab. Resolves the Biological Age state — locked /
/// building baseline / unlocked — against the user's Pro
/// entitlement + HealthKit history. Hosts the cosmic backdrop,
/// the hero, the upsell card (only when locked), the biomarker
/// list, the edit sheet, and the per-biomarker detail sheet.
struct BiologyView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    @State private var storeService = StoreService.shared

    /// `nil` until the first `refreshState()` lands. Defaulting to
    /// `.locked` flashed the upsell at Pro users on every launch.
    @State private var resolved: BioAgeStateResolver.Resolved?
    @State private var showPaywall = false
    @State private var showEditSheet = false
    @State private var showLabs = false
    @State private var showBioAgeExplainer = false
    /// True when Health is connected but a read type added since (VO2 max)
    /// has never been put to the user.
    @State private var needsHealthUpgrade = false
    /// Bumped by pull-to-refresh and a fresh Health grant so the
    /// biomarker list re-reads HealthKit without re-keying on config.
    @State private var reloadID = 0
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
                        state: resolved?.state,
                        chronologicalAge: resolved?.chronologicalAge
                            ?? BioAgeStateResolver.chronologicalAgeFallback,
                        noHealthData: dataStore.profile.healthConnected
                            && resolved?.inputs?.healthDataDays == 0,
                        metricShortcuts: visibleBiomarkers,
                        onSelectMetric: { openDetail(for: $0) },
                        onExplainTapped: { showBioAgeExplainer = true }
                    )
                    .sectionAppear(index: 0)

                    if case .locked? = resolved?.state {
                        PremiumPromoCard(
                            eyebrow: "ATLAS PRO",
                            title: "See your Biological Age",
                            subtitle: "Track how you're aging and discover which habits move your Biological Age.",
                            ctaLabel: "Unlock",
                            qualifier: "Available for users 18+",
                            onTap: { presentPaywall() }
                        )
                        .sectionAppear(index: 1)
                    }

                    healthPrompt

                    bioAgeDetail

                    BiomarkerListSection(
                        visibleBiomarkers: visibleBiomarkers,
                        reloadID: reloadID,
                        onEditTapped: { showEditSheet = true },
                        onSelectBiomarker: { snapshot in
                            openDetail(for: snapshot.biomarker, seed: snapshot)
                        }
                    )

                    GlassEntryRow(
                        icon: "cross.vial.fill",
                        title: "Labs",
                        subtitle: labsSubtitle,
                        action: openLabs
                    )
                    .accessibilityHint("Opens your blood-work results")
                    .biologyCardReveal()

                    disclaimerFootnote
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, Spacing.xxxxl)
                // iPad content cap — Biology rows benefit from a
                // readable measure (Phase 5.8 partial).
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await reload() }
            .background {
                CosmicBackdrop(intensity: 0.55)
                    .ignoresSafeArea()
            }
            .navigationTitle("Biology")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ProfileToolbarButton() }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: .performanceAge)
                    .liquidGlassPresentation()
            }
            .sheet(isPresented: $showEditSheet, onDismiss: persistConfigChanges) {
                EditBiomarkersSheet(
                    config: editConfigBinding,
                    isPro: storeService.isProUser,
                    unit: dataStore.profile.bodyMetrics.unit
                )
                .liquidGlassPresentation()
            }
            .sheet(item: $detailItem) { item in
                BiomarkerDetailSheet(
                    biomarker: item.biomarker,
                    initialSnapshot: item.snapshot,
                    historicalFetcher: { await fetchHistorical(for: item.biomarker) },
                    unit: dataStore.profile.bodyMetrics.unit
                )
                .liquidGlassPresentation()
            }
            .sheet(isPresented: $showLabs) {
                LabsView(presentedModally: true)
                    .environment(dataStore)
                    .liquidGlassPresentation()
            }
            .sheet(isPresented: $showBioAgeExplainer) {
                BioAgeExplainerSheet()
                    .liquidGlassPresentation(detents: [.medium, .large])
            }
            .onAppear { consumePendingLabsDeepLink() }
            .onChange(of: appState.pendingLabsOpen) { _, _ in
                consumePendingLabsDeepLink()
            }
        }
        .appAnimation(AppAnimation.springSmooth, value: healthPromptState)
        // Single `.task(id:)` keyed on the inputs `refreshState` reads.
        // It auto-cancels the prior run when either input changes, so
        // two near-simultaneous changes can't land out of order and
        // leave `resolved` reflecting stale inputs.
        .task(id: RefreshKey(isPro: storeService.isProUser,
                             metrics: dataStore.profile.bodyMetrics,
                             weightHistory: dataStore.profile.weightHistory,
                             healthConnected: dataStore.profile.healthConnected)) {
            await refreshState()
        }
    }

    /// Asks for Health access while it's missing, and slides away once
    /// granted rather than vanishing.
    @ViewBuilder
    private var healthPrompt: some View {
        Group {
            if needsHealthConnection {
                GlassEntryRow(
                    icon: "heart.text.square.fill",
                    title: "Connect Apple Health",
                    subtitle: Text("Fills in cardio fitness, HRV, resting heart rate, sleep and steps"),
                    action: connectHealth
                )
                .accessibilityHint("Asks for read access to Apple Health")
            } else if needsHealthUpgrade {
                GlassEntryRow(
                    icon: "lungs.fill",
                    title: "Add cardio fitness",
                    subtitle: Text("Let Atlas read VO2 max from Apple Health for a sharper estimate"),
                    action: requestNewHealthTypes
                )
                .accessibilityHint("Asks Apple Health for access to VO2 max")
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
        .sectionAppear(index: 1)
    }

    /// Which Health prompt is showing, so its exit animates.
    private var healthPromptState: Int {
        needsHealthConnection ? 2 : (needsHealthUpgrade ? 1 : 0)
    }

    /// The estimate's explanation, below the hero: what moved it, how it
    /// has moved, and what it was built from. Only once there is
    /// something to explain — locked and loading show none of it.
    @ViewBuilder
    private var bioAgeDetail: some View {
        if let resolved {
            if case .unlocked(let estimate) = resolved.state {
                BioAgeDriversCard(estimate: estimate, unit: dataStore.profile.bodyMetrics.unit)
                    .biologyCardReveal()
                BioAgeTrendCard(points: resolved.trend, chronologicalAge: resolved.chronologicalAge)
                    .biologyCardReveal()
            }
            if let inputs = resolved.inputs {
                BioAgeCoverageCard(inputs: inputs, healthConnected: dataStore.profile.healthConnected)
                    .biologyCardReveal()
            }
        }
    }

    /// Pro biomarkers stay in `profile.biologyConfig` after a subscription
    /// lapse so the user's selection survives a re-up — but they're filtered
    /// out of every visible surface while `!isProUser` (audit Biology MED 11).
    /// `EditBiomarkersSheet` already blocks *adding* new Pro entries; this
    /// closes the rendering side of the gate, for both the list and the
    /// hero's metric menu.
    private var visibleBiomarkers: [Biomarker] {
        dataStore.profile.biologyConfig.visibleBiomarkers
            .filter { storeService.isProUser || !$0.requiresPro }
    }

    /// Equatable key for the Biological Age refresh `.task(id:)`: every
    /// profile fact the estimate reads.
    private struct RefreshKey: Equatable {
        let isPro: Bool
        let metrics: BodyMetrics
        let weightHistory: [WeightEntry]
        let healthConnected: Bool
    }

    /// Consumes the cross-tab "open Labs" deep-link flag set by the
    /// Home overview card's latest-lab insight tap. Cleared the
    /// moment we present the sheet so re-appearing the tab doesn't
    /// re-fire. Mirrors the consumer that lived on the retired
    /// Insights tab so the deep-link from `HomeView.onTapInsight`
    /// still lands on the right surface after the Insights → Biology
    /// rename.
    private func consumePendingLabsDeepLink() {
        guard appState.pendingLabsOpen else { return }
        appState.pendingLabsOpen = false
        showLabs = true
    }

    // MARK: - Labs & Health

    private var labsSubtitle: Text {
        let count = dataStore.latestLabSummaries.count
        return count == 0
            ? Text("Log blood work and track your results")
            : Text("^[\(count) marker](inflect: true) tracked")
    }

    private func openLabs() {
        Haptics.impact(.light)
        showLabs = true
    }

    private var needsHealthConnection: Bool {
        !dataStore.profile.healthConnected && HealthKitService.shared.isAvailable
    }

    private func connectHealth() {
        Task { @MainActor in
            guard await dataStore.toggleHealthConnection() else { return }
            Haptics.success()
            await reload()
        }
    }

    private func requestNewHealthTypes() {
        Haptics.impact(.light)
        Task { @MainActor in
            guard await HealthKitService.shared.requestAuthorization() else { return }
            Haptics.success()
            await reload()
        }
    }

    private func reload() async {
        reloadID &+= 1
        await refreshState()
    }

    // MARK: - Biological Age resolution

    private func refreshState() async {
        let profile = dataStore.profile
        let latestWeight = profile.weightHistory.max(by: { $0.date < $1.date })?.kg
            ?? profile.bodyMetrics.weightKg
        resolved = await BioAgeStateResolver.resolve(
            chronologicalAge: profile.bodyMetrics.age,
            sex: profile.bodyMetrics.sex,
            bodyMassIndex: PerformanceAgeEngine.bodyMassIndex(
                weightKg: latestWeight,
                heightCm: profile.bodyMetrics.heightCm
            ),
            weightHistory: profile.weightHistory,
            isPro: storeService.isProUser
        )
        if profile.healthConnected && storeService.isProUser {
            needsHealthUpgrade = await HealthKitService.shared.hasUnrequestedReadTypes()
        } else {
            needsHealthUpgrade = false
        }
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

    private func openDetail(for biomarker: Biomarker, seed: BiomarkerSnapshot? = nil) {
        // Lab results have no daily series to chart — their history
        // lives in Labs.
        guard biomarker != .latestLabPanel else {
            openLabs()
            return
        }
        Haptics.impact(.light)
        // Present the sheet immediately with the row's 14-day snapshot
        // (empty when opened from the hero menu), then let it fill in
        // via `historicalFetcher`. Fetching before
        // setting `detailItem` raced on rapid taps: the second tap
        // would overwrite the first `detailItem`, and SwiftUI's
        // `.sheet(item:)` dismisses the first sheet mid-flight on
        // an Identifiable change.
        detailItem = BiomarkerDetailItem(
            biomarker: biomarker,
            snapshot: seed ?? .empty(biomarker)
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
            days: days,
            unit: dataStore.profile.bodyMetrics.unit
        )
        return snapshots.first ?? .empty(biomarker)
    }

    // MARK: - Paywall

    private func presentPaywall() {
        Haptics.impact(.light)
        showPaywall = true
    }

    private var disclaimerFootnote: some View {
        Text("Atlas estimates based on your personal biometrics. Not medical advice.")
            .font(AppFont.scaled(11))
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
