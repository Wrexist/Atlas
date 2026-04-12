import Foundation

// MARK: - New Scoring Signals (6-12)

extension StackRecommendationEngine {

    // MARK: Signal 6: Timing Awareness

    /// Bonus if candidate's preferred dosing window is underrepresented in current stack.
    static func scoreTiming(
        candidate: Peptide,
        context: RecommendationContext
    ) -> (Int, RecommendationReason?) {
        guard let candidateTiming = PeptideTimingData.timingRecommendations[candidate.abbreviation] else {
            return (0, nil)
        }

        let currentWindows = context.currentPeptides.compactMap {
            PeptideTimingData.timingRecommendations[$0.abbreviation]
        }.flatMap(\.preferredWindows)

        let windowCounts = Dictionary(grouping: currentWindows, by: \.self).mapValues(\.count)
        let candidateWindows = candidateTiming.preferredWindows

        // Bonus if any of the candidate's preferred windows has 0-1 existing peptides
        let hasUnderservedWindow = candidateWindows.contains { window in
            window != .anyTime && (windowCounts[window] ?? 0) <= 1
        }

        if hasUnderservedWindow {
            let windowName = candidateWindows.first { $0 != .anyTime }?.rawValue ?? "flexible"
            return (1, .timingComplement(description: "Fills a \(windowName) dosing gap in your schedule"))
        }
        return (0, nil)
    }

    // MARK: Signal 7: Compliance Weighting

    /// Bonus if user demonstrates high compliance with this peptide's category.
    static func scoreCompliance(
        candidate: Peptide,
        context: RecommendationContext
    ) -> (Int, RecommendationReason?) {
        guard !context.entries.isEmpty else { return (0, nil) }

        let categoryRate = context.categoryCompliance[candidate.category] ?? 0
        if categoryRate >= 0.85 {
            return (2, .complianceBoost(category: candidate.category.displayName))
        } else if categoryRate >= 0.70 {
            return (1, .complianceBoost(category: candidate.category.displayName))
        }
        return (0, nil)
    }

    // MARK: Signal 8: Route Diversity

    /// Bonus for non-injectable peptides when stack is injection-heavy.
    static func scoreRouteDiversity(
        candidate: Peptide,
        context: RecommendationContext
    ) -> (Int, RecommendationReason?) {
        let candidateRoute = candidate.adminRoute.lowercased()
        let isInjectable = candidateRoute.contains("subcutaneous") ||
                           candidateRoute.contains("intramuscular") ||
                           candidateRoute.contains("intravenous")

        let injectableCount = context.currentRoutes.filter {
            $0.contains("subcutaneous") || $0.contains("intramuscular") || $0.contains("intravenous")
        }.count

        guard !isInjectable && injectableCount >= 2 else { return (0, nil) }

        let routeLabel: String
        if candidateRoute.contains("oral") { routeLabel = "oral" }
        else if candidateRoute.contains("nasal") || candidateRoute.contains("intranasal") { routeLabel = "intranasal" }
        else if candidateRoute.contains("topical") { routeLabel = "topical" }
        else { routeLabel = candidateRoute }

        return (1, .routeDiversity(route: "Available as \(routeLabel) — reduces injection burden"))
    }

    // MARK: Signal 9: Half-Life Complementarity

    /// Bonus if candidate fills a temporal gap (all short-acting stack → long-acting bonus, vice versa).
    static func scoreHalfLife(
        candidate: Peptide,
        context: RecommendationContext
    ) -> (Int, RecommendationReason?) {
        let currentHalfLives = context.currentPeptides.compactMap { parseHalfLifeHours($0.halfLife) }
        guard !currentHalfLives.isEmpty else { return (0, nil) }
        guard let candidateHL = parseHalfLifeHours(candidate.halfLife) else { return (0, nil) }

        let avgHL = currentHalfLives.reduce(0.0, +) / Double(currentHalfLives.count)

        // If stack average is short (<4h) and candidate is long (>12h), or vice versa
        if avgHL < 4 && candidateHL > 12 {
            return (1, .halfLifeComplement(description: "Long-acting — extends coverage beyond your short-acting stack"))
        }
        if avgHL > 12 && candidateHL < 4 {
            return (1, .halfLifeComplement(description: "Short-acting — adds acute pulses to your long-acting stack"))
        }
        return (0, nil)
    }

