import AppIntents

/// "Log [N] ounces of water" / "Log a glass of water".
///
/// Optional `ounces` parameter — when omitted, logs one glass in the
/// user's unit (8 oz, or 250 mL for metric), the same glass the Control
/// Center button logs. Power users wiring this into Shortcuts can drop
/// in any whole number of ounces.
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log water"

    static let description = IntentDescription(
        "Adds water to today's nutrition log. Logs one glass when no amount is given.",
        categoryName: "Nutrition"
    )

    static let openAppWhenRun: Bool = false

    /// The lower bound is 1 so a Shortcut input can't sneak in a
    /// negative or zero value; upper bound at 256 oz (≈ 2 gallons) is
    /// a sanity check against fat-fingered input.
    @Parameter(
        title: "Ounces",
        description: "How much water to log, in fluid ounces. Leave empty for one glass.",
        inclusiveRange: (1, 256)
    )
    var ounces: Int?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let amount = ounces
        let (added, total): (String, String) = await MainActor.run {
            let store = IntentDataStore.resolve()
            let unit = store.profile.bodyMetrics.unit
            let fluidOunces = amount.map(Double.init) ?? TodayChecklistEngine.glassFluidOunces(for: unit)
            store.logWater(fluidOunces: fluidOunces)
            store.flushPendingSave()
            let totalValue = LifestyleDataLogic.displayedWater(store.consumption(), unit: unit)
            return unit == .metric
                ? ("\(LifestyleDataLogic.millilitres(fluidOunces: fluidOunces)) mL", "\(totalValue) mL")
                : ("\(Int(fluidOunces.rounded())) oz", "\(totalValue) oz")
        }

        return .result(dialog: IntentDialog(
            LocalizedStringResource(
                "Logged \(added). \(total) total today.",
                comment: "Siri confirmation after logging water. First value: amount just added, second: new running total, each with its unit."
            )
        ))
    }
}
