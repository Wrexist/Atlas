import AppIntents

/// "How's my streak?" — reads both the dose-logging and the meal-
/// logging streaks back to the user. Two separate counts (peptides
/// and food) because they answer different questions, but a single
/// intent because users ask the question once and want both.
struct ShowStreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Show streaks"

    static let description = IntentDescription(
        "Reads back your current dose-logging and meal-logging streaks.",
        categoryName: "Progress"
    )

    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot: Snapshot = await MainActor.run {
            let store = IntentDataStore.resolve()
            return Snapshot(
                doseStreak: store.currentStreak,
                tracksProtocols: !store.activeProtocols.isEmpty,
                mealStreak: store.mealLoggingStreak,
                mealBest: store.bestMealLoggingStreak
            )
        }

        return .result(dialog: IntentDialog(Self.readout(snapshot)))
    }

    /// Composes the dose and meal lines independently, so a user who has
    /// never logged a meal doesn't hear "0 day meal streak" and a user with
    /// no protocol doesn't hear about doses at all.
    static func readout(_ s: Snapshot) -> LocalizedStringResource {
        let doseLine: LocalizedStringResource? = s.doseStreak > 0
            ? LocalizedStringResource(
                "\(s.doseStreak) day dose streak.",
                comment: "Siri readout when the dose streak is active."
            )
            : (s.tracksProtocols
                ? LocalizedStringResource(
                    "No active dose streak.",
                    comment: "Siri readout when the dose streak has lapsed."
                )
                : nil)

        let mealLine: LocalizedStringResource? = s.mealStreak > 0
            ? LocalizedStringResource(
                "\(s.mealStreak) day meal streak.",
                comment: "Siri readout when the meal streak is active."
            )
            : (s.mealBest > 0
                ? LocalizedStringResource(
                    "Meal streak paused, best was \(s.mealBest) days.",
                    comment: "Siri readout when the meal streak has lapsed but a best exists."
                )
                : nil)

        switch (doseLine, mealLine) {
        case let (dose?, meal?):
            return LocalizedStringResource(
                "\(String(localized: dose)) \(String(localized: meal))",
                comment: "Concatenated dose + meal streak readout for Siri."
            )
        case let (dose?, nil):
            return dose
        case let (nil, meal?):
            return meal
        case (nil, nil):
            return LocalizedStringResource(
                "No streak yet. Log a meal today to start one.",
                comment: "Siri readout when there is no dose or meal streak to report."
            )
        }
    }

    struct Snapshot {
        let doseStreak: Int
        let tracksProtocols: Bool
        let mealStreak: Int
        let mealBest: Int
    }
}
