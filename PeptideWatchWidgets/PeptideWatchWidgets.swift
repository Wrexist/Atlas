import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct WatchDoseEntry: TimelineEntry {
    let date: Date
    let nextPeptide: String
    let nextDose: String
    let nextDoseTime: Date?
    let completedToday: Int
    let totalToday: Int

    var compliance: Double {
        totalToday > 0 ? Double(completedToday) / Double(totalToday) : 0
    }

    static let placeholder = WatchDoseEntry(
        date: .now,
        nextPeptide: "BPC-157",
        nextDose: "250 mcg",
        nextDoseTime: Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: .now),
        completedToday: 3,
        totalToday: 5
    )
}

// MARK: - Provider

struct WatchDoseProvider: TimelineProvider {
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func placeholder(in context: Context) -> WatchDoseEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (WatchDoseEntry) -> Void) {
        if context.isPreview { completion(.placeholder); return }
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchDoseEntry>) -> Void) {
        let current = entry(at: .now)
        let calendar = Calendar.current
        // Refresh at the next dose time, otherwise every 15 minutes, otherwise
        // at midnight. The midnight entry empties the day even when the
        // refresh runs late.
        let midnight = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        let fifteenMin = calendar.date(byAdding: .minute, value: 15, to: .now) ?? .now
        let nextUpdate: Date
        if let doseDate = current.nextDoseTime, doseDate > .now, doseDate <= fifteenMin {
            nextUpdate = min(doseDate.addingTimeInterval(60), midnight)
        } else {
            nextUpdate = min(fifteenMin, midnight)
        }
        completion(Timeline(entries: [current, entry(at: midnight)], policy: .after(nextUpdate)))
    }

    /// Reads the same `watch_data.json` the watch app already syncs to via
    /// `WatchSyncService` — the widget surface piggybacks on the existing
    /// pipeline, no new sync code required.
    private func entry(at date: Date) -> WatchDoseEntry {
        guard let url = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
                .appendingPathComponent("watch_data.json"),
              let data = try? Data(contentsOf: url),
              let watchData = try? Self.decoder.decode(WatchData.self, from: data).forDisplay(at: date)
        else {
            return WatchDoseEntry(
                date: date, nextPeptide: "", nextDose: "",
                nextDoseTime: nil, completedToday: 0, totalToday: 0
            )
        }

        let next = watchData.todayEntries.first { !$0.completed }

        return WatchDoseEntry(
            date: date,
            nextPeptide: next?.abbreviation ?? "",
            nextDose: next?.dose ?? "",
            nextDoseTime: next?.scheduledTime,
            completedToday: watchData.completedToday,
            totalToday: watchData.totalToday
        )
    }
}

// MARK: - Views

