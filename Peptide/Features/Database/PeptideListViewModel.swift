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

    /// Replace the in-memory catalog with the latest from DataStore.
    /// Previously had a one-shot `hasLoadedFromStore` guard that
    /// dropped every subsequent update — meaning a freshly-created
    /// custom peptide never appeared in the list until the next app
    /// launch (audit Library P0.1). Always refilter; the operation is
    /// cheap (208 + ~N custom entries) and the user-data freshness
    /// is the contract.
    func updatePeptides(_ peptides: [Peptide]) {
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
