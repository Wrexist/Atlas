import SwiftUI

/// Third Watch page — nutrition glance. Mirrors the iOS Meals
/// tab's calorie + protein rings and the meal-logging streak so the
/// wrist surface stays in lockstep with what the user sees on the
/// phone. Renders nothing meaningful when `watchData.nutrition` is
/// nil (older phone build hasn't synced the field, or the user has
/// no nutrition data yet) — caller in `PeptideWatchApp` hides the
/// whole page in that case so we never show a blank screen.
struct WatchNutritionView: View {
    @EnvironmentObject private var store: WatchStore

    private var nutrition: WatchNutritionSnapshot? { store.watchData.nutrition }

    /// Water is stored in fluid ounces, so the labels have to follow the
    /// phone's unit setting or the two surfaces disagree about the same
    /// number. Defaults to imperial when an older phone build hasn't
    /// synced the field — that is what the watch showed before.
    private var isMetric: Bool { store.watchData.measurementUnit == "metric" }

    private var waterOptions: [WaterOption] {
        isMetric
            ? [.init(label: "+250mL", spoken: "Add 250 millilitres of water", oz: 8),
               .init(label: "+500mL", spoken: "Add 500 millilitres of water", oz: 17),
               .init(label: "+1L", spoken: "Add 1 litre of water", oz: 34)]
            : [.init(label: "+8oz", spoken: "Add 8 ounces of water", oz: 8),
               .init(label: "+16oz", spoken: "Add 16 ounces of water", oz: 16),
               .init(label: "+32oz", spoken: "Add 32 ounces of water", oz: 32)]
    }

    /// `spoken` is carried rather than derived: the metric labels are the
    /// nearest whole ounce to a round millilitre figure, so computing the
    /// announcement from `oz` would say "237 millilitres" for the button
    /// that reads "+250mL".
    private struct WaterOption: Identifiable {
        let label: String
        let spoken: String
        let oz: Int
        var id: Int { oz }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let nutrition {
                    caloriesRing(nutrition)
                    proteinRow(nutrition)
                    streakRow(nutrition)
                    mealsRow(nutrition)
                    waterQuickAddRow
                } else {
                    emptyState
                    waterQuickAddRow
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
        }
        .navigationTitle("Nutrition")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Water quick-add

    private var waterQuickAddRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "drop.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text("Log water")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(waterOptions) { option in
                    waterButton(label: option.label, spoken: option.spoken, oz: option.oz)
                }
            }
        }
    }

    private func waterButton(label: String, spoken: String, oz: Int) -> some View {
        Button {
            store.logWater(oz: oz)
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.blue.opacity(0.6))
                )
        }
        .buttonStyle(.plain)
        // VoiceOver reads "+8oz" as letters otherwise.
        .accessibilityLabel(spoken)
        .disabled(store.isSending)
        .accessibilityLabel("Log \(oz) ounces of water")
    }

    // MARK: - Calorie ring

    private func caloriesRing(_ n: WatchNutritionSnapshot) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: n.calorieProgress)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 1.0, green: 0.62, blue: 0.30),
                                Color(red: 0.95, green: 0.40, blue: 0.55),
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(n.caloriesToday)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    if n.calorieTarget > 0 {
                        Text("of \(n.calorieTarget)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text("kcal")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 92, height: 92)

            Text("Calories today")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Protein row

    private func proteinRow(_ n: WatchNutritionSnapshot) -> some View {
        statRow(
            icon: "fish.fill",
            tint: Color(red: 0.36, green: 0.78, blue: 0.55),
            value: "\(n.proteinToday)g",
            subtitle: n.proteinTarget > 0
                ? "of \(n.proteinTarget)g protein"
                : "protein"
        )
    }

    // MARK: - Streak

    private func streakRow(_ n: WatchNutritionSnapshot) -> some View {
        statRow(
            icon: "flame.fill",
            tint: .orange,
            value: n.mealLoggingStreak == 1 ? "1 day" : "\(n.mealLoggingStreak) days",
            subtitle: "Meal streak"
        )
    }

    private func mealsRow(_ n: WatchNutritionSnapshot) -> some View {
        statRow(
            icon: "fork.knife",
            tint: .indigo,
            value: n.mealEntriesToday == 1 ? "1 entry" : "\(n.mealEntriesToday) entries",
            subtitle: "Logged today"
        )
    }

    // MARK: - Shared row layout

    private func statRow(
        icon: String,
        tint: Color,
        value: String,
        subtitle: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("No nutrition logged yet")
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Text("Log a meal in Atlas to see it here.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 30)
        .padding(.horizontal, 8)
    }
}
