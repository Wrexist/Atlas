import AppIntents

/// "Log [N] ounces of water" / "Log a glass of water".
///
/// Optional `ounces` parameter — when omitted, defaults to 8 oz
/// (one standard glass), which is what the most common voice
/// invocations actually mean. Power users wiring this into
/// Shortcuts can drop in any int.
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log water"

    static let description = IntentDescription(
        "Adds water to today's nutrition log. Defaults to 8 ounces (one glass) when no amount is given.",
        categoryName: "Nutrition"
    )

    static let openAppWhenRun: Bool = false

    /// Default of 8 matches the standard "glass of water" mental
    /// model. The lower bound is 1 so a Shortcut input can't sneak
    /// in a negative or zero value; upper bound at 256 oz (≈ 2
    /// gallons) is a sanity check against fat-fingered input.
    @Parameter(
        title: "Ounces",
        description: "How much water to log, in fluid ounces.",
        default: 8,
        inclusiveRange: (1, 256)
    )
    var ounces: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let amount = ounces
        let totalAfterLog: Int = await MainActor.run {
            let store = IntentDataStore.resolve()
            store.logWater(oz: amount)
            store.flushPendingSave()
            return store.consumption().waterOz
        }

        return .result(dialog: IntentDialog(
            LocalizedStringResource(
                "Logged \(amount) oz. \(totalAfterLog) oz total today.",
                comment: "Siri confirmation after logging water. First int: amount just added, second: new running total."
            )
        ))
    }
}
