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

    /// Replaces the in-memory peptide list and refilters. Was one-shot
    /// (`hasLoadedFromStore` flag) so every subsequent call was dropped
    /// — broke pull-to-refresh, freshly-created custom peptides, and
    /// iCloud syncs after first load (audit Library P0.1). Idempotent
    /// equality guard short-circuits when SwiftData triggers a redundant
    /// refresh with the same list.
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
