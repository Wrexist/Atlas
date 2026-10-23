import Foundation

/// Condenses the last week of nutrition into the few numbers the diet
/// coach chat needs — targets, average intake, protein adherence and the
/// weight trend — and renders them as a compact brief for the system
/// prompt. Only these aggregates leave the device, never meal names.
enum NutritionCoachEngine {

    struct Summary: Equatable, Sendable {
        let days: Int
        /// Days in the window with any calories logged.
        let loggedDays: Int
        let targets: NutritionTargets?
        let averageCalories: Int?
        let averageProteinG: Int?
        let averageCarbsG: Int?
        let averageFatG: Int?
        /// Logged days that reached the protein target.
        let proteinDaysHit: Int
        /// Last minus first weigh-in within `weightWindowDays`.
        let weightChangeKg: Double?
        let weightSpanDays: Int?
    }

    static let weightWindowDays = 14

    static func summary(
        of profile: UserProfile,
        days: Int = 7,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Summary {
        let today = calendar.startOfDay(for: now)
        let window = (0..<days).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let logged = window
            .map { LifestyleDataLogic.consumption(in: profile, for: $0) }
            .filter { $0.caloriesKcal > 0 }

        func average(_ value: (DailyConsumption) -> Int) -> Int? {
            guard !logged.isEmpty else { return nil }
            return Int((Double(logged.map(value).reduce(0, +)) / Double(logged.count)).rounded())
        }

        let proteinTarget = profile.nutritionTargets?.proteinG
        let proteinDaysHit = proteinTarget.map { target in
            logged.filter { $0.proteinG >= target }.count
        } ?? 0

        let weightCutoff = calendar.date(byAdding: .day, value: -weightWindowDays, to: today) ?? today
        let weights = profile.weightHistory
            .filter { $0.date >= weightCutoff && $0.date <= now }
            .sorted { $0.date < $1.date }
        let weightTrend: (change: Double, span: Int)? = {
            guard let first = weights.first, let last = weights.last, weights.count >= 2 else { return nil }
            let span = calendar.dateComponents([.day], from: first.date, to: last.date).day ?? 0
            return (last.kg - first.kg, span)
        }()

        return Summary(
            days: days,
            loggedDays: logged.count,
            targets: profile.nutritionTargets,
            averageCalories: average(\.caloriesKcal),
            averageProteinG: average(\.proteinG),
            averageCarbsG: average(\.carbsG),
            averageFatG: average(\.fatG),
            proteinDaysHit: proteinDaysHit,
            weightChangeKg: weightTrend?.change,
            weightSpanDays: weightTrend?.span
        )
    }

    /// Plain-text brief appended to the coach's system prompt. Every line
    /// says what's missing rather than inventing a zero.
    static func brief(_ summary: Summary, unit: MeasurementUnit) -> String {
        var lines: [String] = []
        if let targets = summary.targets {
            lines.append("Daily targets: \(targets.calories) kcal, protein \(targets.proteinG) g, carbs \(targets.carbsG) g, fat \(targets.fatG) g.")
        } else {
            lines.append("Daily targets: not set.")
        }
        lines.append("Days with food logged: \(summary.loggedDays) of \(summary.days).")
        if let calories = summary.averageCalories,
           let protein = summary.averageProteinG,
           let carbs = summary.averageCarbsG,
           let fat = summary.averageFatG {
            lines.append("Average on logged days: \(calories) kcal, protein \(protein) g, carbs \(carbs) g, fat \(fat) g.")
        } else {
            lines.append("Average intake: no meals logged this week.")
        }
        if let targets = summary.targets, summary.loggedDays > 0 {
            lines.append("Protein target (\(targets.proteinG) g) reached on \(summary.proteinDaysHit) of \(summary.loggedDays) logged days.")
        }
        if let change = summary.weightChangeKg, let span = summary.weightSpanDays {
            lines.append("Weight trend: \(formattedWeightChange(change, unit: unit)) over \(span) days.")
        } else {
            lines.append("Weight trend: not enough weigh-ins in the last \(weightWindowDays) days.")
        }
        return lines.joined(separator: "\n")
    }

    static func formattedWeightChange(_ kg: Double, unit: MeasurementUnit) -> String {
        String(format: "%+.1f", unit.weightForDisplay(kg)) + " " + unit.weightSuffix
    }
}
