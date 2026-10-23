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
                tracksDoses: !store.protocols.isEmpty,
                doseStreak: store.currentStreak,
                doseBest: store.bestStreak,
                mealStreak: store.mealLoggingStreak,
                mealBest: store.bestMealLoggingStreak
            )
        }

        return .result(dialog: IntentDialog(Self.readout(snapshot)))
    }

    /// Composes the dose and meal lines independently so a user who has
    /// never logged a meal hears a sensible response instead of "0 day
    /// meal streak", and one who has never set up a protocol, which is
    /// optional, hears nothing about doses.
    static func readout(_ s: Snapshot) -> LocalizedStringResource {
        let lines = [doseLine(s), mealLine(s)].compactMap { $0 }
        switch lines.count {
        case 2:
            return LocalizedStringResource(
                "\(String(localized: lines[0])) \(String(localized: lines[1]))",
                comment: "Concatenated dose + meal streak readout for Siri."
            )
        case 1:
            return lines[0]
        default:
            return LocalizedStringResource(
                "No active streaks yet.",
                comment: "Siri readout when there is neither a dose nor a meal streak to report."
            )
        }
    }

    private static func doseLine(_ s: Snapshot) -> LocalizedStringResource? {
        guard s.tracksDoses else { return nil }
        if s.doseStreak > 0 {
            return LocalizedStringResource(
                "\(s.doseStreak) day dose streak.",
                comment: "Siri readout when the dose streak is active."
            )
        }
        if s.doseBest > 0 {
            return LocalizedStringResource(
                "Dose streak paused, best was \(s.doseBest) days.",
                comment: "Siri readout when the dose streak has lapsed but a best exists."
            )
        }
        return LocalizedStringResource(
            "No active dose streak.",
            comment: "Siri readout when the dose streak has lapsed."
        )
    }

    private static func mealLine(_ s: Snapshot) -> LocalizedStringResource? {
        if s.mealStreak > 0 {
            return LocalizedStringResource(
                "\(s.mealStreak) day meal streak.",
                comment: "Siri readout when the meal streak is active."
            )
        }
        guard s.mealBest > 0 else { return nil }
        return LocalizedStringResource(
            "Meal streak paused, best was \(s.mealBest) days.",
            comment: "Siri readout when the meal streak has lapsed but a best exists."
        )
    }

    struct Snapshot {
        /// False for a user with no protocols, current or past.
        let tracksDoses: Bool
        let doseStreak: Int
        let doseBest: Int
        let mealStreak: Int
        let mealBest: Int
    }
}
