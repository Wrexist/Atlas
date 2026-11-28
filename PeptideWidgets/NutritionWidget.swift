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
    /// The payload couldn't be read: the views draw redacted, not zero.
    var isUnavailable = false

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

    /// The ring's figure with its sign: "+300" past the target, so a
    /// full gauge can't read as 300 left.
    var signedHeadline: String {
        let figure = headline.formatted(.number.notation(.compactName))
        return isOver ? "+\(figure)" : figure
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
        completion(context.isPreview ? .placeholder : entry(from: WidgetStore.load(), at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NutritionEntry>) -> Void) {
        let now = Date.now
        let payload = WidgetStore.load()
        var entries = [entry(from: payload, at: now)]
        // WidgetKit may run the reload late; this entry starts the new
        // day at zero at midnight regardless.
        if payload.isLoaded {
            entries.append(entry(from: payload, at: WidgetData.nextMidnight(after: now)))
        }
        completion(Timeline(entries: entries, policy: .after(payload.reloadDate(after: now))))
    }

    private func entry(from payload: WidgetPayload, at date: Date) -> NutritionEntry {
        let data: WidgetData
        switch payload {
        case .missing: return .empty
        case .unreadable:
            var entry = NutritionEntry.placeholder
            entry.isUnavailable = true
            return entry
        case .loaded(let loaded): data = loaded.forDisplay(at: date)
        }
        return NutritionEntry(
            date: date,
            calories: data.caloriesToday,
            target: data.calorieTarget,
            protein: data.proteinToday,
            carbs: data.carbsToday,
            fat: data.fatToday,
            proteinTarget: data.proteinTarget,
            carbsTarget: data.carbsTarget,
            fatTarget: data.fatTarget,
            meals: data.mealsByCategory
        )
    }
}

// MARK: - Calorie ring

/// The day's calories as one ring split by meal, in the meal colours the
/// app's own calorie ring uses — so the widget is a window onto the same
/// picture rather than a second chart. Calories outside the four buckets
/// (or a payload without the breakdown) fill in the calorie colour.
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
        let parts = segments
        ZStack {
            RingGroove(lineWidth: lineWidth)
            // One raised finish over all the meal segments, so the ring
            // reads as a single lit tube split by colour.
            RaisedArc(progress: parts.last?.end ?? 0, lineWidth: lineWidth) {
                ZStack {
                    ForEach(parts) { segment in
                        Circle()
                            .inset(by: lineWidth / 2)
                            .trim(from: segment.start, to: segment.end)
                            .stroke(segment.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                    }
                }
            }
        }
    }

    private var segments: [Segment] {
        // Past the target the ring is simply full; the split still shows
        // where the day's calories came from.
        let scale = Double(max(entry.target, entry.calories))
        guard scale > 0, entry.calories > 0 else { return [] }

        var parts: [(Int, Color)] = entry.meals.enumerated().compactMap { index, meal -> (Int, Color)? in
            guard meal.calories > 0 else { return nil }
            return (meal.calories, WidgetMeal(rawValue: index)?.tint ?? WidgetPalette.calories)
        }
        let unbucketed = entry.calories - parts.reduce(0) { $0 + $1.0 }
        if unbucketed > 0 { parts.append((unbucketed, WidgetPalette.calories)) }

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
                .minimumScaleFactor(0.4)
                .widgetAccentable()
            Text(entry.headlineCaption)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(entry.isOver ? WidgetPalette.over : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

// MARK: - Macros

private struct Macro: Identifiable {
    let id: String
    let name: LocalizedStringKey
    let kind: MacroKind
    let grams: Int
    let target: Int
    let tint: Color

    var progress: Double { target > 0 ? Double(grams) / Double(target) : 0 }

    var isOver: Bool { target > 0 && grams > target }

    var amount: String {
        target > 0 ? "\(grams.formatted()) / \(target.formatted()) g" : "\(grams.formatted()) g"
    }

    /// "68", or "1.9K" once a figure stops fitting a third of a small widget.
    var compactGrams: String { grams.formatted(.number.notation(.compactName)) }

    /// "Protein 95 of 150 grams" — `amount` reads as "95 slash 150 g".
    var spokenAmount: Text {
        target > 0
            ? Text("\(Text(name)) \(grams) of \(target) grams")
            : Text("\(Text(name)) \(grams) grams")
    }

    static func all(_ entry: NutritionEntry) -> [Macro] {
        [
            Macro(id: "p", name: "Protein", kind: .protein, grams: entry.protein,
                  target: entry.proteinTarget, tint: WidgetPalette.protein),
            Macro(id: "c", name: "Carbs", kind: .carbs, grams: entry.carbs,
                  target: entry.carbsTarget, tint: WidgetPalette.carbs),
            Macro(id: "f", name: "Fat", kind: .fat, grams: entry.fat,
                  target: entry.fatTarget, tint: WidgetPalette.fat),
        ]
    }
}

/// Small-widget macro: a bar over "95" and the macro's icon. Without a target the bar would
/// be meaningless, so it stays an empty track.
private struct CompactMacro: View {
    let macro: Macro

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            WidgetBar(progress: macro.progress, tint: macro.tint, height: 3, showsOverflow: true)
            HStack(spacing: 2) {
                Text(macro.compactGrams)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText(value: Double(macro.grams)))
                MacroIcon(macro.kind, size: 10, relativeTo: .caption2)
                    .foregroundStyle(macro.tint)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Text(macro.name)) \(macro.grams) grams"))
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
                    // Past the target the figure takes the macro's colour,
                    // matching the deeper overflow on the bar below. Not the
                    // warning colour: more protein than planned isn't a fault.
                    .foregroundStyle(macro.isOver ? macro.tint : .primary)
                    .contentTransition(.numericText(value: Double(macro.grams)))
            }
            .lineLimit(1)
            // "Kolhydrater" next to "180 / 250 g" outgrows the column.
            .minimumScaleFactor(0.7)
            WidgetBar(progress: macro.progress, tint: macro.tint, showsOverflow: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(macro.spokenAmount)
    }
}

