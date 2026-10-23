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
                .sorted(by: Warning.displayOrder)
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
                title: String(localized: "Compounding \"\(effect)\" risk"),
                detail: String(localized: "\(names.count) peptides in your protocol share this side effect, which may intensify."),
                suggestion: String(localized: "Discuss this overlap with a qualified clinician before continuing the protocol."),
                peptides: names.sorted(),
                icon: "waveform.path.ecg"
            ))
        }

        // 2. Category overloading
        let categoryGroups = Dictionary(grouping: currentPeptides, by: \.category)
        for (category, peptides) in categoryGroups where peptides.count > 3 {
            warnings.append(Warning(
                severity: .caution,
                title: String(localized: "Heavy \(category.displayName) focus"),
                detail: String(localized: "\(peptides.count) peptides targeting \(category.displayName). Diminishing returns likely."),
                suggestion: String(localized: "Try swapping one for a complementary category to create synergy."),
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
                        title: String(localized: "Potential interaction"),
                        detail: String(localized: "\(a.abbreviation) and \(b.abbreviation) may have contraindications when combined."),
                        suggestion: String(localized: "Review both peptides' safety profiles and consult a professional before combining."),
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
                    title: String(localized: "Redundant GHS-R agonists"),
                    detail: "\(names.joined(separator: " & ")) target the same ghrelin receptor. Risk of desensitization.",
                    suggestion: String(localized: "Research usually pairs one GHS-R agonist with one GHRH analog (e.g., CJC-1295). Discuss changes with a qualified clinician."),
                    peptides: names,
                    icon: "arrow.triangle.2.circlepath"
                ))
            case .ghrhAnalog where peptides.count >= 2:
                warnings.append(Warning(
                    severity: .caution,
                    title: String(localized: "Multiple GHRH analogs"),
                    detail: String(localized: "\(peptides.count) GHRH pathway peptides may over-stimulate growth hormone release."),
                    suggestion: String(localized: "Research usually pairs one GHRH analog with one GHS-R agonist rather than combining analogs. Discuss changes with a qualified clinician."),
                    peptides: names,
                    icon: "arrow.triangle.2.circlepath"
                ))
            case .appetiteRegulation where peptides.count >= 2:
                warnings.append(Warning(
                    severity: .caution,
                    title: String(localized: "Multiple appetite regulators"),
                    detail: "\(names.joined(separator: " & ")) both affect appetite/satiety pathways.",
                    suggestion: String(localized: "Combining GLP-1 agonists can amplify GI side effects. Discuss using one at a time with a qualified clinician."),
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
                    title: String(localized: "High injection burden"),
                    detail: String(localized: "Your protocol requires ~\(dailyCount) injections daily across \(injectables.count) peptides."),
                    suggestion: String(localized: "Group compatible peptides at the same injection time to reduce needle count and improve adherence."),
                    peptides: injectables.map(\.abbreviation),
                    icon: "syringe.fill",
                    kind: .injectionBurden
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
                        title: String(localized: "Known interaction"),
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
                title: String(localized: "\(group.pathway) overload"),
                detail: String(localized: "\(matching.count) peptides in your protocol target the \(group.pathway) pathway. Some sources describe using no more than \(group.maxSafe) together."),
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
                title: String(localized: "High angiogenic activity"),
                detail: String(localized: "\(angiogenic.count) peptides in your protocol are described in research as promoting blood vessel growth. Some sources flag this for people with a history of cancer."),
                suggestion: String(localized: "Discuss this combination with your clinician, especially if you have any cancer history."),
                peptides: angiogenic.map(\.abbreviation),
                icon: "staroflife.fill"
            ))
        }

        // 9-12. Per-peptide warnings (also fire for single-peptide stacks)
        warnings.append(contentsOf: perPeptideWarnings(for: currentPeptides, activeProtocols: activeProtocols))

        return warnings.sorted(by: Warning.displayOrder)
    }

    /// Warnings that apply per-peptide (cycle length, desensitization, hepatotoxicity, timing).
    /// These fire regardless of stack size — a single overdue peptide still deserves a warning.
    private static func perPeptideWarnings(
        for currentPeptides: [Peptide],
        activeProtocols: [PeptideProtocol]
    ) -> [Warning] {
        var warnings: [Warning] = []
        let selected = Set(currentPeptides.map(\.abbreviation))

        // 9. Cycle length warning — only for the peptides being checked, and
        // measured within the current on-phase so a planned wash-out (or a
        // later cycle) doesn't read as an overrun.
        var overrunWarned: Set<String> = []
        for proto in activeProtocols {
            guard let weeksElapsed = weeksIntoCurrentRun(of: proto) else { continue }
            for peptide in proto.peptides where selected.contains(peptide.abbreviation) {
                guard let cycle = PeptideTimingData.cycleProtocols[peptide.abbreviation],
                      weeksElapsed > cycle.onWeeks,
                      overrunWarned.insert(peptide.abbreviation).inserted else { continue }
                let overBy = weeksElapsed - cycle.onWeeks
                warnings.append(Warning(
                    severity: .caution,
                    title: String(localized: "\(peptide.abbreviation) is \(overBy) weeks past its cycle"),
                    detail: String(localized: "Sources commonly describe \(cycle.onWeeks) weeks on and \(cycle.offWeeks) weeks off. You're at week \(weeksElapsed). \(cycle.reason)."),
                    suggestion: String(localized: "Review your cycle plan with your clinician."),
                    peptides: [peptide.abbreviation],
                    icon: "clock.arrow.circlepath",
                    kind: .cycleOverrun
                ))
            }
        }

        // 10. Desensitization risk — nothing is dosed during a wash-out.
        var desensitizationWarned: Set<String> = []
        for peptide in currentPeptides {
            guard let info = PeptideTimingData.desensitizationRisks[peptide.abbreviation],
                  desensitizationWarned.insert(peptide.abbreviation).inserted else { continue }
            let weeks = activeProtocols
                .filter { proto in proto.peptides.contains { $0.abbreviation == peptide.abbreviation } }
                .compactMap { weeksIntoCurrentRun(of: $0) }
                .max()
            guard let weeks, weeks >= info.riskOnsetWeeks else { continue }
            let offWeeks = PeptideTimingData.cycleProtocols[peptide.abbreviation]?.offWeeks ?? 4
            warnings.append(Warning(
                severity: .caution,
                title: String(localized: "\(info.receptor) desensitization risk"),
                detail: String(localized: "\(peptide.abbreviation) active for \(weeks) weeks. \(info.description) typically begins around week \(info.riskOnsetWeeks)."),
                suggestion: String(localized: "Some sources describe a \(offWeeks)-week break at this point. Discuss timing with your clinician."),
                peptides: [peptide.abbreviation],
                icon: "arrow.down.right.circle",
                kind: .desensitization
            ))
        }

        // 11. Hepatotoxicity stacking
        let hepatotoxic = currentPeptides.filter {
            PeptideCompatibilityData.hepatotoxicPeptides.contains($0.abbreviation)
        }
        if hepatotoxic.count >= 2 {
            warnings.append(Warning(
                severity: .caution,
                title: String(localized: "Multiple liver-stressing peptides"),
                detail: String(localized: "\(hepatotoxic.count) peptides in your protocol have hepatic metabolism burden: \(hepatotoxic.map(\.abbreviation).joined(separator: ", "))."),
                suggestion: String(localized: "Discuss liver monitoring with your clinician. Alcohol and some supplements also affect the liver."),
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
                        title: String(localized: "Timing separation recommended"),
                        detail: String(localized: "\(a.abbreviation) and \(b.abbreviation) should be separated when administered."),
                        suggestion: timingA.notes,
                        peptides: [a.abbreviation, b.abbreviation],
                        icon: "clock.badge.exclamationmark",
                        kind: .timingConflict
                    ))
                } else if let timingB = PeptideTimingData.timingRecommendations[b.abbreviation],
                          timingB.avoidWith.contains(a.abbreviation) {
                    warnings.append(Warning(
                        severity: .info,
                        title: String(localized: "Timing separation recommended"),
                        detail: String(localized: "\(a.abbreviation) and \(b.abbreviation) should be separated when administered."),
                        suggestion: timingB.notes,
                        peptides: [a.abbreviation, b.abbreviation],
                        icon: "clock.badge.exclamationmark",
                        kind: .timingConflict
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
