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
        guard aggregate.compliance.total > 0 else { return dosesFreeOpener(for: aggregate) }

        let pct = Int((aggregate.compliance.pct * 100).rounded())
        let completed = aggregate.compliance.completed
        let total = aggregate.compliance.total

        if pct >= 90 {
            return String(localized: "Strong week — \(completed) of \(total) doses logged (\(pct)% compliance).")
        }
        if pct >= 70 {
            return String(localized: "Solid week — \(completed) of \(total) doses logged (\(pct)% compliance).")
        }
        if pct >= 40 {
            return String(localized: "Mixed week — \(completed) of \(total) doses logged (\(pct)%).")
        }
        return String(localized: "Quiet week — \(completed) of \(total) doses logged (\(pct)%).")
    }

    /// For a week with nothing scheduled — a training- or nutrition-only
    /// user — so the summary never leads with "0 of 0 doses".
    private static func dosesFreeOpener(for aggregate: WeeklyAggregate) -> String {
        if let outcomes = aggregate.outcomes, outcomes.checkInsCount > 0 {
                return String(localized: "Your week in review — \(outcomes.checkInsCount) daily check-ins logged.")
        }
        if let nutrition = aggregate.nutrition, nutrition.mealLoggingDays > 0 {
            return String(localized: "Your week in review — meals logged on \(nutrition.mealLoggingDays) of 7 days.")
        }
        return String(localized: "Your week in review.")
    }

    // MARK: - Observations

    private static func buildObservations(from aggregate: WeeklyAggregate) -> [String] {
        var observations: [String] = []

        if aggregate.streak.current >= 7 {
            observations.append(
                String(localized: "You're on a \(aggregate.streak.current)-day streak — your best is \(aggregate.streak.best).")
            )
        } else if aggregate.streak.current >= 3 {
            observations.append(String(localized: "Current streak: \(aggregate.streak.current) days."))
        }

        if let outcomes = aggregate.outcomes {
            let composite = (
                outcomes.energyAvg + outcomes.sleepAvg + outcomes.recoveryAvg
                + outcomes.moodAvg + outcomes.focusAvg
            ) / 5.0
            let compStr = String(format: "%.1f", composite)
            if outcomes.compositeDelta > 0.2 {
                observations.append(
                    String(localized: "Daily check-ins averaged \(compStr) of 5 — up from last week.")
                )
            } else if outcomes.compositeDelta < -0.2 {
                observations.append(
                    String(localized: "Daily check-ins averaged \(compStr) of 5 — down from last week.")
                )
            } else {
                observations.append(String(localized: "Daily check-ins averaged \(compStr) of 5."))
            }
        }

        if let nutrition = aggregate.nutrition {
            let onTarget = abs(nutrition.avgCalories - nutrition.targetCalories) <= 150
            if onTarget {
                observations.append(
                    String(localized: "Nutrition stayed on target — \(nutrition.avgCalories) kcal average across \(nutrition.mealLoggingDays) days.")
                )
            } else if nutrition.avgCalories < nutrition.targetCalories {
                observations.append(
                    String(localized: "Nutrition trended under target at \(nutrition.avgCalories) kcal/day.")
                )
            } else {
                observations.append(
                    String(localized: "Nutrition trended over target at \(nutrition.avgCalories) kcal/day.")
                )
            }
        }

        if let bio = aggregate.biometrics, let delta = bio.hrvDelta, abs(delta) >= 3 {
            if delta > 0 {
                observations.append(String(localized: "HRV moved up \(delta) ms vs last week."))
            } else {
                observations.append(String(localized: "HRV moved down \(abs(delta)) ms vs last week."))
            }
        }

        if let training = aggregate.training {
            let dayWord = training.sessionDays == 1 ? "day" : "days"
            observations.append("Trained on \(training.sessionDays) \(dayWord) this week.")
        }

        if aggregate.labs.newPanelsLogged > 0 {
            let panels = aggregate.labs.newPanelsLogged
            observations.append(String(localized: "Logged \(panels) new lab panels this week."))
        }

        return observations
    }

    // MARK: - Closer

    private static func closer(for aggregate: WeeklyAggregate) -> String {
        guard aggregate.compliance.total > 0 else {
            return String(localized: "Keep logging next week — every day of data sharpens the picture.")
        }
        let pct = aggregate.compliance.pct

        if pct >= 0.9 {
            return String(localized: "Keep the cadence steady next week — consistency at this level compounds.")
        }
        if pct >= 0.7 {
            return String(localized: "Aim to tighten one missed dose next week — small gains add up.")
        }
        if pct >= 0.4 {
            return String(localized: "Pick one consistent time block next week and protect it.")
        }
        return String(localized: "Start with one dose tomorrow. Streaks rebuild faster than they look.")
    }
}
