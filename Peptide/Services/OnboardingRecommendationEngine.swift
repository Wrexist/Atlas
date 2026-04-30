import Foundation

/// Cold-start recommendations used by the onboarding flow. Maps the user's
/// selected goals (and optional body metrics) to a small starter stack of
/// peptides drawn from the canonical database.
///
/// The main `StackRecommendationEngine` requires at least one current peptide
/// to score from. Onboarding has no protocol yet, so we derive the seed list
/// here using the same goal->category mapping the engine uses elsewhere, then
/// pick top candidates by category match + benefit overlap.
enum OnboardingRecommendationEngine {

    struct Suggestion: Identifiable, Hashable {
        var id: UUID { peptide.id }
        let peptide: Peptide
        let goalMatches: [String]
        /// Personalized dose string for the user's body weight, or the
        /// peptide's published range when weight is unavailable.
        let suggestedDose: String
        /// True when `suggestedDose` was scaled to the user's weight.
        let isPersonalized: Bool
        /// Short rationale shown below the dose (e.g., "matches Recovery").
        let rationale: String
    }

    private static let starterAllowlist: Set<String> = [
        // Recovery
        "BPC-157", "TB-500", "GHK-Cu",
        // Growth
        "Ipamorelin", "CJC-1295", "CJC-1295 DAC", "Tesamorelin", "Sermorelin", "MK-677",
        // Cognitive
        "Semax", "Selank", "Cerebrolysin", "Dihexa",
        // Anti-Aging
        "Epitalon", "GHK-Cu", "Thymalin",
        // Immune
        "Thymosin Alpha-1", "TA-1", "LL-37",
        // Metabolic / Fat Loss
        "Semaglutide", "Tirzepatide", "Retatrutide", "AOD-9604",
        // Sleep
        "DSIP",
    ]

    static func recommend(
        goals: [String],
        metrics: BodyMetrics,
        from database: [Peptide],
        limit: Int = 4
    ) -> [Suggestion] {
        let resolved = StackRecommendationEngine.resolveGoals(goals)
        guard !resolved.isEmpty else { return [] }

        let goalCategories = Set(resolved.map(\.category))
        let benefitTerms = resolved.flatMap(\.benefitTerms).map { $0.lowercased() }

        struct Scored {
            let peptide: Peptide
            let score: Int
            let matchedGoals: [String]
        }

        var scored: [UUID: Scored] = [:]
        for peptide in database {
            var points = 0
            var matched: Set<String> = []

            if goalCategories.contains(peptide.category) {
                points += 4
                for goal in resolved where goal.category == peptide.category {
                    matched.insert(goal.displayName)
                }
            }

            let benefitHits = peptide.benefits.filter { benefit in
                let lower = benefit.lowercased()
                return benefitTerms.contains { lower.contains($0) }
            }.count
            if benefitHits > 0 {
                points += min(benefitHits, 3)
                for goal in resolved {
                    if peptide.benefits.contains(where: { benefit in
                        goal.benefitTerms.contains { benefit.localizedCaseInsensitiveContains($0) }
                    }) {
                        matched.insert(goal.displayName)
                    }
                }
            }

            if starterAllowlist.contains(peptide.abbreviation) {
                points += 2
            }

            guard points > 0 else { continue }
            scored[peptide.id] = Scored(
                peptide: peptide,
                score: points,
                matchedGoals: matched.sorted()
            )
        }

        // Diversify: cap to one peptide per category for a clean starter stack.
        let ranked = scored.values.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.peptide.abbreviation < $1.peptide.abbreviation
        }

        var seenCategories: Set<PeptideCategory> = []
        var picks: [Scored] = []
        for candidate in ranked {
            if seenCategories.contains(candidate.peptide.category) { continue }
            seenCategories.insert(candidate.peptide.category)
            picks.append(candidate)
            if picks.count >= limit { break }
        }

        return picks.map { entry in
            Suggestion(
                peptide: entry.peptide,
                goalMatches: entry.matchedGoals,
                suggestedDose: PeptideDoseCalculator.dose(for: entry.peptide, metrics: metrics),
                isPersonalized: PeptideDoseCalculator.isPersonalized(entry.peptide, metrics: metrics),
                rationale: rationale(for: entry.peptide, matchedGoals: entry.matchedGoals)
            )
        }
    }

    private static func rationale(for peptide: Peptide, matchedGoals: [String]) -> String {
        if matchedGoals.isEmpty {
            return "Aligned with \(peptide.category.displayName.lowercased())"
        }
        if matchedGoals.count == 1 { return "Matches your \(matchedGoals[0]) goal" }
        return "Matches \(matchedGoals.prefix(2).joined(separator: " + "))"
    }
}
