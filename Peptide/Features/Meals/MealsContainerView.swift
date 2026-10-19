import SwiftUI

/// Meals tab root. Phase D of the training pivot promotes the
/// nutrition surfaces out of the Today scroll into their own
/// top-level tab so food gets first-class real estate alongside
/// training.
///
/// Composed from the existing `HomeMealsSection` — already a self-
/// contained, sheet-owning view that bubbles its modals up the
/// SwiftUI hierarchy — so mounting it here gives the user a
/// single Meals destination without duplicating logic. The section
/// is also mounted on the Today scroll, but only this instance
/// passes `consumesDeepLink: true` so Spotlight food taps land
/// here (the router switches to `.meals` first) and the Today
/// instance stays silent for deep-links.
///
/// Progress photos are body-tracking, not nutrition, so they live
/// on the Your Progress screen (`AtlasProgressView`) rather than here.
struct MealsContainerView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    HomeMealsSection(consumesDeepLink: true)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.xxxxl)
                // iPad content cap — Meals stretches less comfortably
                // than Home (per-meal rows want a readable measure)
                // (Phase 5.8 partial).
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("Meals")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ProfileToolbarButton() }
            }
        }
    }
}

#Preview {
    MealsContainerView()
        .environment(DataStore(seedSampleData: true))
        .environment(AppState())
        .preferredColorScheme(.dark)
}
