import Foundation

enum StackRecommendationEngine {

    // Model types live in StackRecommendationTypes.swift.

    // MARK: - Category Synergies

    private static let categorySynergies: [(PeptideCategory, PeptideCategory, String)] = [
        (.growth, .recovery, "Growth + Recovery amplify tissue repair"),
        (.cognitive, .antiAging, "Cognitive + Anti-Aging support neuroprotection"),
        (.metabolic, .growth, "Metabolic + Growth preserve muscle during fat loss"),
        (.immune, .recovery, "Immune + Recovery accelerate healing response"),
        (.antiAging, .recovery, "Anti-Aging + Recovery enhance regeneration"),
        (.growth, .cognitive, "Growth + Cognitive support neuroplasticity"),
    ]

    // MARK: - Goal Mapping

    private static let goalKeywords: [(keywords: [String], category: PeptideCategory, benefitTerms: [String])] = [
        (["muscle", "growth", "hypertrophy", "strength", "mass"],
         .growth, ["muscle", "growth", "hypertrophy", "strength", "anabolic"]),
        (["recovery", "healing", "repair", "injury", "tendon", "joint"],
         .recovery, ["recovery", "healing", "repair", "tendon", "tissue", "wound"]),
        (["cognitive", "focus", "brain", "memory", "mental", "edge"],
         .cognitive, ["cognitive", "focus", "memory", "brain", "neuroprotect", "mental"]),
        (["anti-aging", "longevity", "skin", "aging", "youth"],
         .antiAging, ["anti-aging", "collagen", "skin", "longevity", "elastin", "wrinkle"]),
        (["immune", "immunity", "infection", "defense"],
         .immune, ["immune", "antimicrobial", "inflammation", "pathogen", "defense"]),
        (["weight", "fat", "metabolic", "lean", "diet", "appetite"],
         .metabolic, ["weight", "fat", "metabolic", "appetite", "lipolytic", "satiety"]),
        // Sleep maps to recovery — most sleep-supportive peptides (DSIP,
        // MK-677, Epitalon) are catalogued under recovery/anti-aging.
        (["sleep", "rest", "insomnia"],
         .recovery, ["sleep", "rest", "circadian", "melatonin", "rem", "deep sleep"]),
        // Stress maps to cognitive — anxiolytic peptides (Selank, Semax)
        // live under cognitive in the database.
        (["stress", "anxiety", "calm", "mood"],
         .cognitive, ["anxiolytic", "anti-stress", "calming", "mood", "anti-anxiety"]),
    ]

    // MARK: - Mechanism Pathways

    /// Internal (not private) so the Warnings extension in another file can use it.
    enum MechanismPathway: String, CaseIterable {
        case ghsrAgonist = "GHS-R agonist"
        case ghrhAnalog = "GHRH analog"
        case igfSignaling = "IGF-1 signaling"
        case tissueRepair = "Tissue repair"
        case antiInflammatory = "Anti-inflammatory"
        case appetiteRegulation = "Appetite regulation"

        var keywords: [String] {
            switch self {
            case .ghsrAgonist: return ["ghs-r", "ghrelin receptor", "growth hormone secretagogue receptor"]
            case .ghrhAnalog: return ["ghrh", "growth hormone-releasing hormone", "growth hormone releasing"]
            case .igfSignaling: return ["igf-1", "insulin-like growth factor"]
            case .tissueRepair: return ["angiogenesis", "vegf", "wound healing", "collagen synthesis", "tissue repair"]
            case .antiInflammatory: return ["nf-κb", "nf-kb", "anti-inflammatory", "cytokine suppression"]
            case .appetiteRegulation: return ["glp-1", "appetite", "satiety", "incretin"]
            }
        }

        static func detect(from mechanism: String) -> Set<MechanismPathway> {
            let lower = mechanism.lowercased()
            var found = Set<MechanismPathway>()
            for pathway in allCases where pathway.keywords.contains(where: { lower.contains($0) }) {
                found.insert(pathway)
            }
            return found
        }
    }

    // MARK: - Recommendations

    /// Backward-compatible entry point. Wraps the context-aware version.
    static func recommendations(
        for currentPeptides: [Peptide],
        from database: [Peptide],
        goals: [String] = [],
        limit: Int = 5
    ) -> [Recommendation] {
        let context = RecommendationContext(
            currentPeptides: currentPeptides,
            database: database,
            goals: goals,
            activeProtocols: [],
            entries: []
        )
        return recommendations(context: context, limit: limit)
    }

