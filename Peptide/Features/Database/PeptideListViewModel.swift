import SwiftUI

@MainActor @Observable
final class PeptideListViewModel {
    var searchText = "" { didSet { refilter() } }
    var selectedCategory: PeptideCategory?
    private(set) var allPeptides: [Peptide]
    private(set) var filteredPeptides: [Peptide] = []
    private var hasLoadedFromStore = false

    init(peptides: [Peptide] = []) {
        self.allPeptides = peptides.isEmpty ? MockPeptides.all : peptides
        self.hasLoadedFromStore = !peptides.isEmpty
        refilter()
    }

    func updatePeptides(_ peptides: [Peptide]) {
        guard !hasLoadedFromStore else { return }
        allPeptides = peptides
        hasLoadedFromStore = true
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
