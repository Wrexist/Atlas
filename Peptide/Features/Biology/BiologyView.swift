import SwiftUI

/// Root of the Biology tab. Initially a thin shell around the
/// existing `InsightsView` so commit 1 of the Biology pass is a
/// pure rename — no content shift, no regression risk. Subsequent
/// commits build the Bevel-style hero (Bio Age dial + cosmic
/// backdrop), biomarker list, detail sheets, and edit mode on top
/// of this shell while the legacy Insights content stays
/// reachable below.
///
/// Once the hero + biomarker list cover the cases Insights does
/// today (compliance trends, HealthKit correlations, labs), the
/// remaining Insights content folds into this view's sections and
/// `InsightsView` retires.
struct BiologyView: View {
    var body: some View {
        InsightsView()
    }
}

#Preview {
    BiologyView()
        .environment(DataStore(seedSampleData: true))
        .environment(AppState())
        .preferredColorScheme(.dark)
}
