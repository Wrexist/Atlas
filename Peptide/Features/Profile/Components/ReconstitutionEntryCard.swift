import SwiftUI

/// One-line entry tile for the reconstitution calculator. Sits in
/// Profile between the Apple Health card and the Export section —
/// the "tools" cluster — so users discover it when they're already
/// in setup-and-config mode. Visually a smaller tile than the
/// other Profile cards to signal "utility" rather than "primary
/// affordance".
struct ReconstitutionEntryCard: View {
    let onTap: () -> Void

    var body: some View {
        GlassEntryRow(
            icon: "syringe.fill",
            title: "Reconstitution calculator",
            subtitle: Text("Vial mg + bac water → exact syringe units"),
            action: onTap
        )
        .accessibilityLabel("Reconstitution calculator")
        .accessibilityHint("Opens the calculator for converting vial size, bacteriostatic water, and target dose into U-100 syringe units.")
    }
}