    // MARK: Signal 10: Experience Filtering

    /// Beginners get a bonus for well-known peptides; no penalty for advanced users.
    static func scoreExperience(
        candidate: Peptide,
        context: RecommendationContext
    ) -> (Int, RecommendationReason?) {
        switch context.experienceLevel {
        case .beginner:
            if PeptideTimingData.wellKnownPeptides.contains(candidate.abbreviation) {
                return (1, nil) // Silent boost — no reason shown
            } else {
                return (-1, nil) // Mild penalty for niche peptides
            }
        case .intermediate, .advanced:
            return (0, nil)
        }
    }

    // MARK: Signal 11: Diminishing Returns

    /// Penalty for adding a 4th+ peptide in a category that already has 3+.
    static func scoreDiminishingReturns(
        candidate: Peptide,
        context: RecommendationContext
    ) -> (Int, RecommendationReason?) {
        let count = context.categoryCounts[candidate.category] ?? 0
        if count >= 3 {
            return (-2, nil) // Score penalty, no reason shown
        }
        return (0, nil)
    }

    // MARK: Signal 12: Seasonal Relevance

    /// Bonus if peptide's category matches current seasonal context.
    static func scoreSeasonal(
        candidate: Peptide,
        context: RecommendationContext
    ) -> (Int, RecommendationReason?) {
        let month = Calendar.current.component(.month, from: context.currentDate)
        if let boostMonths = PeptideTimingData.seasonalBoosts[candidate.category],
           boostMonths.contains(month) {
            let season: String
            switch month {
            case 12, 1, 2: season = "winter"
            case 3, 4, 5: season = "spring"
            case 6, 7, 8: season = "summer"
            default: season = "fall"
            }
            return (1, .seasonalRelevance(
                description: "\(candidate.category.displayName) peptides are especially relevant in \(season)"
            ))
        }
        return (0, nil)
    }

    // MARK: - Confidence Computation

    static func computeConfidence(reasons: [RecommendationReason], score: Int) -> Confidence {
        let hasValidated = reasons.contains {
            if case .validatedStack = $0 { return true }
            return false
        }
        if hasValidated { return .high }

        let signalCount = reasons.count
        if signalCount >= 4 || score >= 8 { return .high }
        if signalCount >= 2 { return .medium }
        return .low
    }

    // MARK: - Half-Life Parsing

    /// Parses a human-readable half-life string into approximate hours.
    /// Returns nil for unknown/unparseable values.
    static func parseHalfLifeHours(_ halfLife: String) -> Double? {
        let lower = halfLife.lowercased()
        if lower.contains("unknown") || lower.isEmpty { return nil }

        // Extract numeric value
        let pattern = #"(\d+\.?\d*)\s*[-–]?\s*(\d+\.?\d*)?\s*(min|hour|hr|h|day|d|week|wk)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) else {
            return nil
        }

        let firstNumStr = String(lower[Range(match.range(at: 1), in: lower)!])
        let firstNum = Double(firstNumStr) ?? 0

        var value = firstNum
        if let secondRange = Range(match.range(at: 2), in: lower),
           let secondNum = Double(String(lower[secondRange])) {
            value = (firstNum + secondNum) / 2.0
        }

        let unitRange = Range(match.range(at: 3), in: lower)!
        let unit = String(lower[unitRange])

        switch unit {
        case "min": return value / 60.0
        case "hour", "hr", "h": return value
        case "day", "d": return value * 24.0
        case "week", "wk": return value * 168.0
        default: return nil
        }
    }
}
