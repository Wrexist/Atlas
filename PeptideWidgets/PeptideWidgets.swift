import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct DoseEntry: TimelineEntry {
    let date: Date
    let peptideName: String
    let dose: String
    let doseTime: String
    let nextDoseDate: Date?
    let completed: Int
    let total: Int
    let compliance: Double
    let upcoming: [WidgetDoseSlot]

    static let placeholder = DoseEntry(
        date: .now,
        peptideName: "BPC-157",
        dose: "250 mcg",
        doseTime: "8:00 AM",
        nextDoseDate: .now,
        completed: 3,
        total: 5,
        compliance: 0.6,
        upcoming: [
            WidgetDoseSlot(peptideName: "BPC-157",     dose: "250 mcg", time: .now, completed: true),
            WidgetDoseSlot(peptideName: "TB-500",      dose: "2 mg",    time: .now.addingTimeInterval(3600), completed: false),
            WidgetDoseSlot(peptideName: "Glutathione", dose: "200 mg",  time: .now.addingTimeInterval(7200), completed: false),
        ]
    )
}

// MARK: - Timeline Provider

struct DoseTimelineProvider: TimelineProvider {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func placeholder(in context: Context) -> DoseEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (DoseEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DoseEntry>) -> Void) {
        let entry = currentEntry()
        let calendar = Calendar.current

        // Always refresh at midnight to show the new day's schedule
        let midnight = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        let fifteenMin = calendar.date(byAdding: .minute, value: 15, to: .now) ?? .now

        let nextUpdate: Date
        if let doseDate = entry.nextDoseDate, doseDate > .now, doseDate <= fifteenMin {
            // Dose is imminent: refresh 1 min after it's due
            nextUpdate = min(doseDate.addingTimeInterval(60), midnight)
        } else {
            // Standard 15-min refresh, but never past midnight
            nextUpdate = min(fifteenMin, midnight)
        }

        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func currentEntry() -> DoseEntry {
        guard let widgetData = loadWidgetData() else {
            return DoseEntry(
                date: .now,
                peptideName: "",
                dose: "",
                doseTime: "",
                nextDoseDate: nil,
                completed: 0,
                total: 0,
                compliance: 0,
                upcoming: []
            )
        }

        let doseTime: String
        if let time = widgetData.nextDoseTime {
            doseTime = time.formatted(.dateTime.hour().minute())
        } else {
            doseTime = ""
        }

        return DoseEntry(
            date: .now,
            peptideName: widgetData.nextPeptideName,
            dose: widgetData.nextDose,
            doseTime: doseTime,
            nextDoseDate: widgetData.nextDoseTime,
            completed: widgetData.completedToday,
            total: widgetData.totalToday,
            compliance: widgetData.compliance,
            upcoming: widgetData.upcoming
        )
    }

