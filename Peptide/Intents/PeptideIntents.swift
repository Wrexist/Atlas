import AppIntents
import Foundation

// Atlas's App Intents surface. Each intent owns its own
// presentation logic; the entity types (`PeptideEntity`,
// `FoodEntity`) and the data-access helper (`IntentDataStore`)
// live in sibling files so multiple intents can share them.
//
// Naming convention:
//   • `Show...Intent` = read-only, returns a Siri dialog (+ value
//     for the Shortcuts pipeline when useful)
//   • `Log...Intent`  = side-effecting, hops to MainActor through
//     `IntentDataStore` and force-flushes the save before
//     returning so the change is durable.

// MARK: - Next Dose

struct NextDoseIntent: AppIntent {
    static let title: LocalizedStringResource = "Show next dose"
    static let description = IntentDescription(
        "Tells you the next scheduled peptide dose for today.",
        categoryName: "Doses"
    )
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot: NextDoseReadout = await MainActor.run {
            let store = IntentDataStore.resolve()
            guard let next = store.nextDose else { return .allDone }
            return .upcoming(name: next.peptide.name, dose: next.dose, date: next.date)
        }

        switch snapshot {
        case .allDone:
            return .result(dialog: IntentDialog(
                LocalizedStringResource(
                    "You've logged everything for today. Nice work.",
                    comment: "Siri response when no doses remain today."
                )
            ))
        case .upcoming(let name, let dose, let date):
            let time = date.formatted(date: .omitted, time: .shortened)
            let relative = Self.relativePhrase(for: date)
            return .result(dialog: IntentDialog(
                LocalizedStringResource(
                    "Next up: \(name), \(dose), at \(time). \(relative).",
                    comment: "Siri readout of the next scheduled dose."
                )
            ))
        }
    }

    private static func relativePhrase(for date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if abs(interval) < 60 {
            return String(localized: "Now")
        }
        if interval < 0 {
            return String(localized: "Earlier today")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private enum NextDoseReadout {
        case allDone
        case upcoming(name: String, dose: String, date: Date)
    }
}

// MARK: - Compliance

struct ComplianceIntent: AppIntent {
    static let title: LocalizedStringResource = "Show compliance"
    static let description = IntentDescription(
        "Reads back your 7-day peptide compliance.",
        categoryName: "Doses"
    )
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let snapshot: ComplianceReadout = await MainActor.run {
            let store = IntentDataStore.resolve()
            let fraction = EntryAnalytics.weeklyComplianceFraction(in: store.entries)
            return ComplianceReadout(
                percent: Int((fraction * 100).rounded()),
                hasData: !store.entries.isEmpty
            )
        }

        guard snapshot.hasData else {
            return .result(value: 0, dialog: IntentDialog(
                LocalizedStringResource(
                    "No recent data. Start logging doses in Atlas.",
                    comment: "Siri response when there are no entries yet."
                )
            ))
        }
        return .result(value: snapshot.percent, dialog: IntentDialog(
            LocalizedStringResource(
                "Your 7-day compliance is \(snapshot.percent) percent. Keep it up.",
                comment: "Siri readout — weekly compliance percentage."
            )
        ))
    }

    private struct ComplianceReadout {
        let percent: Int
        let hasData: Bool
    }
}

// MARK: - Log Dose

/// "Log my [peptide] dose" — primary voice / Action Button surface.
///
/// Marks today's first incomplete dose of the chosen peptide as
/// complete, mirroring the in-app tap on a `DoseRowView` checkmark.
/// Earliest-incomplete picking lets a user with morning + evening
/// doses say "log my BPC-157" twice and hit both without
/// disambiguation.
struct LogDoseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log peptide dose"
    static let description = IntentDescription(
        "Marks the next scheduled dose of a peptide as completed.",
        categoryName: "Doses"
    )
    static let openAppWhenRun: Bool = false

    @Parameter(
        title: "Peptide",
        description: "Which peptide to log a dose for.",
        requestValueDialog: IntentDialog("Which peptide?")
    )
    var peptide: PeptideEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let chosenID = peptide.id
        let chosenName = peptide.displayName

        let resolution: ToggleResolution = await MainActor.run {
            let store = IntentDataStore.resolve()
            let candidate = store.todayEntries
                .sorted { $0.date < $1.date }
                .first { !$0.completed && $0.peptide.id.uuidString == chosenID }
            guard let entry = candidate else { return .nothingToLog }
            store.toggleEntry(entry.id)
            store.flushPendingSave()
            return .logged(at: entry.date, dose: entry.dose)
        }

        switch resolution {
        case .nothingToLog:
            return .result(dialog: IntentDialog(
                LocalizedStringResource(
                    "No more \(chosenName) doses scheduled for today.",
                    comment: "Siri response when no doses remain."
                )
            ))
        case .logged(let date, let dose):
            let time = date.formatted(date: .omitted, time: .shortened)
            return .result(dialog: IntentDialog(
                LocalizedStringResource(
                    "Logged \(chosenName) \(dose) at \(time).",
                    comment: "Siri confirmation after marking a dose complete."
                )
            ))
        }
    }

    private enum ToggleResolution {
        case logged(at: Date, dose: String)
        case nothingToLog
    }
}

