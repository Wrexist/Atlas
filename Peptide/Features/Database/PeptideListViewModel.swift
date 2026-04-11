import SwiftUI

@Observable
final class PeptideListViewModel {
    var searchText = ""
    var selectedCategory: PeptideCategory?
    var allPeptides = MockPeptides.all

    var filteredPeptides: [Peptide] {
        var results = allPeptides

        if let category = selectedCategory {
            results = results.filter { $0.category == category }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            results = results.filter {
                $0.name.lowercased().contains(query) ||
                $0.abbreviation.lowercased().contains(query) ||
                $0.benefits.contains { $0.lowercased().contains(query) }
            }
        }

        return results
    }

    var categories: [PeptideCategory] {
        PeptideCategory.allCases
    }

    func selectCategory(_ category: PeptideCategory?) {
        withAnimation(AppAnimation.springSnappy) {
            if selectedCategory == category {
                selectedCategory = nil
            } else {
                selectedCategory = category
            }
        }
    }
}