    private func loadWidgetData() -> WidgetData? {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appendingPathComponent("widget-data.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(WidgetData.self, from: data)
    }
}

// MARK: - Small Widget View

struct SmallWidgetView: View {
    let entry: DoseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "flask.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                Text("PeptideX")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if entry.total == 0 {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
                Text("No protocols")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else if entry.dose.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
                Text("All done!")
                    .font(.headline)
            } else {
                Text(entry.peptideName)
                    .font(.headline)
                    .lineLimit(1)
                Text(entry.dose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.doseTime)
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Medium Widget View

struct MediumWidgetView: View {
    let entry: DoseEntry

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Compliance ring + counter — anchors the widget visually.
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: entry.compliance)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(entry.compliance * 100))%")
                        .font(.system(size: 14, weight: .bold))
                }
                .frame(width: 56, height: 56)

                Text("\(entry.completed)/\(entry.total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Today list — shows the day at a glance instead of a single
            // next dose. Capped at 3 rows so a default Dynamic Type viewport
            // never clips on the Medium family.
            VStack(alignment: .leading, spacing: 6) {
                Text("Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if entry.total == 0 {
                    Text("Create a protocol")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("to start tracking doses")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                } else if entry.upcoming.isEmpty {
                    Text("All doses completed!")
                        .font(.headline)
                        .foregroundStyle(.green)
                } else {
                    ForEach(entry.upcoming.prefix(3), id: \.time) { slot in
                        doseRow(slot)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func doseRow(_ slot: WidgetDoseSlot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: slot.completed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(slot.completed ? .green : .secondary)
            Text(slot.peptideName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(slot.completed ? .secondary : .primary)
                .strikethrough(slot.completed, color: .secondary)
                .lineLimit(1)
            Text("\u{2022} \(slot.dose)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(slot.time.formatted(.dateTime.hour().minute()))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Widget Definitions

struct NextDoseWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: DoseEntry

    var body: some View {
        switch family {
        case .systemMedium:
            MediumWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

struct NextDoseWidget: Widget {
    let kind = "NextDoseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DoseTimelineProvider()) { entry in
            NextDoseWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Dose")
        .description("Shows your next scheduled peptide dose")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ComplianceWidget: Widget {
    let kind = "ComplianceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DoseTimelineProvider()) { entry in
            MediumWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Compliance")
        .description("Track your daily dose completion")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Nutrition Widget (Phase 7)

/// Timeline entry for the nutrition widget. Shape-matched to
/// `WidgetData`'s nutrition fields so the timeline provider is a
/// trivial pass-through.
struct NutritionEntry: TimelineEntry {
    let date: Date
    let calories: Int
    let target: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let meals: [WidgetMealSlot]

    var progress: Double {
        guard target > 0 else { return 0 }
        return min(1.0, Double(calories) / Double(target))
    }

    static let placeholder = NutritionEntry(
        date: .now,
        calories: 1450,
        target: 2200,
        protein: 95,
        carbs: 160,
        fat: 48,
        meals: [
            WidgetMealSlot(category: "Breakfast", calories: 420, entryCount: 1),
            WidgetMealSlot(category: "Lunch",     calories: 680, entryCount: 2),
            WidgetMealSlot(category: "Dinner",    calories: 0,   entryCount: 0),
            WidgetMealSlot(category: "Snack",     calories: 350, entryCount: 1),
        ]
    )
}

struct NutritionTimelineProvider: TimelineProvider {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func placeholder(in context: Context) -> NutritionEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (NutritionEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NutritionEntry>) -> Void) {
        let entry = currentEntry()
        let calendar = Calendar.current
        // Reset at midnight so tomorrow's empty rings paint correctly
        // without waiting for the next in-app log to push fresh data.
        let midnight = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        let fifteenMin = calendar.date(byAdding: .minute, value: 15, to: .now) ?? .now
        let nextUpdate = min(fifteenMin, midnight)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func currentEntry() -> NutritionEntry {
        guard let widgetData = loadWidgetData() else {
            return NutritionEntry(
                date: .now,
                calories: 0,
                target: 0,
                protein: 0,
                carbs: 0,
                fat: 0,
                meals: []
            )
        }
        return NutritionEntry(
            date: .now,
            calories: widgetData.caloriesToday,
            target: widgetData.calorieTarget,
            protein: widgetData.proteinToday,
            carbs: widgetData.carbsToday,
            fat: widgetData.fatToday,
            meals: widgetData.mealsByCategory
        )
    }

    private func loadWidgetData() -> WidgetData? {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appendingPathComponent("widget-data.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(WidgetData.self, from: data)
    }
}

struct SmallNutritionView: View {
    let entry: NutritionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("Today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: entry.progress)
                    .stroke(
                        LinearGradient(
                            colors: [.orange, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(entry.calories)")
                        .font(.system(size: 18, weight: .heavy))
                        .monospacedDigit()
                    if entry.target > 0 {
                        Text("of \(entry.target)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text("kcal")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct MediumNutritionView: View {
    let entry: NutritionEntry

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Ring + total on the left mirrors the in-app rings so the
            // widget feels like a window into the same data.
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.25), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: entry.progress)
                        .stroke(
                            LinearGradient(
                                colors: [.orange, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(entry.calories)")
                            .font(.system(size: 16, weight: .heavy))
                            .monospacedDigit()
                        Text("kcal")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 70, height: 70)

                if entry.target > 0 {
                    Text("of \(entry.target)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // Per-category breakdown on the right — same buckets as
            // the Lifestyle tab's `MealCategoriesCard`.
            VStack(alignment: .leading, spacing: 4) {
                Text("Meals")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if entry.meals.allSatisfy({ $0.calories == 0 }) {
                    Text("No meals logged yet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entry.meals, id: \.category) { meal in
                        nutritionMealRow(meal)
                    }
                }

                Divider().padding(.top, 2)

                HStack(spacing: 6) {
                    macroPip(label: "P", value: entry.protein, color: .green)
                    macroPip(label: "C", value: entry.carbs,   color: .blue)
                    macroPip(label: "F", value: entry.fat,     color: .orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func nutritionMealRow(_ meal: WidgetMealSlot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: iconFor(meal.category))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tintFor(meal.category))
                .frame(width: 14)
            Text(meal.category)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(meal.calories > 0 ? .primary : .secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(meal.calories)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func macroPip(label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 11, weight: .heavy))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background {
            Capsule().fill(color.opacity(0.15))
        }
    }

    private func iconFor(_ category: String) -> String {
        WidgetMealStyle.icon(forCategoryName: category)
    }

    private func tintFor(_ category: String) -> Color {
        WidgetMealStyle.tint(forCategoryName: category)
    }
}

/// Widget-target mapping from the `category` string in the shared
/// `WidgetData` blob to the SwiftUI icon + accent color. Lives here
/// (not in the app target) because the widget extension can't import
/// the app module — `MealCategory.tint` and `.icon` aren't
/// reachable. RGB values mirror `MealCategory.tint` exactly so a
/// user toggling between app and widget sees the same palette.
private enum WidgetMealStyle {
    static func icon(forCategoryName name: String) -> String {
        switch name {
        case "Breakfast": "sun.horizon.fill"
        case "Lunch":     "sun.max.fill"
        case "Dinner":    "moon.stars.fill"
        case "Snack":     "leaf.fill"
        default:          "fork.knife"
        }
    }

    static func tint(forCategoryName name: String) -> Color {
        switch name {
        case "Breakfast": Color(red: 1.0,  green: 0.62, blue: 0.30)
        case "Lunch":     Color(red: 0.98, green: 0.78, blue: 0.20)
        case "Dinner":    Color(red: 0.48, green: 0.50, blue: 0.92)
        case "Snack":     Color(red: 0.36, green: 0.78, blue: 0.55)
        default:          .secondary
        }
    }
}

struct NutritionWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: NutritionEntry

    var body: some View {
        switch family {
        case .systemMedium:
            MediumNutritionView(entry: entry)
        default:
            SmallNutritionView(entry: entry)
        }
    }
}

struct NutritionWidget: Widget {
    let kind = "NutritionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NutritionTimelineProvider()) { entry in
            NutritionWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Nutrition")
        .description("Today's calorie ring and per-meal breakdown from PeptideX.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Widget Bundle

@main
struct PeptideWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextDoseWidget()
        ComplianceWidget()
        NutritionWidget()
        if #available(iOS 16.1, *) {
            DoseWindowLiveActivity()
        }
    }
}
