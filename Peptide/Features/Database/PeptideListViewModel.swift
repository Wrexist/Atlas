import SwiftUI

@MainActor @Observable
final class PeptideListViewModel {
    /// Debounced, not immediate: every keystroke used to run four
    /// `localizedCaseInsensitiveContains` passes over all 208 peptides
    /// (plus each one's benefits array) synchronously on the main actor,
    /// so fast typing stuttered the list. A short settle window collapses
    /// a burst of keystrokes into one filter pass.
    var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            scheduleRefilter()
        }
    }
    var selectedCategory: PeptideCategory?
    private(set) var allPeptides: [Peptide]
    private(set) var filteredPeptides: [Peptide] = []

    @ObservationIgnored private var refilterTask: Task<Void, Never>?

    /// Long enough to swallow a normal typing burst, short enough that the
    /// list still feels like it's tracking the keyboard.
    private static let searchDebounce = Duration.milliseconds(150)

    init(peptides: [Peptide] = []) {
        self.allPeptides = peptides
        refilter()
    }

    private func scheduleRefilter() {
        refilterTask?.cancel()
        refilterTask = Task { [weak self] in
            try? await Task.sleep(for: Self.searchDebounce)
            guard !Task.isCancelled else { return }
            self?.refilter()
        }
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
        // A category tap is deliberate, so it filters immediately — and it
        // drops any in-flight search debounce so a late keystroke pass can't
        // land on top of the animation with a stale category.
        refilterTask?.cancel()
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
