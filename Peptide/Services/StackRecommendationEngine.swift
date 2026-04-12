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

        enum Severity: Comparable {
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

        let currentIds = Set(currentPeptides.map(\.id))

        // Build a lookup from lowercased name/abbreviation → Peptide
        let dbByName: [String: Peptide] = database.reduce(into: [:]) { dict, p in
            dict[p.abbreviation.lowercased()] = p
            dict[p.name.lowercased()] = p
        }

        // Pre-compute current benefit keywords for O(1) lookups
        let currentBenefits = Set(currentPeptides.flatMap(\.benefits).map { $0.lowercased() })

        // Score each recommended peptide by how many current stack peptides suggest it
        var scores: [UUID: (peptide: Peptide, score: Int, recommenders: Set<String>)] = [:]

        for current in currentPeptides {
            let seenStacks = Set(current.commonStacks.map { $0.lowercased() })
            for stackName in seenStacks {
                guard let found = resolveMatch(stackName, in: dbByName, database: database),
                      !currentIds.contains(found.id) else { continue }

                if var existing = scores[found.id] {
                    existing.score += 1
                    existing.recommenders.insert(current.abbreviation)
                    scores[found.id] = existing
                } else {
                    scores[found.id] = (found, 1, [current.abbreviation])
                }
            }
        }

        // Boost peptides that share benefits with the current stack
        for candidate in database where !currentIds.contains(candidate.id) {
            let sharedCount = candidate.benefits.filter { currentBenefits.contains($0.lowercased()) }.count
            if sharedCount >= 2, scores[candidate.id] != nil {
                scores[candidate.id]?.score += 1
            }
        }

        return scores.values
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { entry in
                let names = Array(entry.recommenders).sorted()
                let reasonText = names.count <= 3
                    ? names.joined(separator: ", ")
                    : names.prefix(2).joined(separator: ", ") + " +\(names.count - 2) more"
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

        // 1. Check for overlapping side effects that compound (3+ distinct peptides share same effect)
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

        for (effect, peptideNames) in sideEffectPeptides where peptideNames.count >= 3 {
            warnings.append(Warning(
                severity: .caution,
                title: "Compounding side effect risk",
                detail: "\(peptideNames.count) peptides share \"\(effect)\" as a potential side effect. Monitor closely.",
                peptides: peptideNames.sorted()
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

        // 3. Check cross-contraindication references (only for names ≥ 4 chars to avoid false positives)
        for i in 0..<currentPeptides.count {
            for j in (i + 1)..<currentPeptides.count {
                let a = currentPeptides[i]
                let b = currentPeptides[j]

                let aReferences = b.abbreviation.count >= 4 && a.contraindications.contains {
                    $0.localizedCaseInsensitiveContains(b.abbreviation) ||
                    $0.localizedCaseInsensitiveContains(b.name)
                }
                let bReferences = a.abbreviation.count >= 4 && b.contraindications.contains {
                    $0.localizedCaseInsensitiveContains(a.abbreviation) ||
                    $0.localizedCaseInsensitiveContains(a.name)
                }

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

        // 4. Check for multiple GH secretagogues that might over-stimulate
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

        return warnings.sorted { $0.severity > $1.severity }
    }

    // MARK: - Helpers

    /// Resolve a commonStacks name to a database Peptide via exact key match, then careful substring match.
    private static func resolveMatch(
        _ stackName: String,
        in lookup: [String: Peptide],
        database: [Peptide]
    ) -> Peptide? {
        // Exact match on lowercased abbreviation or name
        if let exact = lookup[stackName] { return exact }

        // Fuzzy: only for names ≥ 4 chars to prevent "GH" matching "GHK-Cu"
        guard stackName.count >= 4 else { return nil }

        return database.first {
            $0.abbreviation.localizedCaseInsensitiveContains(stackName) ||
            $0.name.localizedCaseInsensitiveContains(stackName)
        }
    }

    /// Normalize side effect strings to canonical keywords for grouping.
    /// Keyword order matters: more specific terms should come first.
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
