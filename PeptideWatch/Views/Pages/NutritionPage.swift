import SwiftUI

/// Fourth page: calories and protein as a two-ring stack with today's
/// calories rolling up inside, protein and streak beneath, and one-tap
/// water logging whose drop bounces on each pour.
struct NutritionPage: View {
    @EnvironmentObject private var store: WatchStore
    let nutrition: WatchNutritionSnapshot
    /// Taps per water button, keyed by ounces, so only the tapped
    /// button's drop bounces.
    @State private var pours: [Int: Int] = [:]

    /// Water is stored in fluid ounces, so the labels follow the phone's
    /// unit setting or the two surfaces disagree about the same number.
    /// An older phone build that doesn't send the unit gets imperial,
    /// which is what the Watch always showed.
    private var isMetric: Bool { store.watchData.measurementUnit == "metric" }

    /// `spoken` is carried rather than derived: the metric amounts are
    /// the nearest whole ounce to a round millilitre figure, so deriving
    /// it from `oz` would announce "237 millilitres" for "+250mL".
    private struct WaterOption: Identifiable {
        let label: String
        let spoken: String
        let oz: Int
        var id: Int { oz }
    }

    private var waterOptions: [WaterOption] {
        isMetric
            ? [.init(label: "+250mL", spoken: String(localized: "Log 250 millilitres of water"), oz: 8),
               .init(label: "+500mL", spoken: String(localized: "Log 500 millilitres of water"), oz: 17),
               .init(label: "+1L", spoken: String(localized: "Log 1 litre of water"), oz: 34)]
            : [.init(label: "+8oz", spoken: String(localized: "Log 8 ounces of water"), oz: 8),
               .init(label: "+16oz", spoken: String(localized: "Log 16 ounces of water"), oz: 16),
               .init(label: "+32oz", spoken: String(localized: "Log 32 ounces of water"), oz: 32)]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                rings
                summary
                water
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Nutrition")
        .pageBackground(WatchPalette.caloriesStart)
    }

    private var rings: some View {
        ZStack {
            ActivityRings(rings: [
                RingSpec(id: "calories", progress: nutrition.calorieProgress,
                         color: WatchPalette.caloriesStart, symbol: "flame.fill"),
                RingSpec(id: "protein", progress: nutrition.proteinProgress,
                         color: WatchPalette.protein, symbol: "bolt.fill"),
            ], lineWidth: 14)
            VStack(spacing: -2) {
                RollingNumber(value: nutrition.caloriesToday)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("KCAL")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(WatchPalette.caloriesStart)
            }
            .padding(.horizontal, 34)
        }
        .frame(maxWidth: 124)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caloriesSpoken)
    }

    private var caloriesSpoken: String {
        nutrition.calorieTarget > 0
            ? String(localized: "\(nutrition.caloriesToday) of \(nutrition.calorieTarget) calories")
            : String(localized: "\(nutrition.caloriesToday) calories")
    }

    private var summary: some View {
        VStack(spacing: 4) {
            summaryRow(
                color: WatchPalette.protein,
                label: String(localized: "Protein"),
                value: nutrition.proteinTarget > 0
                    ? "\(nutrition.proteinToday)/\(nutrition.proteinTarget)g"
                    : "\(nutrition.proteinToday)g"
            )
            summaryRow(
                color: WatchPalette.caloriesEnd,
                label: String(localized: "Meal streak"),
                value: String(localized: "\(nutrition.mealLoggingStreak)d")
            )
        }
    }

    private func summaryRow(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }

    private var water: some View {
        HStack(spacing: 5) {
            ForEach(waterOptions) { option in
                Button {
                    store.logWater(oz: option.oz)
                    pours[option.oz, default: 0] += 1
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: "drop.fill")
                            .font(.caption2)
                            .foregroundStyle(WatchPalette.water)
                            .symbolEffect(.bounce, value: pours[option.oz, default: 0])
                        Text(option.label)
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(WatchPalette.water.opacity(0.22))
                    )
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(store.isSending)
                .accessibilityLabel(option.spoken)
            }
        }
        .padding(.top, 4)
    }
}
