import AppIntents
import Foundation

/// "Log my weight" — records today's weigh-in without opening the app.
///
/// The number is read in the user's unit (kg or lb, as set in Atlas) and
/// saved through `DataStore.logWeight`, the same path as the weight sheet
/// and the weigh-in reminder's reply: one entry per day, mirrored to
/// Apple Health when Health sync is on.
struct LogWeightIntent: AppIntent {
    static let title: LocalizedStringResource = "Log weight"

    static let description = IntentDescription(
        "Logs today's body weight in the unit you use in Atlas.",
        categoryName: "Body"
    )

    static let openAppWhenRun: Bool = false

    @Parameter(
        title: "Weight",
        description: "Today's weight, in kilograms or pounds as set in Atlas.",
        requestValueDialog: IntentDialog("What's your weight?")
    )
    var weight: Double

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = IntentDataStore.resolve()
        let unit = store.profile.bodyMetrics.unit
        guard let kilograms = Self.kilograms(weight, unit: unit) else {
            let range = DailyReminderEngine.plausibleWeightKilograms
            let low = unit.weightLabel(range.lowerBound)
            let high = unit.weightLabel(range.upperBound)
            return .result(dialog: IntentDialog(
                LocalizedStringResource(
                    "Enter a weight between \(low) and \(high).",
                    comment: "Shown when a typed or spoken weight is outside the plausible range."
                )
            ))
        }

        store.logWeight(kg: kilograms)
        store.flushPendingSave()
        // Today's weigh-in reminder has nothing left to ask for.
        await DailyReminderScheduler.reconcile(dataStore: store)

        let logged = unit.weightLabel(kilograms, fractionDigits: 1)
        return .result(dialog: IntentDialog(
            LocalizedStringResource(
                "Logged \(logged).",
                comment: "Siri confirmation after logging a body weight, e.g. “Logged 82.4 kg.”"
            )
        ))
    }

    /// The spoken number in the user's unit → canonical kilograms, or nil
    /// when it's outside the range the weight sheet accepts, so a misheard
    /// "8.24" never lands in the history.
    static func kilograms(_ value: Double, unit: MeasurementUnit) -> Double? {
        let kilograms = unit.kilograms(fromDisplayed: value)
        guard DailyReminderEngine.plausibleWeightKilograms.contains(kilograms) else { return nil }
        return kilograms
    }
}
