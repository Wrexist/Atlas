import SwiftUI

/// Root of the Biology tab. Bevel-style cosmic backdrop, biomarker
/// list below. Bio Age hero (commit 6) and edit / detail sheets
/// (commit 8) will mount above + on top of this skeleton.
///
/// The full-screen `CosmicBackdrop` sits behind everything at
/// 0.55 intensity so foreground content reads cleanly without
/// the gradient competing. Per-card backgrounds remain glass
/// material — the cosmic tone is the room, not the furniture.
struct BiologyView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    BioAgeHeroSection(
                        state: .locked,                     // commit 7 wires real state
                        chronologicalAge: 30,               // commit 7 sources from profile
                        asOfDate: Date(),
                        onUnlockTapped: { /* commit 7: present paywall */ }
                    )

                    PremiumPromoCard(
                        eyebrow: "ATLAS PRO",
                        title: "View Your Biological Age",
                        subtitle: "Track how you're aging and discover which habits move your Bio Age.",
                        ctaLabel: "View",
                        onTap: { /* commit 7: present paywall */ }
                    )

                    BiomarkerListSection(
                        visibleBiomarkers: Biomarker.defaultVisible,
                        onEditTapped: { /* commit 8 */ },
                        onSelectBiomarker: { _ in /* commit 8 */ }
                    )

                    disclaimerFootnote

                    // Legacy Insights content stays reachable below
                    // until commit 6 promotes the Bio Age hero into
                    // the slot above this section and commit 8 folds
                    // the remaining Insights surfaces into Biology.
                    // For now: zero regression, the user can still
                    // reach compliance trends + HealthKit
                    // correlations + labs through the same scroll.
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
        }
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
