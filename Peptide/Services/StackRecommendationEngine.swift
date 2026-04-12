import Foundation

enum StackRecommendationEngine {

    // MARK: - Models

    struct Recommendation: Identifiable {
        let id: UUID
        let peptide: Peptide
        let score: Int
        let reasons: [String]
    }

    struct Warning: Identifiable {
        let id = UUID()
        let severity: Severity
        let title: String
        let detail: String
        let peptides: [String]

        enum Severity {
            case caution, danger
        }
    }

    // MARK: - Recommendations

    static func recommendations(
        for currentPeptides: [Peptide],
        from database: [Peptide],
        limit: Int = 5
    ) -> [Recommendation] {
        guard !currentPeptides.isEmpty else { return [] }

        let currentNames = Set(currentPeptides.map { $0.abbreviation.lowercased() })
        let currentFullNames = Set(currentPeptides.map { $0.name.lowercased() })
        let currentIds = Set(currentPeptides.map(\.id))

        // Build a lookup from lowercased name/abbreviation → Peptide
        let dbByName: [String: Peptide] = database.reduce(into: [:]) { dict, p in
            dict[p.abbreviation.lowercased()] = p
            dict[p.name.lowercased()] = p
        }

        // Score each recommended peptide by how many current stack peptides suggest it
        var scores: [UUID: (peptide: Peptide, score: Int, recommenders: [String])] = [:]

        for current in currentPeptides {
            for stackName in current.commonStacks {
                let key = stackName.lowercased()

                // Try direct match first, then fuzzy contains
                let match = dbByName[key] ?? database.first {
                    $0.abbreviation.localizedCaseInsensitiveContains(stackName) ||
                    $0.name.localizedCaseInsensitiveContains(stackName) ||
                    stackName.localizedCaseInsensitiveContains($0.abbreviation)
                }

                guard let found = match, !currentIds.contains(found.id) else { continue }

                if var existing = scores[found.id] {
                    existing.score += 1
                    existing.recommenders.append(current.abbreviation)
                    scores[found.id] = existing
                } else {
                    scores[found.id] = (found, 1, [current.abbreviation])
                }
            }
        }

        // Also boost peptides that share the same category benefits
        for candidate in database where !currentIds.contains(candidate.id) {
            let sharedBenefits = candidate.benefits.filter { benefit in
                currentPeptides.contains { current in
                    current.benefits.contains { $0.localizedCaseInsensitiveContains(benefit) }
                }
            }
            if sharedBenefits.count >= 2, scores[candidate.id] != nil {
                scores[candidate.id]?.score += 1
            }
        }

        return scores.values
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { entry in
                let reasonText = entry.recommenders.count <= 3
                    ? entry.recommenders.joined(separator: ", ")
                    : entry.recommenders.prefix(2).joined(separator: ", ") + " +\(entry.recommenders.count - 2) more"
                return Recommendation(
                    id: entry.peptide.id,
                    peptide: entry.peptide,
                    score: entry.score,
                    reasons: ["Pairs well with \(reasonText)"]
                )
            }
    }

    // MARK: - Compatibility Warnings

    static func warnings(for currentPeptides: [Peptide]) -> [Warning] {
        guard currentPeptides.count >= 2 else { return [] }

        var warnings: [Warning] = []

        // 1. Check for overlapping side effects that compound (3+ peptides share same effect)
        var sideEffectCounts: [String: [String]] = [:]
        for peptide in currentPeptides {
            for effect in peptide.sideEffects {
                let normalized = effect.lowercased()
                    .replacingOccurrences(of: "possible ", with: "")
                    .replacingOccurrences(of: "mild ", with: "")
                    .trimmingCharacters(in: .whitespaces)

                let key = normalizedSideEffect(normalized)
                sideEffectCounts[key, default: []].append(peptide.abbreviation)
            }
        }

        for (effect, peptideNames) in sideEffectCounts where peptideNames.count >= 3 {
            let uniqueNames = Array(Set(peptideNames))
            warnings.append(Warning(
                severity: .caution,
                title: "Compounding side effect risk",
                detail: "\(uniqueNames.count) peptides share \"\(effect)\" as a potential side effect. Monitor closely.",
                peptides: uniqueNames
            ))
        }

        // 2. Check category overloading (>3 peptides in same category)
        let categoryGroups = Dictionary(grouping: currentPeptides, by: \.category)
        for (category, peptides) in categoryGroups where peptides.count > 3 {
            warnings.append(Warning(
                severity: .caution,
                title: "Heavy \(category.displayName) focus",
                detail: "\(peptides.count) peptides in the \(category.displayName) category. Consider diversifying for a balanced stack.",
                peptides: peptides.map(\.abbreviation)
            ))
        }

        // 3. Check cross-contraindication references
        for i in 0..<currentPeptides.count {
            for j in (i + 1)..<currentPeptides.count {
                let a = currentPeptides[i]
                let b = currentPeptides[j]

                let aContra = a.contraindications.joined(separator: " ").lowercased()
                let bContra = b.contraindications.joined(separator: " ").lowercased()

                let aReferences = aContra.contains(b.abbreviation.lowercased()) ||
                                  aContra.contains(b.name.lowercased())
                let bReferences = bContra.contains(a.abbreviation.lowercased()) ||
                                  bContra.contains(a.name.lowercased())

                if aReferences || bReferences {
                    warnings.append(Warning(
                        severity: .danger,
                        title: "Potential interaction",
                        detail: "\(a.abbreviation) and \(b.abbreviation) may have contraindications when used together. Review each peptide's safety information.",
                        peptides: [a.abbreviation, b.abbreviation]
                    ))
                }
            }
        }

        // 4. Check for peptides with overlapping mechanisms that might over-stimulate a pathway
        let ghReleasers = currentPeptides.filter {
            $0.mechanism.localizedCaseInsensitiveContains("growth hormone") &&
            ($0.mechanism.localizedCaseInsensitiveContains("releas") ||
             $0.mechanism.localizedCaseInsensitiveContains("secretagogue") ||
             $0.mechanism.localizedCaseInsensitiveContains("GHRH"))
        }
        if ghReleasers.count >= 3 {
            warnings.append(Warning(
                severity: .caution,
                title: "Multiple GH secretagogues",
                detail: "Using \(ghReleasers.count) growth hormone releasers simultaneously may cause excessive GH elevation. Consider cycling or reducing.",
                peptides: ghReleasers.map(\.abbreviation)
            ))
        }

        // Sort: danger first, then caution
        return warnings.sorted { a, b in
            switch (a.severity, b.severity) {
            case (.danger, .caution): return true
            case (.caution, .danger): return false
            default: return false
            }
        }
    }

    // MARK: - Helpers

    private static func normalizedSideEffect(_ raw: String) -> String {
        let keywords = [
            "nausea", "headache", "fatigue", "dizziness", "water retention",
            "injection site", "flushing", "appetite", "blood pressure",
            "cortisol", "insulin", "blood sugar", "numbness", "tingling",
            "joint pain", "swelling"
        ]
        for keyword in keywords where raw.contains(keyword) {
            return keyword
        }
        return raw.prefix(40).lowercased()
    }
}