// MARK: - Today Macros

struct TodayMacrosIntent: AppIntent {
    static let title: LocalizedStringResource = "Show today's nutrition"
    static let description = IntentDescription(
        "Reads back today's calories, protein, carbs, and fat against your targets.",
        categoryName: "Nutrition"
    )
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let snapshot: MacrosReadout = await MainActor.run {
            let store = IntentDataStore.resolve()
            let consumed = store.consumption()
            let targets = store.profile.nutritionTargets
            return MacrosReadout(
                calories: consumed.caloriesKcal,
                calorieTarget: targets?.calories ?? 0,
                protein: consumed.proteinG,
                carbs: consumed.carbsG,
                fat: consumed.fatG
            )
        }

        let dialog: IntentDialog
        if snapshot.calorieTarget > 0 {
            let remaining = max(0, snapshot.calorieTarget - snapshot.calories)
            dialog = IntentDialog(
                LocalizedStringResource(
                    "\(snapshot.calories) of \(snapshot.calorieTarget) calories. \(remaining) remaining. \(snapshot.protein) grams protein, \(snapshot.carbs) grams carbs, \(snapshot.fat) grams fat.",
                    comment: "Siri readout — calorie totals against target plus macro line."
                )
            )
        } else {
            dialog = IntentDialog(
                LocalizedStringResource(
                    "\(snapshot.calories) calories so far. \(snapshot.protein) grams protein, \(snapshot.carbs) grams carbs, \(snapshot.fat) grams fat.",
                    comment: "Siri readout when no calorie target is set."
                )
            )
        }
        return .result(value: snapshot.calories, dialog: dialog)
    }

    private struct MacrosReadout {
        let calories: Int
        let calorieTarget: Int
        let protein: Int
        let carbs: Int
        let fat: Int
    }
}

// MARK: - App Shortcuts Provider

/// Registers every intent with the system. Apple permits a single
/// `AppShortcutsProvider` per app target; collapsing the
/// dose-shortcuts + nutrition-shortcuts surfaces here keeps that
/// constraint satisfied while letting both sets share the same
/// pleasant invocation phrases.
struct PeptideShortcuts: AppShortcutsProvider {

    static let shortcutTileColor: ShortcutTileColor = .lightBlue

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogDoseIntent(),
            phrases: [
                "Log a \(.applicationName) dose",
                "Log my dose in \(.applicationName)",
                "Mark my peptide complete in \(.applicationName)",
            ],
            shortTitle: "Log Dose",
            systemImageName: "syringe.fill"
        )
        AppShortcut(
            intent: NextDoseIntent(),
            phrases: [
                "What's my next \(.applicationName) dose",
                "Next dose in \(.applicationName)",
                "When is my next peptide in \(.applicationName)",
            ],
            shortTitle: "Next Dose",
            systemImageName: "clock.badge.fill"
        )
        AppShortcut(
            intent: ComplianceIntent(),
            phrases: [
                "How's my compliance in \(.applicationName)",
                "Check my \(.applicationName) compliance",
                "Show \(.applicationName) stats",
            ],
            shortTitle: "Compliance",
            systemImageName: "chart.bar.fill"
        )
        AppShortcut(
            intent: ShowStreakIntent(),
            phrases: [
                "Show my \(.applicationName) streak",
                "What's my streak in \(.applicationName)",
            ],
            shortTitle: "Streaks",
            systemImageName: "flame.fill"
        )
        AppShortcut(
            intent: LogWaterIntent(),
            phrases: [
                "Log water in \(.applicationName)",
                "Add water in \(.applicationName)",
                "Log a glass of water in \(.applicationName)",
            ],
            shortTitle: "Log Water",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: TodayMacrosIntent(),
            phrases: [
                "Show my calories in \(.applicationName)",
                "How many calories in \(.applicationName)",
                "Today's nutrition in \(.applicationName)",
            ],
            shortTitle: "Today's Nutrition",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: LogMealIntent(),
            phrases: [
                "Log a meal in \(.applicationName)",
                "Log my food in \(.applicationName)",
            ],
            shortTitle: "Log Meal",
            systemImageName: "fork.knife.circle.fill"
        )
        AppShortcut(
            intent: LogRecipeIntent(),
            phrases: [
                "Log a \(.applicationName) recipe",
                "Log my recipe in \(.applicationName)",
            ],
            shortTitle: "Log Recipe",
            systemImageName: "list.bullet.rectangle.fill"
        )
    }
}