/// Four meal glyphs, lit in their ring colour once that meal has
/// something logged: the key to the ring's segments, and the day's shape
/// in one row.
private struct MealStrip: View {
    let meals: [WidgetMealSlot]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(WidgetMeal.allCases, id: \.self) { meal in
                let logged = meals.indices.contains(meal.rawValue)
                    && meals[meal.rawValue].entryCount > 0
                Image(systemName: meal.glyph)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(logged ? meal.tint : Color.secondary)
                    .frame(width: 22, height: 22)
                    .raisedDisc(logged ? meal.tint.opacity(0.18) : WidgetPalette.track)
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

struct SmallNutritionView: View {
    let entry: NutritionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(glyph: "fork.knife", title: "Nutrition", tint: WidgetPalette.accent)
            Spacer(minLength: 6)
            CalorieRing(entry: entry)
                .ringLabel(lineWidth: 8) { CalorieCenter(entry: entry, large: false) }
                .calorieAccessibility(entry)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 80, maxHeight: 80)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 6)
            HStack(spacing: 8) {
                ForEach(Macro.all(entry)) { CompactMacro(macro: $0) }
            }
        }
        .widgetBackdrop(WidgetPalette.accent)
    }
}

struct MediumNutritionView: View {
    let entry: NutritionEntry

    var body: some View {
        HStack(spacing: 16) {
            // The 44pt targets keep their size and the ring takes what
            // height is left, up to 78pt: a medium widget on a 375pt-wide
            // phone has about 116pt inside its margins, less than a fixed
            // 78pt ring plus the targets.
            VStack(spacing: 0) {
                CalorieRing(entry: entry, lineWidth: 9)
                    .ringLabel(lineWidth: 9) { CalorieCenter(entry: entry, large: true) }
                    .calorieAccessibility(entry)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 78, maxHeight: 78)
                    .layoutPriority(-1)
                // The 44pt hit frames sit edge to edge; the 32pt circles
                // inside them still read as two separate buttons.
                HStack(spacing: 0) {
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
                    tint: WidgetPalette.accent,
                    trailingAccessibilityLabel: entry.target > 0
                        ? Text("\(entry.calories) of \(entry.target) calories")
                        : nil,
                    trailingText: totalLabel
                )
                VStack(spacing: 4) {
                    ForEach(Macro.all(entry)) { MacroRow(macro: $0) }
                }
                Spacer(minLength: 0)
                MealStrip(meals: entry.meals)
            }
        }
        .widgetBackdrop(WidgetPalette.accent)
    }

    /// "1 296 / 2 575 kcal": what was eaten leads in the primary colour,
    /// the budget follows in secondary, so the figure reads at a glance
    /// without competing with the ring.
    private var totalLabel: Text {
        var eaten = AttributedString(entry.calories.formatted())
        eaten.foregroundColor = Color.primary
        var rest = AttributedString(entry.target > 0 ? " / \(entry.target.formatted()) kcal" : " kcal")
        rest.foregroundColor = Color.secondary
        return Text(eaten + rest)
    }
}

/// The small round buttons under the medium widget's ring: scan a meal
/// (opens the scanner) and log a glass of water (no app launch). The
/// circle is 32pt but the tappable frame is the 44pt minimum.
private struct QuickActionGlyph: View {
    let systemImage: String

    /// Apple's minimum hit target. `Spacing.minimumHitTarget` lives in
    /// the app's design system, which this extension doesn't compile.
    private static let hitTarget: CGFloat = 44

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(WidgetPalette.accent)
            .frame(width: 32, height: 32)
            .raisedDisc(WidgetPalette.accent.opacity(0.16))
            .frame(width: Self.hitTarget, height: Self.hitTarget)
            .contentShape(Rectangle())
    }
}

// MARK: - Lock screen

private struct CircularNutritionView: View {
    let entry: NutritionEntry

    var body: some View {
        Gauge(value: entry.progress) {
            Image(systemName: "fork.knife")
        } currentValueLabel: {
            Text(entry.signedHeadline)
                .foregroundStyle(entry.isOver ? WidgetPalette.over : Color.primary)
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
        .calorieAccessibility(entry)
    }
}

private extension View {
    /// Speaks a calorie ring and its centre as one sentence — "300 kcal
    /// left, 1,450 of 2,200 calories" — instead of loose fragments.
    func calorieAccessibility(_ entry: NutritionEntry) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(entry.budgetLine))
            .accessibilityValue(entry.target > 0 ? Text("\(entry.calories) of \(entry.target) calories") : Text(""))
    }
}

private struct RectangularNutritionView: View {
    let entry: NutritionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(entry.budgetLine)
                .minimumScaleFactor(0.8)
            } icon: {
                Image(systemName: "fork.knife")
            }
            .font(.headline)
            .widgetAccentable()
            HStack(spacing: 6) {
                lockScreenMacro(.protein, grams: entry.protein)
                lockScreenMacro(.carbs, grams: entry.carbs)
                lockScreenMacro(.fat, grams: entry.fat)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Protein \(entry.protein) grams, carbs \(entry.carbs) grams, fat \(entry.fat) grams"))
            Gauge(value: entry.progress) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
        }
        .lineLimit(1)
    }

    private func lockScreenMacro(_ kind: MacroKind, grams: Int) -> some View {
        HStack(spacing: 2) {
            MacroIcon(kind, size: 11)
            Text("\(grams)")
        }
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
                .redacted(reason: entry.isUnavailable ? .placeholder : [])
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
