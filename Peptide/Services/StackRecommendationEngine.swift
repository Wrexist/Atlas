import Foundation

enum StackRecommendationEngine {

    // MARK: - Models

    enum RecommendationReason {
        case commonStack(pairsWith: [String])
        case goalMatch(goal: String)
        case categorySynergy(description: String)
        case sharedBenefits(count: Int)
        case validatedStack(name: String, synergy: String)
        case timingComplement(description: String)
        case complianceBoost(category: String)
        case routeDiversity(route: String)
        case halfLifeComplement(description: String)
        case seasonalRelevance(description: String)

        var icon: String {
            switch self {
            case .commonStack: return "link"
            case .goalMatch: return "target"
            case .categorySynergy: return "sparkles"
            case .sharedBenefits: return "square.on.square"
            case .validatedStack: return "checkmark.seal.fill"
            case .timingComplement: return "clock"
            case .complianceBoost: return "checkmark.circle"
            case .routeDiversity: return "syringe"
            case .halfLifeComplement: return "waveform"
            case .seasonalRelevance: return "leaf"
            }
        }

        var text: String {
            switch self {
            case .commonStack(let names):
                let display = names.count <= 3
                    ? names.joined(separator: ", ")
                    : names.prefix(2).joined(separator: ", ") + " +\(names.count - 2) more"
                return "Pairs well with \(display)"
            case .goalMatch(let goal):
                return "Matches your \"\(goal)\" goal"
            case .categorySynergy(let desc):
                return desc
            case .sharedBenefits(let count):
                return "Shares \(count) benefits with your stack"
            case .validatedStack(let name, _):
                return "Part of \(name) — research-backed combination"
            case .timingComplement(let desc):
                return desc
            case .complianceBoost(let category):
                return "You're highly compliant with \(category) peptides"
            case .routeDiversity(let route):
                return route
            case .halfLifeComplement(let desc):
                return desc
            case .seasonalRelevance(let desc):
                return desc
            }
        }
    }

    enum Confidence: Comparable {
        case low, medium, high

        var label: String {
            switch self {
            case .low: return "Exploratory"
            case .medium: return "Suggested"
            case .high: return "Research-backed"
            }
        }
    }

    struct Recommendation: Identifiable {
        let id: UUID
        let peptide: Peptide
        let score: Int
        let reasons: [RecommendationReason]
        let confidence: Confidence
    }

    struct Warning: Identifiable {
        let id = UUID()
        let severity: Severity
        let title: String
        let detail: String
        let suggestion: String
        let peptides: [String]
        let icon: String

        enum Severity: Comparable {
            case info, caution, danger
        }
    }

    struct StackCompleteness {
        let score: Double
        let coveredGoals: [String]
        let missingCategories: [PeptideCategory]
        let suggestions: [String]
    }

