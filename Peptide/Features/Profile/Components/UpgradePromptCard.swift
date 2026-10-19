import SwiftUI

/// Profile's upsell, on the same premium card Biology uses so every
/// "behind the paywall" surface reads as one thing.
struct UpgradePromptCard: View {
    @State private var showPaywall = false

    var body: some View {
        PremiumPromoCard(
            eyebrow: "ATLAS PRO",
            title: "Upgrade to Atlas Pro",
            subtitle: "Progressive plans, photo meal logging, recovery insights.",
            ctaLabel: "See plans",
            onTap: { showPaywall = true }
        )
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: .profile)
                .liquidGlassPresentation()
        }
    }
}