    /// Full context-aware recommendation engine with all 12 scoring signals.
    static func recommendations(
        context: RecommendationContext,
        limit: Int = 5
    ) -> [Recommendation] {
        guard !context.currentPeptides.isEmpty else { return [] }

        var candidates: [UUID: (peptide: Peptide, score: Int, reasons: [RecommendationReason])] = [:]

        // --- 1. CommonStacks scoring ---
        var stackRecommenders: [UUID: Set<String>] = [:]
        for current in context.currentPeptides {
            let seenStacks = Set(current.commonStacks.map { $0.lowercased() })
            for stackName in seenStacks {
                guard let found = resolveMatch(stackName, in: context.dbByName, database: context.database),
                      !context.currentIds.contains(found.id) else { continue }
                stackRecommenders[found.id, default: []].insert(current.abbreviation)
                if candidates[found.id] == nil {
                    candidates[found.id] = (found, 0, [])
                }
            }
        }
        for (id, recommenders) in stackRecommenders {
            candidates[id]?.score += recommenders.count * 2
            candidates[id]?.reasons.append(.commonStack(pairsWith: recommenders.sorted()))
        }

        // --- 2. Goal-aligned scoring ---
        if !context.resolvedGoals.isEmpty {
            for candidate in context.database where !context.currentIds.contains(candidate.id) {
                var goalScore = 0
                var matchedGoals: [String] = []

                for goal in context.resolvedGoals {
                    if candidate.category == goal.category {
                        goalScore += 2
                        matchedGoals.append(goal.displayName)
                    }
                    let benefitHits = candidate.benefits.filter { benefit in
                        goal.benefitTerms.contains { benefit.localizedCaseInsensitiveContains($0) }
                    }.count
                    if benefitHits > 0 {
                        goalScore += min(benefitHits, 2)
                        if !matchedGoals.contains(goal.displayName) {
                            matchedGoals.append(goal.displayName)
                        }
                    }
                }

                if goalScore > 0 {
                    if candidates[candidate.id] == nil {
                        candidates[candidate.id] = (candidate, 0, [])
                    }
                    candidates[candidate.id]?.score += goalScore
                    for goal in matchedGoals {
                        candidates[candidate.id]?.reasons.append(.goalMatch(goal: goal))
                    }
                }
            }
        }

        // --- 3. Category synergy scoring ---
        for candidate in context.database where !context.currentIds.contains(candidate.id) {
            for (catA, catB, description) in categorySynergies {
                let candidateCat = candidate.category
                if (candidateCat == catA && context.currentCategories.contains(catB)) ||
                   (candidateCat == catB && context.currentCategories.contains(catA)) {
                    if candidates[candidate.id] == nil {
                        candidates[candidate.id] = (candidate, 0, [])
                    }
                    candidates[candidate.id]?.score += 1
                    candidates[candidate.id]?.reasons.append(.categorySynergy(description: description))
                    break
                }
            }
        }

        // --- 4. Validated stack scoring ---
        var validatedStacksAdded: [UUID: Set<String>] = [:]
        for stack in PeptideCompatibilityData.validatedStacks {
            let overlap = stack.peptideAbbreviations.filter { context.currentAbbreviations.contains($0) }
            guard !overlap.isEmpty else { continue }
            for missing in stack.peptideAbbreviations where !context.currentAbbreviations.contains(missing) {
                guard let found = resolveMatch(missing.lowercased(), in: context.dbByName, database: context.database),
                      !context.currentIds.contains(found.id) else { continue }
                if validatedStacksAdded[found.id, default: []].contains(stack.name) { continue }
                validatedStacksAdded[found.id, default: []].insert(stack.name)

                if candidates[found.id] == nil {
                    candidates[found.id] = (found, 0, [])
                }
                candidates[found.id]?.score += 3
                candidates[found.id]?.reasons.append(
                    .validatedStack(name: stack.name, synergy: stack.synergy)
                )
            }
        }

        // --- 5. Shared benefits boost ---
        for candidate in context.database where !context.currentIds.contains(candidate.id) {
            let sharedCount = candidate.benefits.filter { context.currentBenefits.contains($0.lowercased()) }.count
            if sharedCount >= 2 {
                if candidates[candidate.id] == nil {
                    candidates[candidate.id] = (candidate, 0, [])
                }
                candidates[candidate.id]?.score += 1
                candidates[candidate.id]?.reasons.append(.sharedBenefits(count: sharedCount))
            }
        }

        // --- 6-12. New scoring signals ---
        for candidate in context.database where !context.currentIds.contains(candidate.id) {
            let signals: [(Int, RecommendationReason?)] = [
                scoreTiming(candidate: candidate, context: context),
                scoreCompliance(candidate: candidate, context: context),
                scoreRouteDiversity(candidate: candidate, context: context),
                scoreHalfLife(candidate: candidate, context: context),
                scoreExperience(candidate: candidate, context: context),
                scoreDiminishingReturns(candidate: candidate, context: context),
                scoreSeasonal(candidate: candidate, context: context),
            ]
            for (points, reason) in signals where points != 0 {
                if candidates[candidate.id] == nil && points > 0 {
                    candidates[candidate.id] = (candidate, 0, [])
                }
                guard candidates[candidate.id] != nil else { continue }
                candidates[candidate.id]?.score += points
                if let reason { candidates[candidate.id]?.reasons.append(reason) }
            }
        }

        // Filter out zero-score, compute confidence, sort and return
        return candidates.values
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map {
                Recommendation(
                    id: $0.peptide.id,
                    peptide: $0.peptide,
                    score: $0.score,
                    reasons: $0.reasons,
                    confidence: computeConfidence(reasons: $0.reasons, score: $0.score)
                )
            }
    }

