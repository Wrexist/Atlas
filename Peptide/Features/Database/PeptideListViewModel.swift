import SwiftUI

@MainActor @Observable
final class PeptideListViewModel {
    var searchText = "" { didSet { refilter() } }
    var selectedCategory: PeptideCategory?
    private(set) var allPeptides: [Peptide]
    private(set) var filteredPeptides: [Peptide] = []

    init(peptides: [Peptide] = []) {
        self.allPeptides = peptides
        refilter()
    }

    /// Replaces the in-memory peptide list. Idempotent — calling
    /// with the same value is a no-op for SwiftUI's diff. The
    /// previous implementation guarded on a "first load" flag and
    /// silently dropped every subsequent call, which broke the
    /// `refreshable` pull-to-refresh handler on the list view and
    /// hid any custom peptides synced in from another device via
    /// iCloud after the initial load.
    func updatePeptides(_ peptides: [Peptide]) {
        guard allPeptides != peptides else { return }
        allPeptides = peptides
        refilter()
    }

    var categories: [PeptideCategory] {
        PeptideCategory.allCases
    }

    func selectCategory(_ category: PeptideCategory?) {
        withAnimation(AppAnimation.springSnappy) {
            selectedCategory = (selectedCategory == category) ? nil : category
            refilter()
        }
    }

    private func refilter() {
        var results = allPeptides

        if let category = selectedCategory {
            results = results.filter { $0.category == category }
        }

        if !searchText.isEmpty {
            let query = searchText
            results = results.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                $0.abbreviation.localizedCaseInsensitiveContains(query) ||
                $0.category.displayName.localizedCaseInsensitiveContains(query) ||
                $0.benefits.contains { $0.localizedCaseInsensitiveContains(query) }
            }
        }

        filteredPeptides = results
    }
}
