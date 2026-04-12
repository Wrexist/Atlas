import Foundation

extension StackRecommendationEngine {

    /// Pre-computed context for the recommendation engine.
    /// All derived fields are computed once at init to keep scoring signals O(1) per lookup.
    struct RecommendationContext {
        let currentPeptides: [Peptide]
        let database: [Peptide]
        let goals: [String]
        let activeProtocols: [PeptideProtocol]
        let entries: [ProtocolEntry]
        let currentDate: Date

        // Derived
        let currentIds: Set<UUID>
        let currentCategories: Set<PeptideCategory>
        let currentAbbreviations: Set<String>
        let categoryCounts: [PeptideCategory: Int]
        let currentBenefits: Set<String>
        let currentRoutes: [String]
        let dbByName: [String: Peptide]
        let resolvedGoals: [ResolvedGoal]
        let categoryCompliance: [PeptideCategory: Double]
        let experienceLevel: ExperienceLevel

        init(
            currentPeptides: [Peptide],
            database: [Peptide],
            goals: [String],
            activeProtocols: [PeptideProtocol],
            entries: [ProtocolEntry],
            currentDate: Date = Date()
        ) {
            self.currentPeptides = currentPeptides
            self.database = database
            self.goals = goals
            self.activeProtocols = activeProtocols
            self.entries = entries
            self.currentDate = currentDate

            self.currentIds = Set(currentPeptides.map(\.id))
            self.currentCategories = Set(currentPeptides.map(\.category))
            self.currentAbbreviations = Set(currentPeptides.map(\.abbreviation))
            self.categoryCounts = Dictionary(grouping: currentPeptides, by: \.category)
                .mapValues(\.count)
            self.currentBenefits = Set(currentPeptides.flatMap(\.benefits).map { $0.lowercased() })
            self.currentRoutes = currentPeptides.map { $0.adminRoute.lowercased() }
            self.dbByName = database.reduce(into: [:]) { dict, p in
                dict[p.abbreviation.lowercased()] = p
                dict[p.name.lowercased()] = p
            }
            self.resolvedGoals = StackRecommendationEngine.resolveGoals(goals)
            self.categoryCompliance = Self.computeCategoryCompliance(
                entries: entries,
                currentPeptides: currentPeptides
            )

            // Use total unique peptides as experience proxy.
            // When activeProtocols is empty (legacy API), fall back to currentPeptides count.
            let totalPeptides: Int
            if activeProtocols.isEmpty {
                totalPeptides = currentPeptides.count
            } else {
                totalPeptides = Set(activeProtocols.flatMap(\.peptides).map(\.id)).count
            }
            if totalPeptides <= 2 {
                self.experienceLevel = .beginner
            } else if totalPeptides <= 6 {
                self.experienceLevel = .intermediate
            } else {
                self.experienceLevel = .advanced
            }
        }

        private static func computeCategoryCompliance(
            entries: [ProtocolEntry],
            currentPeptides: [Peptide]
        ) -> [PeptideCategory: Double] {
            guard !entries.isEmpty else { return [:] }
            let peptideCategories = Dictionary(
                currentPeptides.map { ($0.id, $0.category) },
                uniquingKeysWith: { first, _ in first }
            )
            var categoryEntries: [PeptideCategory: (completed: Int, total: Int)] = [:]
            for entry in entries {
                guard let category = peptideCategories[entry.peptide.id] else { continue }
                var stats = categoryEntries[category, default: (0, 0)]
                stats.total += 1
                if entry.completed { stats.completed += 1 }
                categoryEntries[category] = stats
            }
            return categoryEntries.mapValues { stats in
                stats.total > 0 ? Double(stats.completed) / Double(stats.total) : 0
            }
        }
    }

    enum ExperienceLevel: Equatable {
        case beginner
        case intermediate
        case advanced
    }
}
