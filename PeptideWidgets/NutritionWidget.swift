import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

/// Shape-matched to `WidgetData`'s nutrition fields so the provider is a
/// pass-through and the views only render.
struct NutritionEntry: TimelineEntry {
    let date: Date
    let calories: Int
    let target: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let proteinTarget: Int
    let carbsTarget: Int
    let fatTarget: Int
    let meals: [WidgetMealSlot]

    var progress: Double {
        guard target > 0 else { return 0 }
        return min(1.0, Double(calories) / Double(target))
    }

    var isOver: Bool { target > 0 && calories > target }

    /// The number the ring leads with: what's left of the budget, how far
    /// past it the day went, or the plain total when there's no target.
    /// "What's left" is the figure a glance is for — it answers "can I
    /// have this?" without arithmetic.
    var headline: Int { target > 0 ? abs(target - calories) : calories }

    var headlineCaption: LocalizedStringKey {
        if target == 0 { return "kcal" }
        return isOver ? "over" : "left"
    }

    /// One-line form for the lock screen.
    var budgetLine: LocalizedStringKey {
        if target == 0 { return "\(calories.formatted()) kcal today" }
        return isOver
            ? "\(headline.formatted()) kcal over"
            : "\(headline.formatted()) kcal left"
    }

    static let empty = NutritionEntry(
        date: .now, calories: 0, target: 0, protein: 0, carbs: 0, fat: 0,
        proteinTarget: 0, carbsTarget: 0, fatTarget: 0, meals: []
    )

    static let placeholder = NutritionEntry(
        date: .now,
        calories: 1450,
        target: 2200,
        protein: 95,
        carbs: 160,
        fat: 48,
        proteinTarget: 150,
        carbsTarget: 240,
        fatTarget: 70,
        meals: [
            WidgetMealSlot(category: "Breakfast", calories: 420, entryCount: 1),
            WidgetMealSlot(category: "Lunch", calories: 680, entryCount: 2),
            WidgetMealSlot(category: "Dinner", calories: 0, entryCount: 0),
            WidgetMealSlot(category: "Snack", calories: 350, entryCount: 1),
        ]
    )
}

// MARK: - Timeline Provider

struct NutritionTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NutritionEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (NutritionEntry) -> Void) {
        completion(context.isPreview ? .placeholder : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NutritionEntry>) -> Void) {
        completion(Timeline(
            entries: [currentEntry()],
            policy: .after(WidgetStore.nextRefresh(after: .now))
        ))
    }

    private func currentEntry() -> NutritionEntry {
        guard let data = WidgetStore.load() else { return .empty }
        // The intake belongs to the day the app last wrote it. Past
        // midnight with no app launch it would be yesterday's, so the
        // widget starts the new day at zero against the same targets.
        let today = Calendar.current.isDateInToday(data.lastUpdated)
        return NutritionEntry(
            date: .now,
            calories: today ? data.caloriesToday : 0,
            target: data.calorieTarget,
            protein: today ? data.proteinToday : 0,
            carbs: today ? data.carbsToday : 0,
            fat: today ? data.fatToday : 0,
            proteinTarget: data.proteinTarget,
            carbsTarget: data.carbsTarget,
            fatTarget: data.fatTarget,
            meals: today ? data.mealsByCategory : data.mealsByCategory.map {
                WidgetMealSlot(category: $0.category, calories: 0, entryCount: 0)
            }
        )
    }
}

// MARK: - Calorie ring

/// The day's calories as one ring split by meal, in the meal colours the
/// app's own calorie ring uses — so the widget is a window onto the same
/// picture rather than a second chart. Calories outside the four buckets
/// (or a payload without the breakdown) fill in brand emerald.
private struct CalorieRing: View {
    let entry: NutritionEntry
    var lineWidth: CGFloat = 8

    private struct Segment: Identifiable {
        let id: Int
        let start: Double
        let end: Double
        let tint: Color
    }

