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

    private var peptideCount: Int { PeptideDatabase.shared.count }
    private var activeProtocols: Int { dataStore.activeProtocols.count }

    var body: some View {
        GlassEntryRow(
            icon: "books.vertical.fill",
            title: "Peptide Library",
            subtitle: Text(subtitle),
            action: openLibrary
        )
        .accessibilityHint("Opens the peptide database, protocols, and AI research")
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

    private var subtitle: String {
        let peptides = "\(peptideCount) peptides"
        if activeProtocols == 1 {
            return "\(peptides) · 1 active protocol"
        } else if activeProtocols > 1 {
            return "\(peptides) · \(activeProtocols) active protocols"
        }
        return "\(peptides) · research & protocols"
    }
}
