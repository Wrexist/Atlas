import Foundation

/// Deterministic template-based summary the iOS client falls back
/// to when the AI proxy is unreachable. Produces 2-3 paragraphs
/// from the same `WeeklyAggregate` the network call would send,
/// so the card layout reads identically whether the AI summary
/// landed or not — the only signal that this is the fallback is
/// the `kind: .offline` marker the UI surfaces as a small chip.
///
/// Kept template-based (not natural-language varied) on purpose —
/// the user already has fallback messaging; adding randomness here
/// would just make "did the AI run?" harder to debug.
enum OfflineWeeklySummaryFormatter {

    static func summary(from aggregate: WeeklyAggregate) -> String {
        var paragraphs: [String] = []

        paragraphs.append(opener(for: aggregate))

        let observations = buildObservations(from: aggregate)
        if !observations.isEmpty {
            paragraphs.append(observations.joined(separator: " "))
        }

        paragraphs.append(closer(for: aggregate))

        return paragraphs.joined(separator: "\n\n")
    }

    // MARK: - Opener

    private static func opener(for aggregate: WeeklyAggregate) -> String {
        let pct = Int((aggregate.compliance.pct * 100).rounded())
        let completed = aggregate.compliance.completed
        let total = aggregate.compliance.total

        if pct >= 90 {
            return "Strong week — \(completed) of \(total) doses logged (\(pct)% compliance)."
        }
        if pct >= 70 {
            return "Solid week — \(completed) of \(total) doses logged (\(pct)% compliance)."
        }
        if pct >= 40 {
            return "Mixed week — \(completed) of \(total) doses logged (\(pct)%)."
        }
        return "Quiet week — \(completed) of \(total) doses logged (\(pct)%)."
    }

    // MARK: - Observations

    private static func buildObservations(from aggregate: WeeklyAggregate) -> [String] {
        var observations: [String] = []

        if aggregate.streak.current >= 7 {
            observations.append(
                "You're on a \(aggregate.streak.current)-day streak — your best is \(aggregate.streak.best)."
            )
        } else if aggregate.streak.current >= 3 {
            observations.append("Current streak: \(aggregate.streak.current) days.")
        }

        if let outcomes = aggregate.outcomes {
            let composite = (
                outcomes.energyAvg + outcomes.sleepAvg + outcomes.recoveryAvg
                + outcomes.moodAvg + outcomes.focusAvg
            ) / 5.0
            let compStr = String(format: "%.1f", composite)
            if outcomes.compositeDelta > 0.2 {
                observations.append(
                    "Daily check-ins averaged \(compStr) of 5 — up from last week."
                )
            } else if outcomes.compositeDelta < -0.2 {
                observations.append(
                    "Daily check-ins averaged \(compStr) of 5 — down from last week."
                )
            } else {
                observations.append("Daily check-ins averaged \(compStr) of 5.")
            }
        }

        if let nutrition = aggregate.nutrition {
            let onTarget = abs(nutrition.avgCalories - nutrition.targetCalories) <= 150
            if onTarget {
                observations.append(
                    "Nutrition stayed on target — \(nutrition.avgCalories) kcal average across \(nutrition.mealLoggingDays) days."
                )
            } else if nutrition.avgCalories < nutrition.targetCalories {
                observations.append(
                    "Nutrition trended under target at \(nutrition.avgCalories) kcal/day."
                )
            } else {
                observations.append(
                    "Nutrition trended over target at \(nutrition.avgCalories) kcal/day."
                )
            }
        }

        if let bio = aggregate.biometrics, let delta = bio.hrvDelta, abs(delta) >= 3 {
            if delta > 0 {
                observations.append("HRV moved up \(delta) ms vs last week.")
            } else {
                observations.append("HRV moved down \(abs(delta)) ms vs last week.")
            }
        }

        if aggregate.labs.newPanelsLogged > 0 {
            let panels = aggregate.labs.newPanelsLogged
            let panelWord = panels == 1 ? "panel" : "panels"
            observations.append("Logged \(panels) new lab \(panelWord) this week.")
        }

        return observations
    }

    // MARK: - Closer

    private static func closer(for aggregate: WeeklyAggregate) -> String {
        let pct = aggregate.compliance.pct

        if pct >= 0.9 {
            return "Keep the cadence steady next week — consistency at this level compounds."
        }
        if pct >= 0.7 {
            return "Aim to tighten one missed dose next week — small gains add up."
        }
        if pct >= 0.4 {
            return "Pick one consistent time block next week and protect it."
        }
        return "Start with one dose tomorrow. Streaks rebuild faster than they look."
    }
}