    var body: some View {
        ZStack {
            Circle().stroke(WidgetPalette.track, lineWidth: lineWidth)
            ForEach(segments) { segment in
                Circle()
                    .trim(from: segment.start, to: segment.end)
                    .stroke(segment.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }
        }
        // Strokes straddle the path; keep the whole ring inside the frame.
        .padding(lineWidth / 2)
    }

    private var segments: [Segment] {
        // Past the target the ring is simply full; the split still shows
        // where the day's calories came from.
        let scale = Double(max(entry.target, entry.calories))
        guard scale > 0, entry.calories > 0 else { return [] }

        var parts: [(Int, Color)] = entry.meals.enumerated().compactMap { index, meal -> (Int, Color)? in
            guard meal.calories > 0 else { return nil }
            return (meal.calories, WidgetMeal(rawValue: index)?.tint ?? WidgetPalette.brand)
        }
        let unbucketed = entry.calories - parts.reduce(0) { $0 + $1.0 }
        if unbucketed > 0 { parts.append((unbucketed, WidgetPalette.brand)) }

        // A hairline gap between meals, only when there is more than one.
        let gap = parts.count > 1 ? 0.008 : 0
        var cursor = 0.0
        return parts.enumerated().map { index, part -> Segment in
            let length = Double(part.0) / scale
            defer { cursor += length }
            return Segment(
                id: index,
                start: cursor,
                end: cursor + max(length - gap, length / 2),
                tint: part.1
            )
        }
    }
}

private struct CalorieCenter: View {
    let entry: NutritionEntry
    let large: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(entry.headline.formatted())
                .font(.system(large ? .title2 : .title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(entry.headline)))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            Text(entry.headlineCaption)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(entry.isOver ? WidgetPalette.over : .secondary)
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Macros

private struct Macro: Identifiable {
    let id: String
    let name: LocalizedStringKey
    let letter: LocalizedStringKey
    let grams: Int
    let target: Int
    let tint: Color

    var progress: Double { target > 0 ? Double(grams) / Double(target) : 0 }

    var amount: String { target > 0 ? "\(grams) / \(target) g" : "\(grams) g" }

    static func all(_ entry: NutritionEntry) -> [Macro] {
        [
            Macro(id: "p", name: "Protein", letter: "P", grams: entry.protein,
                  target: entry.proteinTarget, tint: WidgetPalette.protein),
            Macro(id: "c", name: "Carbs", letter: "C", grams: entry.carbs,
                  target: entry.carbsTarget, tint: WidgetPalette.carbs),
            Macro(id: "f", name: "Fat", letter: "F", grams: entry.fat,
                  target: entry.fatTarget, tint: WidgetPalette.fat),
        ]
    }
}

/// Small-widget macro: a bar over "95 P". Without a target the bar would
/// be meaningless, so it stays an empty track.
private struct CompactMacro: View {
    let macro: Macro

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            WidgetBar(progress: macro.progress, tint: macro.tint, height: 3)
            HStack(spacing: 2) {
                Text("\(macro.grams)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText(value: Double(macro.grams)))
                Text(macro.letter)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(macro.tint)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }
}

private struct MacroRow: View {
    let macro: Macro

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(macro.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(macro.amount)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText(value: Double(macro.grams)))
            }
            .lineLimit(1)
            WidgetBar(progress: macro.progress, tint: macro.tint)
        }
    }
}

/// Four meal glyphs, lit once that meal has something logged — the day's
/// shape in one row.
private struct MealStrip: View {
    let meals: [WidgetMealSlot]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(WidgetMeal.allCases, id: \.self) { meal in
                let logged = meals.indices.contains(meal.rawValue)
                    && meals[meal.rawValue].entryCount > 0
                Image(systemName: meal.glyph)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(logged ? meal.tint : Color.secondary.opacity(0.5))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(logged ? meal.tint.opacity(0.18) : WidgetPalette.track))
                    .widgetAccentable(logged)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: Text {
        let logged = meals.filter { $0.entryCount > 0 }.map(\.category)
        return logged.isEmpty
            ? Text("No meals logged yet")
            : Text("Logged: \(logged.formatted(.list(type: .and)))")
    }
}

