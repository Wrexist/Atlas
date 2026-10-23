import AppIntents

/// "Log [N] ounces of water" / "Log a glass of water".
///
/// Optional `millilitres` or `ounces` parameter — when both are omitted,
/// logs one glass in the user's unit (8 oz, or 250 mL for metric), the
/// same glass the Control Center button logs. Power users wiring this
/// into Shortcuts can drop in a whole number of either unit.
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

    /// Metric counterpart to `ounces`, kept separate so existing
    /// Shortcuts that pass ounces keep working. 7 500 mL ≈ 256 oz.
    @Parameter(
        title: "Milliliters",
        description: "How much water to log, in milliliters. Used instead of ounces when both are set.",
        inclusiveRange: (1, 7500)
    )
    var millilitres: Int?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ounces = self.ounces, millilitres = self.millilitres
        let (added, total): (String, String) = await MainActor.run {
            let store = IntentDataStore.resolve()
            let unit = store.profile.bodyMetrics.unit
            let fluidOunces = Self.fluidOunces(ounces: ounces, millilitres: millilitres, unit: unit)
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

    /// The amount to log: millilitres when given, else ounces, else one
    /// glass in the user's unit.
    static func fluidOunces(ounces: Int?, millilitres: Int?, unit: MeasurementUnit) -> Double {
        if let millilitres { return LifestyleDataLogic.fluidOunces(millilitres: Double(millilitres)) }
        return ounces.map(Double.init) ?? TodayChecklistEngine.glassFluidOunces(for: unit)
    }
}
