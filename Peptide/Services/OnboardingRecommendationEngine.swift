import Foundation
import SwiftUI

/// Cold-start educational matcher used by the onboarding flow. Maps the
/// user's selected goals to a small list of peptides drawn from the canonical
/// database based on category and benefit overlap.
///
/// This is a goal-based matcher, NOT a dose recommender. No dose values,
/// dose ranges, or weight-scaled calculations are produced or surfaced. The
/// surrounding UI shows peptide names with a short rationale; users review
/// the educational detail page (with citations) before adding anything to a
/// stack and remain solely responsible for any dosing decisions made with
/// their own clinician.
enum OnboardingRecommendationEngine {

    struct Suggestion: Identifiable {
        var id: UUID { peptide.id }
        let peptide: Peptide
        let goalMatches: [String]
        /// Short rationale shown below the peptide name (e.g., "matches Recovery").
        /// Uses LocalizedStringKey so the surrounding phrase translates while
        /// dynamic goal names interpolate via %@.
        let rationale: LocalizedStringKey
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

            let matchingBenefits = peptide.benefits.filter { benefit in
                let lower = benefit.lowercased()
                return benefitTerms.contains { lower.contains($0) }
            }
            if !matchingBenefits.isEmpty {
                points += min(matchingBenefits.count, 3)
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
                rationale: rationale(for: entry.peptide, matchedGoals: entry.matchedGoals)
            )
        }
    }

    private static func rationale(for peptide: Peptide, matchedGoals: [String]) -> LocalizedStringKey {
        if matchedGoals.isEmpty {
            return "Aligned with \(peptide.category.displayName)"
        }
        if matchedGoals.count == 1 {
            return "Matches your \(matchedGoals[0]) goal"
        }
        let pair = matchedGoals.prefix(2).joined(separator: " + ")
        return "Matches \(pair)"
    }
}
