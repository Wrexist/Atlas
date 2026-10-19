import SwiftUI

/// Profile-tab entry point for the stack-wide cycle card share. Hides
/// itself when the user has no active protocols — there's nothing to
/// summarise yet, and surfacing the CTA would just open an empty card.
struct CycleCardShareSection: View {
    @Environment(DataStore.self) private var dataStore
    @State private var showShareSheet = false

    var body: some View {
        if dataStore.activeProtocols.isEmpty {
            EmptyView()
        } else {
            content
                .sheet(isPresented: $showShareSheet) {
                    ShareCardSheet(subject: .fullStack)
                        .environment(dataStore)
                        .liquidGlassPresentation()
                }
        }
    }

    private var content: some View {
        GlassEntryRow(
            icon: "square.and.arrow.up.fill",
            title: "Share my cycle card",
            subtitle: Text("A shareable card of your current cycle and stats."),
            action: { showShareSheet = true }
        )
    }
}
