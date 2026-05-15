import AppIntents

/// "How's my streak?" — reads both the dose-logging and the meal-
/// logging streaks back to the user. Two separate counts (peptides
/// and food) because they answer different questions, but a single
/// intent because users ask the question once and want both.
struct ShowStreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Show streaks"

    static let description = IntentDescription(
        "Reads back your current dose-logging and meal-logging streaks.",
        categoryName: "Doses"
    )

    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot: Snapshot = await MainActor.run {
            let store = IntentDataStore.resolve()
            return Snapshot(
                doseStreak: store.currentStreak,
                doseBest: store.bestStreak,
                mealStreak: store.mealLoggingStreak,
                mealBest: store.bestMealLoggingStreak
            )
        }

        return .result(dialog: IntentDialog(makeReadout(snapshot)))
    }

    private func makeReadout(_ s: Snapshot) -> LocalizedStringResource {
        // Compose the dose + meal lines independently so a user
        // who's never logged a meal hears a sensible response
        // instead of "0 day meal streak".
        let doseLine: LocalizedStringResource = s.doseStreak > 0
            ? LocalizedStringResource(
                "\(s.doseStreak) day dose streak.",
                comment: "Siri readout when the dose streak is active."
            )
            : LocalizedStringResource(
                "No active dose streak.",
                comment: "Siri readout when the dose streak has lapsed."
            )

        let mealLine: LocalizedStringResource? = s.mealStreak > 0
            ? LocalizedStringResource(
                "\(s.mealStreak) day meal streak.",
                comment: "Siri readout when the meal streak is active."
            )
            : (s.mealBest > 0
                ? LocalizedStringResource(
                    "Meal streak paused, best was \(s.mealBest).",
                    comment: "Siri readout when the meal streak has lapsed but a best exists."
                )
                : nil)

        if let mealLine {
            return LocalizedStringResource(
                "\(String(localized: doseLine)) \(String(localized: mealLine))",
                comment: "Concatenated dose + meal streak readout for Siri."
            )
        }
        return doseLine
    }

    private struct Snapshot {
        let doseStreak: Int
        let doseBest: Int
        let mealStreak: Int
        let mealBest: Int
    }
}
