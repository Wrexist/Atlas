import SwiftUI

/// "Suggestions for your protocols" cluster on the Protocols tab — surfaces the
/// smart cycle planner's suggestions plus the recommendation
/// engine's "peptides that pair well with what you already run".
/// Phase 34 split this off from HomeView so discovery lives next
/// to stack management rather than in the daily-action surface.
///
/// Renders nothing when the user has no active protocols (the
/// engines need a baseline to compare against) or when both
/// engines return empty, so the section gracefully disappears for
/// brand-new users instead of stranding an empty header.
struct ProtocolsDiscoverSection: View {
    @Environment(DataStore.self) private var dataStore

    var body: some View {
        let plannerSuggestions = dataStore.smartCycleSuggestions
        let recommendations = dataStore.stackRecommendations

        if !plannerSuggestions.isEmpty || !recommendations.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HomeSectionHeader(eyebrow: "Discover", title: "Suggestions for your protocols")

                if !plannerSuggestions.isEmpty {
                    SmartCyclePlannerCard(suggestions: plannerSuggestions)
                }

                if !recommendations.isEmpty {
                    RecommendedPeptidesCard(
                        recommendations: recommendations,
                        activeProtocols: dataStore.activeProtocols
                    )
                }
            }
        }
    }
}
