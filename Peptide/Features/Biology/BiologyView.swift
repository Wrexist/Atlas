import SwiftUI

/// Root of the Biology tab. Resolves the Bio Age state — locked /
/// building baseline / unlocked — against the user's Pro
/// entitlement + HealthKit history. Hosts the cosmic backdrop,
/// the hero, the upsell card (only when locked), and the
/// biomarker list. Edit + detail sheets land in commit 8.
struct BiologyView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    @State private var storeService = StoreService.shared

    @State private var resolved: BioAgeStateResolver.Resolved = .init(
        state: .locked,
        chronologicalAge: BioAgeStateResolver.chronologicalAgeFallback
    )
    @State private var showPaywall = false

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

                    // The cosmic upsell card sits below the dial
                    // only when Bio Age is locked. Once the user
                    // is Pro (building or unlocked), the slot
                    // disappears — no point upselling a feature
                    // the user already has.
                    if case .locked = resolved.state {
                        PremiumPromoCard(
                            eyebrow: "ATLAS PRO",
                            title: "View Your Biological Age",
                            subtitle: "Track how you're aging and discover which habits move your Bio Age.",
                            ctaLabel: "View",
                            onTap: { presentPaywall() }
                        )
                    }

                    BiomarkerListSection(
                        visibleBiomarkers: Biomarker.defaultVisible,
                        onEditTapped: { /* commit 8 */ },
                        onSelectBiomarker: { _ in /* commit 8 */ }
                    )

                    disclaimerFootnote

                    // Legacy Insights content stays reachable until
                    // commit 8 folds compliance trends + HealthKit
                    // correlations + labs into Biology's sections.
                    // Visually demoted so the new top half is the
                    // hero; the old surface is still here so users
                    // don't lose access mid-migration.
                    InsightsView()
                        .padding(.top, Spacing.lg)
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
        }
        .task { await refreshState() }
        // Re-resolve when Pro entitlement flips (e.g. a fresh
        // purchase completes inside the paywall sheet) or when
        // the user updates their age in Profile.
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

    /// 30-day weight delta in kilograms, derived from the
    /// nearest log to "30 days ago" vs the most recent log.
    /// Returns nil when there's fewer than 2 entries or the
    /// span doesn't cover ~30 days — the engine treats a missing
    /// signal as a dropped weight component rather than zero.
    private func computeWeightDelta30d() -> Double? {
        let history = dataStore.profile.weightHistory.sorted { $0.date < $1.date }
        guard history.count >= 2, let latest = history.last else { return nil }
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        // First entry on-or-after the cutoff is the 30-day-ago
        // sample. If everything is newer than 30 days, fall back
        // to the oldest available — better than nothing for a
        // user with only 2 weeks of data.
        let baseline = history.first { $0.date >= cutoff } ?? history.first!
        // Sanity check: don't compute a "delta" when latest is
        // the same entry as baseline (single sample collected
        // exactly once).
        guard baseline.id != latest.id else { return nil }
        return latest.kg - baseline.kg
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
