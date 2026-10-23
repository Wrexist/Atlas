import SwiftUI

/// Fourth page: calories and protein as a two-ring stack with today's
/// calories rolling up inside, protein and streak beneath, and one-tap
/// water logging whose drop bounces on each pour.
struct NutritionPage: View {
    @EnvironmentObject private var store: WatchStore
    let nutrition: WatchNutritionSnapshot
    /// Taps per water button, keyed by option, so only the tapped
    /// button's drop bounces.
    @State private var pours: [String: Int] = [:]
    @ScaledMetric(relativeTo: .largeTitle) private var calorieSize: CGFloat = 24

    /// Water is stored in fluid ounces, so the labels follow the phone's
    /// unit setting or the two surfaces disagree about the same number.
    /// Read through `WatchWeightUnit` so a missing unit means metric here
    /// too, never oz water beside kg weights.
    private var isMetric: Bool { !WatchWeightUnit(store.watchData.measurementUnit).isImperial }

    /// Metric amounts are sent as exact fractional ounces, so +250mL
    /// logs 250 mL on the phone rather than a rounded 8 oz (237 mL).
    private struct WaterOption: Identifiable {
        let label: String
        let spoken: String
        let fluidOunces: Double
        var id: String { label }
    }

    private var waterOptions: [WaterOption] {
        isMetric
            ? [.init(label: "+250 mL", spoken: String(localized: "Log 250 milliliters of water"), fluidOunces: Self.fluidOunces(milliliters: 250)),
               .init(label: "+500 mL", spoken: String(localized: "Log 500 milliliters of water"), fluidOunces: Self.fluidOunces(milliliters: 500)),
               .init(label: "+1 L", spoken: String(localized: "Log 1 liter of water"), fluidOunces: Self.fluidOunces(milliliters: 1000))]
            : [.init(label: "+8 oz", spoken: String(localized: "Log 8 ounces of water"), fluidOunces: 8),
               .init(label: "+16 oz", spoken: String(localized: "Log 16 ounces of water"), fluidOunces: 16),
               .init(label: "+32 oz", spoken: String(localized: "Log 32 ounces of water"), fluidOunces: 32)]
    }

    private static func fluidOunces(milliliters: Double) -> Double {
        Measurement(value: milliliters, unit: UnitVolume.milliliters).converted(to: .fluidOunces).value
    }

    /// Ring geometry. The calorie figure sits inside the protein ring's
    /// hole, sized from these so it can never reach a ring.
    private let ringSize: CGFloat = 124
    private let ringWidth: CGFloat = 11
    private let ringGap: CGFloat = 3
    private var holeDiameter: CGFloat { ringSize - 2 * (2 * ringWidth + ringGap) }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                rings
                summary
                    .entrance(0)
                water
                    .entrance(1)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Nutrition")
        .pageBackground(WatchPalette.calories)
    }

    private var rings: some View {
        ZStack {
            ActivityRings(rings: [
                RingSpec(id: "calories", progress: nutrition.calorieProgress,
                         color: WatchPalette.calories, symbol: "flame.fill"),
                RingSpec(id: "protein", progress: nutrition.proteinProgress,
                         color: WatchPalette.protein, symbol: "bolt.fill"),
            ], lineWidth: ringWidth, spacing: ringGap)
            VStack(spacing: -1) {
                RollingNumber(value: nutrition.caloriesToday)
                    .font(.system(size: calorieSize, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("KCAL")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(WatchPalette.calories)
            }
            .frame(width: holeDiameter * 0.78)
        }
        .frame(width: ringSize, height: ringSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caloriesSpoken)
    }

    private var caloriesSpoken: String {
        nutrition.calorieTarget > 0
            ? String(localized: "\(nutrition.caloriesToday) of \(nutrition.calorieTarget) calories")
            : String(localized: "\(nutrition.caloriesToday) calories")
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 4) {
            StatColumn(
                value: nutrition.proteinTarget > 0
                    ? "\(nutrition.proteinToday)/\(nutrition.proteinTarget)g"
                    : "\(nutrition.proteinToday)g",
                label: String(localized: "Protein"),
                color: WatchPalette.protein,
                spoken: nutrition.proteinTarget > 0
                    ? String(localized: "Protein \(nutrition.proteinToday) of \(nutrition.proteinTarget) grams")
                    : String(localized: "Protein \(nutrition.proteinToday) grams")
            )
            StatColumn(
                value: String(localized: "\(nutrition.mealLoggingStreak)d"),
                label: String(localized: "Streak"),
                color: WatchPalette.calories,
                spoken: String(localized: "Meal streak \(nutrition.mealLoggingStreak) days")
            )
        }
    }

    private var water: some View {
        HStack(spacing: 5) {
            ForEach(waterOptions) { option in
                Button {
                    store.logWater(fluidOunces: option.fluidOunces)
                    pours[option.id, default: 0] += 1
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: "drop.fill")
                            .font(.caption2)
                            .foregroundStyle(WatchPalette.water)
                            .symbolEffect(.bounce, value: pours[option.id, default: 0])
                        Text(option.label)
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(store.isSending)
                .accessibilityLabel(option.spoken)
            }
        }
        .padding(.top, 2)
    }
}
