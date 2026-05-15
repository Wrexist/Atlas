import SwiftUI

/// Today-tab entry point. Pre-Phase-33 this hosted a floating
/// pill that switched between separate Home and Lifestyle scrolls;
/// the recompose merged those two surfaces into one curated
/// HomeView, so the container is now a thin wrapper that exists
/// only because the tab definition references it. Kept rather
/// than collapsed inline so Phase 35's coachmark / sticky-header
/// work has a clear home that isn't HomeView itself.
struct HomeContainerView: View {
    var body: some View {
        HomeView()
    }
}

#Preview("Today") {
    HomeContainerView()
        .environment(DataStore(seedSampleData: true))
        .environment(AppState())
        .preferredColorScheme(.dark)
}
