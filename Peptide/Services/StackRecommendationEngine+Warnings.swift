import Foundation

// Compatibility-warning logic. Lives in its own file so the main
// StackRecommendationEngine.swift stays focused on the recommendation
// algorithm and stack-completeness/cycle-transition computations.

extension StackRecommendationEngine {

    /// Backward-compatible entry point.
    static func warnings(for currentPeptides: [Peptide]) -> [Warning] {
        warnings(for: currentPeptides, activeProtocols: [])
    }

    /// Full context-aware warnings with cycle, desensitization, hepatotoxicity, and timing checks.
    static func warnings(
        for currentPeptides: [Peptide],
        activeProtocols: [PeptideProtocol]
    ) -> [Warning] {
        guard !currentPeptides.isEmpty else { return [] }

        var warnings: [Warning] = []

        // --- Pairwise warnings (require 2+ peptides) ---
        guard currentPeptides.count >= 2 else {
            // Skip to per-peptide warnings below
            return perPeptideWarnings(for: currentPeptides, activeProtocols: activeProtocols)
                .sorted { $0.severity > $1.severity }
        }

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
                } else if freq.contains("3x") || freq.contains("3 times") {
                    dailyCount += 3
                } else if freq.contains("2x") || freq.contains("twice") || freq.contains("2 times") {
                    dailyCount += 2
                } else {
                    dailyCount += 1
                }
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
                matchingNames.isSubset(of: Set(w.peptides))
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

        // 9-12. Per-peptide warnings (also fire for single-peptide stacks)
        warnings.append(contentsOf: perPeptideWarnings(for: currentPeptides, activeProtocols: activeProtocols))

        return warnings.sorted { $0.severity > $1.severity }
    }

    /// Warnings that apply per-peptide (cycle length, desensitization, hepatotoxicity, timing).
    /// These fire regardless of stack size — a single overdue peptide still deserves a warning.
    private static func perPeptideWarnings(
        for currentPeptides: [Peptide],
        activeProtocols: [PeptideProtocol]
    ) -> [Warning] {
        var warnings: [Warning] = []
        let calendar = Calendar.current

        // 9. Cycle length warning
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

        return warnings
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
