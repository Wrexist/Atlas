import AppIntents

/// "Log [N] of water" / "Log a glass of water".
///
/// Optional `amount` parameter in the user's own unit: millilitres for
/// metric, fluid ounces for imperial. A metric user who says 250 means
/// 250 mL, not 250 oz (7.4 L). When omitted, logs one glass (8 oz, or
/// 250 mL for metric), the same glass the Control Center button logs.
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log water"

    static let description = IntentDescription(
        "Adds water to today's nutrition log. Logs one glass when no amount is given.",
        categoryName: "Nutrition"
    )

    static let openAppWhenRun: Bool = false

    /// The lower bound is 1 so a Shortcut input can't sneak in a
    /// negative or zero value. The upper bound fits the metric range;
    /// `fluidOunces(amount:unit:)` caps each unit at about two gallons
    /// as a check against fat-fingered input.
    @Parameter(
        title: "Amount",
        description: "How much water to log, in millilitres or fluid ounces to match your unit setting. Leave empty for one glass.",
        inclusiveRange: (1, 8000)
    )
    var amount: Int?

    /// `amount` read in the user's unit, as the fluid ounces the log stores.
    static func fluidOunces(amount: Int?, unit: MeasurementUnit) -> Double {
        guard let amount else { return TodayChecklistEngine.glassFluidOunces(for: unit) }
        switch unit {
        case .metric:
            return LifestyleDataLogic.fluidOunces(millilitres: Double(min(amount, 8000)))
        case .imperial:
            return Double(min(amount, 256))
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let requested = amount
        let (added, total): (String, String) = await MainActor.run {
            let store = IntentDataStore.resolve()
            let unit = store.profile.bodyMetrics.unit
            let fluidOunces = Self.fluidOunces(amount: requested, unit: unit)
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