    struct CycleTransition: Identifiable {
        let id = UUID()
        let peptideAbbreviation: String
        let weeksRemaining: Int
        let suggestedReplacements: [String]
        let reason: String
    }

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
        (["cognitive", "focus", "brain", "memory", "mental"],
         .cognitive, ["cognitive", "focus", "memory", "brain", "neuroprotect", "mental"]),
        (["anti-aging", "longevity", "skin", "aging", "youth"],
         .antiAging, ["anti-aging", "collagen", "skin", "longevity", "elastin", "wrinkle"]),
        (["immune", "immunity", "infection", "defense"],
         .immune, ["immune", "antimicrobial", "inflammation", "pathogen", "defense"]),
        (["weight", "fat", "metabolic", "lean", "diet", "appetite"],
         .metabolic, ["weight", "fat", "metabolic", "appetite", "lipolytic", "satiety"]),
    ]

    // MARK: - Mechanism Pathways

    private enum MechanismPathway: String, CaseIterable {
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
            for pathway in allCases {
                if pathway.keywords.contains(where: { lower.contains($0) }) {
                    found.insert(pathway)
                }
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

    // MARK: - Compatibility Warnings

    /// Backward-compatible entry point.
    static func warnings(for currentPeptides: [Peptide]) -> [Warning] {
        warnings(for: currentPeptides, activeProtocols: [])
    }

    /// Full context-aware warnings with cycle, desensitization, hepatotoxicity, and timing checks.
    static func warnings(
        for currentPeptides: [Peptide],
        activeProtocols: [PeptideProtocol]
    ) -> [Warning] {
        guard currentPeptides.count >= 2 else { return [] }

        var warnings: [Warning] = []

        // 1. Compounding side effects
        var sideEffectPeptides: [String: Set<String>] = [:]
        for peptide in currentPeptides {
            for effect in peptide.sideEffects {
                let normalized = effect.lowercased()
                    .replacingOccurrences(of: "possible ", with: "")
                    .replacingOccurrences(of: "mild ", with: "")
                    .replacingOccurrences(of: "temporary ", with: "")
                    .trimmingCharacters(in: .whitespaces)
                let key = normalizedSideEffect(normalized)
                sideEffectPeptides[key, default: []].insert(peptide.abbreviation)
            }
        }
        for (effect, names) in sideEffectPeptides where names.count >= 3 {
            warnings.append(Warning(
                severity: .caution,
                title: "Compounding \"\(effect)\" risk",
                detail: "\(names.count) peptides in your stack share this side effect, which may intensify.",
                suggestion: "Consider staggering administration times or reducing doses to minimize compounding.",
                peptides: names.sorted(),
                icon: "waveform.path.ecg"
            ))
        }

        // 2. Category overloading
        let categoryGroups = Dictionary(grouping: currentPeptides, by: \.category)
        for (category, peptides) in categoryGroups where peptides.count > 3 {
            warnings.append(Warning(
                severity: .caution,
                title: "Heavy \(category.displayName) focus",
                detail: "\(peptides.count) peptides targeting \(category.displayName). Diminishing returns likely.",
                suggestion: "Try swapping one for a complementary category to create synergy.",
                peptides: peptides.map(\.abbreviation),
                icon: "square.stack.3d.up.trianglebadge.exclamationmark.fill"
            ))
        }

        // 3. Cross-contraindication references
        for i in 0..<currentPeptides.count {
            for j in (i + 1)..<currentPeptides.count {
                let a = currentPeptides[i]
                let b = currentPeptides[j]
                // Check abbreviation only if ≥4 chars (avoid "GH" matching "high"), but always check full name
                let aRefs = a.contraindications.contains {
                    (b.abbreviation.count >= 4 && $0.localizedCaseInsensitiveContains(b.abbreviation)) ||
                    (b.name.count >= 4 && $0.localizedCaseInsensitiveContains(b.name))
                }
                let bRefs = b.contraindications.contains {
                    (a.abbreviation.count >= 4 && $0.localizedCaseInsensitiveContains(a.abbreviation)) ||
                    (a.name.count >= 4 && $0.localizedCaseInsensitiveContains(a.name))
                }
                if aRefs || bRefs {
                    warnings.append(Warning(
                        severity: .danger,
                        title: "Potential interaction",
                        detail: "\(a.abbreviation) and \(b.abbreviation) may have contraindications when combined.",
                        suggestion: "Review both peptides' safety profiles and consult a professional before combining.",
                        peptides: [a.abbreviation, b.abbreviation],
                        icon: "xmark.octagon.fill"
                    ))
                }
            }
        }

        // 4. Mechanism pathway redundancy (receptor-level, not just "GH releasers")
        let pathwayGroups = Dictionary(grouping: currentPeptides) { peptide -> MechanismPathway? in
            let pathways = MechanismPathway.detect(from: peptide.mechanism)
            // Return the most specific receptor-level pathway
            if pathways.contains(.ghsrAgonist) { return .ghsrAgonist }
            if pathways.contains(.ghrhAnalog) { return .ghrhAnalog }
            if pathways.contains(.appetiteRegulation) { return .appetiteRegulation }
            return nil
        }
        for (pathway, peptides) in pathwayGroups {
            guard let pathway, peptides.count >= 2 else { continue }
            let names = peptides.map(\.abbreviation)
            switch pathway {
            case .ghsrAgonist:
                warnings.append(Warning(
                    severity: .caution,
                    title: "Redundant GHS-R agonists",
                    detail: "\(names.joined(separator: " & ")) target the same ghrelin receptor. Risk of desensitization.",
                    suggestion: "Keep one GHS-R agonist and pair with a GHRH analog (e.g., CJC-1295) for synergistic GH release.",
                    peptides: names,
                    icon: "arrow.triangle.2.circlepath"
                ))
            case .ghrhAnalog where peptides.count >= 2:
                warnings.append(Warning(
                    severity: .caution,
                    title: "Multiple GHRH analogs",
                    detail: "\(peptides.count) GHRH pathway peptides may over-stimulate growth hormone release.",
                    suggestion: "Consider cycling rather than stacking. One GHRH analog + one GHS-R agonist is the proven synergy pattern.",
                    peptides: names,
                    icon: "arrow.triangle.2.circlepath"
                ))
            case .appetiteRegulation where peptides.count >= 2:
                warnings.append(Warning(
                    severity: .caution,
                    title: "Multiple appetite regulators",
                    detail: "\(names.joined(separator: " & ")) both affect appetite/satiety pathways.",
                    suggestion: "Stacking GLP-1 agonists can amplify GI side effects. Consider using one at a time.",
                    peptides: names,
                    icon: "fork.knife"
                ))
            default: break
            }
        }

        // 5. Injection burden
        let injectables = currentPeptides.filter {
            let route = $0.adminRoute.lowercased()
            return route.contains("subcutaneous") || route.contains("intramuscular") || route.contains("intravenous")
        }
        if injectables.count >= 4 {
            var dailyCount = 0
            for p in injectables {
                let freq = p.frequency.lowercased()
                let isWeekly = freq.contains("week") || freq.contains("once per")
                if isWeekly {
                    // Weekly peptides contribute fractionally to daily burden
                    dailyCount += 1 // count as 1 since they do require an injection day
                } else if freq.contains("3x") || freq.contains("3 times") { dailyCount += 3 }
                else if freq.contains("2x") || freq.contains("twice") || freq.contains("2 times") { dailyCount += 2 }
                else { dailyCount += 1 }
            }
            if dailyCount > 4 {
                warnings.append(Warning(
                    severity: .caution,
                    title: "High injection burden",
                    detail: "Your stack requires ~\(dailyCount) injections daily across \(injectables.count) peptides.",
                    suggestion: "Group compatible peptides at the same injection time to reduce needle count and improve adherence.",
                    peptides: injectables.map(\.abbreviation),
                    icon: "syringe.fill"
                ))
            }
        }

        // 6. Known interactions from research database
        let abbreviations = currentPeptides.map(\.abbreviation)
        for i in 0..<abbreviations.count {
            for j in (i + 1)..<abbreviations.count {
                if let interaction = PeptideCompatibilityData.findInteraction(
                    between: abbreviations[i], and: abbreviations[j]
                ) {
                    // Only add if not already covered by mechanism pathway check above
                    let alreadyCovered = warnings.contains { w in
                        w.peptides.contains(abbreviations[i]) && w.peptides.contains(abbreviations[j])
                    }
                    guard !alreadyCovered else { continue }

                    let warnSeverity: Warning.Severity
                    let warnIcon: String
                    switch interaction.severity {
                    case .danger:
                        warnSeverity = .danger
                        warnIcon = "xmark.octagon.fill"
                    case .caution:
                        warnSeverity = .caution
                        warnIcon = "exclamationmark.triangle.fill"
                    }

                    warnings.append(Warning(
                        severity: warnSeverity,
                        title: "Known interaction",
                        detail: interaction.reason,
                        suggestion: interaction.recommendation,
                        peptides: [interaction.peptideA, interaction.peptideB],
                        icon: warnIcon
                    ))
                }
            }
        }

        // 7. Pathway group violations from knowledge base
        for group in PeptideCompatibilityData.pathwayGroups {
            let matching = currentPeptides.filter { group.peptideAbbreviations.contains($0.abbreviation) }
            guard matching.count > group.maxSafe else { continue }
            // Skip if a prior warning already covers 2+ of the same peptides (overlap, not subset)
            let matchingNames = Set(matching.map(\.abbreviation))
            let alreadyCovered = warnings.contains { w in
                matchingNames.intersection(Set(w.peptides)).count >= 2
            }
            guard !alreadyCovered else { continue }

            warnings.append(Warning(
                severity: .caution,
                title: "\(group.pathway) overload",
                detail: "\(matching.count) peptides target the \(group.pathway) pathway (recommended max: \(group.maxSafe)).",
                suggestion: group.warningText,
                peptides: matching.map(\.abbreviation),
                icon: "arrow.triangle.2.circlepath"
            ))
        }

        // 8. Angiogenic risk stacking
        let angiogenic = currentPeptides.filter {
            PeptideCompatibilityData.angiogenicPeptides.contains($0.abbreviation)
        }
        if angiogenic.count >= 3 {
            warnings.append(Warning(
                severity: .caution,
                title: "High angiogenic activity",
                detail: "\(angiogenic.count) peptides in your stack promote blood vessel growth. Use caution if you have a history of malignancy, as angiogenesis can theoretically fuel tumor vascularization.",
                suggestion: "If you have any cancer history, consult an oncologist before using multiple angiogenic peptides together.",
                peptides: angiogenic.map(\.abbreviation),
                icon: "staroflife.fill"
            ))
        }

        // 9. Cycle length warning
        let calendar = Calendar.current
        for proto in activeProtocols {
            for peptide in proto.peptides {
                guard let cycle = PeptideTimingData.cycleProtocols[peptide.abbreviation] else { continue }
                let weeksElapsed = calendar.dateComponents(
                    [.weekOfYear], from: proto.startDate, to: Date()
                ).weekOfYear ?? 0
                guard weeksElapsed > cycle.onWeeks else { continue }
                let overBy = weeksElapsed - cycle.onWeeks
                let transitionText = cycle.transitionSuggestions.isEmpty
                    ? ""
                    : " Consider transitioning to \(cycle.transitionSuggestions.joined(separator: " or "))."
                warnings.append(Warning(
                    severity: .caution,
                    title: "\(peptide.abbreviation) — \(overBy)w over cycle",
                    detail: "Recommended cycle is \(cycle.onWeeks) weeks on / \(cycle.offWeeks) weeks off. You're at week \(weeksElapsed). \(cycle.reason).",
                    suggestion: "Schedule a \(cycle.offWeeks)-week off period.\(transitionText)",
                    peptides: [peptide.abbreviation],
                    icon: "clock.arrow.circlepath"
                ))
            }
        }

        // 10. Desensitization risk
        for peptide in currentPeptides {
            guard let info = PeptideTimingData.desensitizationRisks[peptide.abbreviation] else { continue }
            let matchingProtocol = activeProtocols.first { proto in
                proto.peptides.contains(where: { $0.abbreviation == peptide.abbreviation })
            }
            guard let proto = matchingProtocol else { continue }
            let weeks = calendar.dateComponents(
                [.weekOfYear], from: proto.startDate, to: Date()
            ).weekOfYear ?? 0
            guard weeks >= info.riskOnsetWeeks else { continue }
            let offWeeks = PeptideTimingData.cycleProtocols[peptide.abbreviation]?.offWeeks ?? 4
            warnings.append(Warning(
                severity: .caution,
                title: "\(info.receptor) desensitization risk",
                detail: "\(peptide.abbreviation) active for \(weeks) weeks. \(info.description) typically begins around week \(info.riskOnsetWeeks).",
                suggestion: "Consider a \(offWeeks)-week washout period to restore receptor sensitivity.",
                peptides: [peptide.abbreviation],
                icon: "arrow.down.right.circle"
            ))
        }

        // 11. Hepatotoxicity stacking
        let hepatotoxic = currentPeptides.filter {
            PeptideCompatibilityData.hepatotoxicPeptides.contains($0.abbreviation)
        }
        if hepatotoxic.count >= 2 {
            warnings.append(Warning(
                severity: .caution,
                title: "Multiple liver-stressing peptides",
                detail: "\(hepatotoxic.count) peptides in your stack have hepatic metabolism burden: \(hepatotoxic.map(\.abbreviation).joined(separator: ", ")).",
                suggestion: "Monitor liver enzymes (ALT, AST) and avoid combining with alcohol or hepatotoxic supplements.",
                peptides: hepatotoxic.map(\.abbreviation),
                icon: "exclamationmark.triangle.fill"
            ))
        }

        // 12. Timing conflicts
        for i in 0..<currentPeptides.count {
            for j in (i + 1)..<currentPeptides.count {
                let a = currentPeptides[i]
                let b = currentPeptides[j]
                if let timingA = PeptideTimingData.timingRecommendations[a.abbreviation],
                   timingA.avoidWith.contains(b.abbreviation) {
                    warnings.append(Warning(
                        severity: .info,
                        title: "Timing separation recommended",
                        detail: "\(a.abbreviation) and \(b.abbreviation) should be separated when administered.",
                        suggestion: timingA.notes,
                        peptides: [a.abbreviation, b.abbreviation],
                        icon: "clock.badge.exclamationmark"
                    ))
                } else if let timingB = PeptideTimingData.timingRecommendations[b.abbreviation],
                          timingB.avoidWith.contains(a.abbreviation) {
                    warnings.append(Warning(
                        severity: .info,
                        title: "Timing separation recommended",
                        detail: "\(a.abbreviation) and \(b.abbreviation) should be separated when administered.",
                        suggestion: timingB.notes,
                        peptides: [a.abbreviation, b.abbreviation],
                        icon: "clock.badge.exclamationmark"
                    ))
                }
            }
        }

        return warnings.sorted { $0.severity > $1.severity }
    }

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
                let goalRelevant = stack.goal.localizedCaseInsensitiveContains(goal.displayName) ||
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
            for mapping in goalKeywords {
                if mapping.keywords.contains(where: { lower.contains($0) }) {
                    return ResolvedGoal(displayName: goal, category: mapping.category, benefitTerms: mapping.benefitTerms)
                }
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

    private static func normalizedSideEffect(_ raw: String) -> String {
        let keywords = [
            "injection site", "blood pressure", "blood sugar", "water retention",
            "joint pain", "nausea", "headache", "fatigue", "dizziness",
            "flushing", "appetite", "cortisol", "insulin", "numbness",
            "tingling", "swelling"
        ]
        for keyword in keywords where raw.contains(keyword) {
            return keyword
        }
        return String(raw.prefix(40))
    }
}