    // Compatibility-warning logic lives in StackRecommendationEngine+Warnings.swift.

    // MARK: - Stack Completeness

    /// Evaluates how complete the user's stack is relative to their stated goals.
    /// Returns nil if no goals are set.
    static func stackCompleteness(
        for currentPeptides: [Peptide],
        goals: [String],
        from database: [Peptide]
    ) -> StackCompleteness? {
        let resolved = resolveGoals(goals)
        guard !resolved.isEmpty else { return nil }

        let currentCategories = Set(currentPeptides.map(\.category))
        let currentAbbreviations = Set(currentPeptides.map(\.abbreviation))

        var coveredGoals: [String] = []
        var missingCategories: [PeptideCategory] = []
        var suggestions: [String] = []
        var totalDimensions = 0
        var coveredDimensions = 0

        for goal in resolved {
            totalDimensions += 2

            // Dimension 1: category coverage
            if currentCategories.contains(goal.category) {
                coveredDimensions += 1
                if !coveredGoals.contains(goal.displayName) {
                    coveredGoals.append(goal.displayName)
                }
            } else {
                if !missingCategories.contains(goal.category) {
                    missingCategories.append(goal.category)
                }
                suggestions.append(
                    "Add a \(goal.category.displayName) peptide for your \"\(goal.displayName)\" goal"
                )
            }

            // Dimension 2: validated stack coverage
            let hasCompleteStack = PeptideCompatibilityData.validatedStacks.contains { stack in
                let goalRelevant = stack.goal.localizedCaseInsensitiveContains(goal.category.displayName) ||
                    goal.benefitTerms.contains { stack.goal.localizedCaseInsensitiveContains($0) }
                let isComplete = stack.peptideAbbreviations.allSatisfy { currentAbbreviations.contains($0) }
                return goalRelevant && isComplete
            }
            if hasCompleteStack {
                coveredDimensions += 1
            }
        }

        let score = totalDimensions > 0 ? Double(coveredDimensions) / Double(totalDimensions) : 0
        return StackCompleteness(
            score: score,
            coveredGoals: coveredGoals,
            missingCategories: missingCategories,
            suggestions: suggestions
        )
    }

    // MARK: - Cycle Transitions

    /// Identifies peptides approaching or past their recommended cycle end.
    static func cycleTransitions(
        for activeProtocols: [PeptideProtocol]
    ) -> [CycleTransition] {
        let calendar = Calendar.current
        var transitions: [CycleTransition] = []

        for proto in activeProtocols {
            for peptide in proto.peptides {
                guard let cycle = PeptideTimingData.cycleProtocols[peptide.abbreviation] else { continue }
                let weeksElapsed = calendar.dateComponents(
                    [.weekOfYear], from: proto.startDate, to: Date()
                ).weekOfYear ?? 0
                let weeksRemaining = max(cycle.onWeeks - weeksElapsed, 0)

                // Show transition if within 2 weeks of cycle end or already overdue
                guard weeksRemaining <= 2 else { continue }
                transitions.append(CycleTransition(
                    peptideAbbreviation: peptide.abbreviation,
                    weeksRemaining: weeksRemaining,
                    suggestedReplacements: cycle.transitionSuggestions,
                    reason: cycle.reason
                ))
            }
        }

        return transitions.sorted { $0.weeksRemaining < $1.weeksRemaining }
    }

    // MARK: - Helpers

    struct ResolvedGoal {
        let displayName: String
        let category: PeptideCategory
        let benefitTerms: [String]
    }

    static func resolveGoals(_ goals: [String]) -> [ResolvedGoal] {
        goals.compactMap { goal in
            let lower = goal.lowercased()
            for mapping in goalKeywords where mapping.keywords.contains(where: { lower.contains($0) }) {
                return ResolvedGoal(displayName: goal, category: mapping.category, benefitTerms: mapping.benefitTerms)
            }
            return nil
        }
    }

    static func resolveMatch(
        _ stackName: String,
        in lookup: [String: Peptide],
        database: [Peptide]
    ) -> Peptide? {
        if let exact = lookup[stackName] { return exact }

        // Strip parenthetical qualifiers: "TB-500 (Thymosin Beta-4)" → "TB-500"
        let baseName = stackName.replacingOccurrences(
            of: "\\s*\\(.*\\)", with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespaces).lowercased()

        if !baseName.isEmpty && baseName != stackName, let exact = lookup[baseName] {
            return exact
        }

        // Fuzzy: only for names ≥ 4 chars
        let query = baseName.isEmpty ? stackName : baseName
        guard query.count >= 4 else { return nil }

        return database.first {
            $0.abbreviation.localizedCaseInsensitiveContains(query) ||
            $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    // normalizedSideEffect lives in StackRecommendationEngine+Warnings.swift since
    // it's only used by warnings logic.
}
