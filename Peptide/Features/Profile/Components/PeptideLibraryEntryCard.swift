import SwiftUI

/// Profile entry into the peptide Library — the database, Protocols, and
/// AI research. This is the Library's home after the Habits tab took its
/// slot in the bar. Tapping closes Profile and opens the Library as a
/// full-screen modal after the sheet's dismiss animation (presenting a
/// cover while the sheet is still up gets silently dropped — the app's
/// `sheetDismissDelay` handoff convention).
struct PeptideLibraryEntryCard: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private var activeProtocols: Int { dataStore.activeProtocols.count }

    var body: some View {
        GlassEntryRow(
            icon: "books.vertical.fill",
            title: "Library & Protocols",
            subtitle: subtitle,
            action: openLibrary
        )
        .accessibilityHint("Opens the compound library, protocols, and AI research")
    }

    private func openLibrary() {
        Haptics.impact(.light)
        let app = appState
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: AppAnimation.sheetDismissDelay)
            app.showLibrary = true
        }
    }

    private var subtitle: Text {
        switch activeProtocols {
        case 0: Text("Research, protocols and AI answers")
        case 1: Text("1 active protocol")
        default: Text("\(activeProtocols) active protocols")
        }
    }
}