/// Modular-style three-line layout matching the screenshot guide's slot 7
/// "modularLarge" spec — title (Next Dose), primary (time), secondary
/// (peptide name).
struct WatchAccessoryRectangularView: View {
    let entry: WatchDoseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Next Dose")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if let time = entry.nextDoseTime {
                Text(time.formatted(.dateTime.hour().minute()))
                    .font(.title3.weight(.bold))
                    .widgetAccentable()
            } else {
                Text(entry.totalToday == 0 ? "—" : "Done")
                    .font(.title3.weight(.bold))
                    .widgetAccentable()
            }
            Text(entry.nextPeptide.isEmpty
                 ? (entry.totalToday == 0 ? "No protocols" : "All complete")
                 : "\(entry.nextPeptide) · \(entry.nextDose)")
                .font(.caption2)
                .lineLimit(1)
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct WatchAccessoryCircularView: View {
    let entry: WatchDoseEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.totalToday == 0 {
                Image(systemName: "flask")
                    .font(.title3)
            } else {
                VStack(spacing: 0) {
                    Text("\(entry.completedToday)")
                        .font(.title3.weight(.bold))
                        .widgetAccentable()
                    Text("/\(entry.totalToday)")
                        .font(.caption2)
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct WatchAccessoryInlineView: View {
    let entry: WatchDoseEntry

    var body: some View {
        if let time = entry.nextDoseTime, !entry.nextPeptide.isEmpty {
            Text("\(entry.nextPeptide) · \(time.formatted(.dateTime.hour().minute()))")
        } else if entry.totalToday > 0 {
            Text("\(entry.completedToday)/\(entry.totalToday) doses today")
        } else {
            Text("Atlas")
        }
    }
}

struct WatchNextDoseEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: WatchDoseEntry

    var body: some View {
        switch family {
        case .accessoryRectangular: WatchAccessoryRectangularView(entry: entry)
        case .accessoryCircular:    WatchAccessoryCircularView(entry: entry)
        case .accessoryInline:      WatchAccessoryInlineView(entry: entry)
        default:                    WatchAccessoryRectangularView(entry: entry)
        }
    }
}

// MARK: - Widget

struct WatchNextDoseWidget: Widget {
    let kind = "WatchNextDoseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchDoseProvider()) { entry in
            WatchNextDoseEntryView(entry: entry)
        }
        .configurationDisplayName("Next Dose")
        .description("Shows your next peptide dose at a glance.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Atlas Score / Health / Training

struct WatchMomentumEntry: TimelineEntry {
    let date: Date
    let score: Int
    let level: Int
    let tier: String
    let progress: Double
    let todayEarned: Int
    let healthDone: Int
    let healthTotal: Int
    let trainingDone: Int
    let trainingTotal: Int

    static let empty = WatchMomentumEntry(
        date: .now, score: 0, level: 1, tier: "bronze", progress: 0,
        todayEarned: 0, healthDone: 0, healthTotal: 0,
        trainingDone: 0, trainingTotal: 0
    )

    static let placeholder = WatchMomentumEntry(
        date: .now, score: 142, level: 4, tier: "gold", progress: 0.6,
        todayEarned: 6, healthDone: 2, healthTotal: 3,
        trainingDone: 1, trainingTotal: 2
    )
}

/// Reads the same `watch_data.json` the dose widget uses — the score +
/// habit-split fields piggyback on the existing sync pipeline.
struct WatchMomentumProvider: TimelineProvider {
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func placeholder(in context: Context) -> WatchMomentumEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (WatchMomentumEntry) -> Void) {
        completion(context.isPreview ? .placeholder : entry(at: .now))
    }

    /// Ends on a midnight entry that clears the day's "+N today" and habit
    /// counts, even when the refresh runs late.
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchMomentumEntry>) -> Void) {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        let next = min(calendar.date(byAdding: .minute, value: 30, to: .now) ?? .now, midnight)
        completion(Timeline(entries: [entry(at: .now), entry(at: midnight)], policy: .after(next)))
    }

    private func entry(at date: Date) -> WatchMomentumEntry {
        guard let url = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
                .appendingPathComponent("watch_data.json"),
              let data = try? Data(contentsOf: url),
              let wd = try? Self.decoder.decode(WatchData.self, from: data).forDisplay(at: date)
        else { return .empty }

        return WatchMomentumEntry(
            date: date,
            score: wd.atlasScore ?? 0,
            level: wd.atlasLevel ?? 1,
            tier: wd.atlasTier ?? "bronze",
            progress: wd.atlasProgress ?? 0,
            todayEarned: wd.atlasTodayEarned ?? 0,
            healthDone: wd.healthHabitsDone ?? 0,
            healthTotal: wd.healthHabitsTotal ?? 0,
            trainingDone: wd.trainingHabitsDone ?? 0,
            trainingTotal: wd.trainingHabitsTotal ?? 0
        )
    }
}

// MARK: Atlas Score views