// MARK: - Home screen

private struct SmallNutritionView: View {
    let entry: NutritionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(glyph: "fork.knife", title: "Nutrition", tint: WidgetPalette.brand)
            Spacer(minLength: 6)
            CalorieRing(entry: entry)
                .overlay { CalorieCenter(entry: entry, large: false) }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 80, maxHeight: 80)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 6)
            HStack(spacing: 8) {
                ForEach(Macro.all(entry)) { CompactMacro(macro: $0) }
            }
        }
        .widgetBackdrop(WidgetPalette.brand)
    }
}

private struct MediumNutritionView: View {
    let entry: NutritionEntry

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 8) {
                CalorieRing(entry: entry, lineWidth: 9)
                    .overlay { CalorieCenter(entry: entry, large: true) }
                    .frame(width: 86, height: 86)
                HStack(spacing: 10) {
                    if let scan = QuickAction.scanMeal.url {
                        Link(destination: scan) {
                            QuickActionGlyph(systemImage: QuickAction.scanMeal.systemImage)
                        }
                        .accessibilityLabel(Text(QuickAction.scanMeal.title))
                    }
                    Button(intent: LogWaterGlassIntent()) {
                        QuickActionGlyph(systemImage: QuickAction.logWater.systemImage)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Log a glass of water"))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(
                    glyph: "fork.knife",
                    title: "Nutrition",
                    tint: WidgetPalette.brand,
                    trailing: totalLabel
                )
                VStack(spacing: 4) {
                    ForEach(Macro.all(entry)) { MacroRow(macro: $0) }
                }
                Spacer(minLength: 0)
                MealStrip(meals: entry.meals)
            }
        }
        .widgetBackdrop(WidgetPalette.brand)
    }

    private var totalLabel: String {
        entry.target > 0
            ? "\(entry.calories.formatted()) / \(entry.target.formatted())"
            : "\(entry.calories.formatted()) kcal"
    }
}

/// The small round buttons under the medium widget's ring: scan a meal
/// (opens the scanner) and log a glass of water (no app launch).
private struct QuickActionGlyph: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(WidgetPalette.brand)
            .frame(width: 32, height: 32)
            .background(Circle().fill(WidgetPalette.brand.opacity(0.16)))
    }
}

// MARK: - Lock screen

private struct CircularNutritionView: View {
    let entry: NutritionEntry

    var body: some View {
        Gauge(value: entry.progress) {
            Image(systemName: "fork.knife")
        } currentValueLabel: {
            Text(entry.headline.formatted(.number.notation(.compactName)))
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }
}

private struct RectangularNutritionView: View {
    let entry: NutritionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(entry.budgetLine)
            } icon: {
                Image(systemName: "fork.knife")
            }
            .font(.headline)
            .widgetAccentable()
            Text("P \(entry.protein) · C \(entry.carbs) · F \(entry.fat)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Gauge(value: entry.progress) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
        }
        .lineLimit(1)
    }
}

private struct InlineNutritionView: View {
    let entry: NutritionEntry

    var body: some View {
        Label {
            Text(entry.budgetLine)
        } icon: {
            Image(systemName: "fork.knife")
        }
    }
}

// MARK: - Widget

struct NutritionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NutritionEntry

    var body: some View {
        switch family {
        case .systemMedium: MediumNutritionView(entry: entry)
        case .accessoryCircular: CircularNutritionView(entry: entry).accessoryBackdrop()
        case .accessoryRectangular: RectangularNutritionView(entry: entry).accessoryBackdrop()
        case .accessoryInline: InlineNutritionView(entry: entry).accessoryBackdrop()
        default: SmallNutritionView(entry: entry)
        }
    }
}

struct NutritionWidget: Widget {
    let kind = "NutritionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NutritionTimelineProvider()) { entry in
            NutritionWidgetView(entry: entry)
                .widgetURL(WidgetDeepLink.meals)
        }
        .configurationDisplayName("Nutrition")
        .description("Calories left today, split by meal, with your macros.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}
