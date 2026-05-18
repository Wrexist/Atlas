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
/// Weight tracking and progress photos stay on the Today scroll
/// for now (they're body-tracking, not nutrition) — a future
/// refinement could split them into a "Body" sub-tab here.
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
        }
    }
}

#Preview {
    MealsContainerView()
        .environment(DataStore(seedSampleData: true))
        .environment(AppState())
        .preferredColorScheme(.dark)
}