struct WatchAtlasCircularView: View {
    let entry: WatchMomentumEntry
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Circle()
                .trim(from: 0, to: max(0.001, min(1, entry.progress)))
                .stroke(WatchPalette.tier(entry.tier),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3)
            VStack(spacing: -2) {
                Text("\(entry.score)")
                    .font(.title3.weight(.bold))
                    .widgetAccentable()
                Text("Lv\(entry.level)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct WatchAtlasRectangularView: View {
    let entry: WatchMomentumEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("Atlas · \(entry.tier.capitalized)", systemImage: "bolt.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WatchPalette.tier(entry.tier))
                .labelStyle(.titleAndIcon)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Lv \(entry.level)")
                    .font(.headline)
                    .widgetAccentable()
                Spacer(minLength: 0)
                Text(entry.todayEarned > 0
                     ? "\(entry.score) · +\(entry.todayEarned)"
                     : "\(entry.score) pts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: max(0, min(1, entry.progress)))
                .tint(WatchPalette.tier(entry.tier))
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct WatchAtlasInlineView: View {
    let entry: WatchMomentumEntry
    var body: some View {
        Text("Atlas Lv \(entry.level) · \(entry.score) pts")
    }
}

struct WatchAtlasEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: WatchMomentumEntry
    var body: some View {
        switch family {
        case .accessoryCircular: WatchAtlasCircularView(entry: entry)
        case .accessoryInline:   WatchAtlasInlineView(entry: entry)
        default:                 WatchAtlasRectangularView(entry: entry)
        }
    }
}

struct WatchAtlasScoreWidget: Widget {
    let kind = "WatchAtlasScoreWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchMomentumProvider()) { entry in
            WatchAtlasEntryView(entry: entry)
        }
        .configurationDisplayName("Atlas Score")
        .description("Your Atlas Score, level and tier at a glance.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: Health / Training habit views (shared, color-parameterized)

struct WatchHabitCircularView: View {
    let icon: String
    let tint: Color
    let done: Int
    let total: Int
    private var progress: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if total > 0 {
                Circle()
                    .trim(from: 0, to: max(0.001, progress))
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(3)
            }
            VStack(spacing: -1) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(tint)
                Text(total > 0 ? "\(done)/\(total)" : "—")
                    .font(.system(size: 15, weight: .bold))
                    .widgetAccentable()
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct WatchHabitRectangularView: View {
    let title: String
    let icon: String
    let tint: Color
    let done: Int
    let total: Int
    private var progress: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .labelStyle(.titleAndIcon)
            if total > 0 {
                Text("\(done)/\(total) done")
                    .font(.headline)
                    .widgetAccentable()
                ProgressView(value: progress)
                    .tint(tint)
            } else {
                Text("No habits")
                    .font(.headline)
                Text("scheduled today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct WatchHealthEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: WatchMomentumEntry
    var body: some View {
        switch family {
        case .accessoryCircular:
            WatchHabitCircularView(icon: "heart.fill", tint: WatchPalette.health,
                                   done: entry.healthDone, total: entry.healthTotal)
        case .accessoryInline:
            Text("Health \(entry.healthDone)/\(entry.healthTotal)")
        default:
            WatchHabitRectangularView(title: "Health", icon: "heart.fill",
                                      tint: WatchPalette.health,
                                      done: entry.healthDone, total: entry.healthTotal)
        }
    }
}

struct WatchTrainingEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: WatchMomentumEntry
    var body: some View {
        switch family {
        case .accessoryCircular:
            WatchHabitCircularView(icon: "figure.run", tint: WatchPalette.training,
                                   done: entry.trainingDone, total: entry.trainingTotal)
        case .accessoryInline:
            Text("Training \(entry.trainingDone)/\(entry.trainingTotal)")
        default:
            WatchHabitRectangularView(title: "Training", icon: "figure.run",
                                      tint: WatchPalette.training,
                                      done: entry.trainingDone, total: entry.trainingTotal)
        }
    }
}

struct WatchHealthHabitsWidget: Widget {
    let kind = "WatchHealthHabitsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchMomentumProvider()) { entry in
            WatchHealthEntryView(entry: entry)
        }
        .configurationDisplayName("Health Habits")
        .description("Today's health-habit progress.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct WatchTrainingHabitsWidget: Widget {
    let kind = "WatchTrainingHabitsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchMomentumProvider()) { entry in
            WatchTrainingEntryView(entry: entry)
        }
        .configurationDisplayName("Training Habits")
        .description("Today's training-habit progress.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

@main
struct PeptideWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WatchNextDoseWidget()
        WatchAtlasScoreWidget()
        WatchHealthHabitsWidget()
        WatchTrainingHabitsWidget()
        WatchRecoveryWidget()
        WatchSleepWidget()
        WatchWorkoutWidget()
        WatchNutritionWidget()
    }
}
