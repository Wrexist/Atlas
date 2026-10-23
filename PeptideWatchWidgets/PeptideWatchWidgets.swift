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
    /// The last push is from an earlier day, so today's doses are unknown
    /// rather than none.
    var awaitsToday = false

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
        // Nothing shown changes with the clock before midnight; new data
        // reloads the timeline from `WatchStore.apply`. The midnight entry
        // empties the day even when the refresh runs late.
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        completion(Timeline(entries: [entry(at: .now), entry(at: midnight)], policy: .after(midnight)))
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
            totalToday: watchData.totalToday,
            awaitsToday: watchData.awaitsToday(at: date)
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
            if entry.nextPeptide.isEmpty {
                Text(entry.awaitsToday ? String(localized: "Open Atlas on iPhone")
                     : entry.totalToday == 0 ? String(localized: "No doses today")
                     : String(localized: "All complete"))
                    .font(.caption2)
                    .lineLimit(1)
            } else {
                // Dosing is health information: redacted on a lowered
                // wrist and while the watch is locked.
                Text(entry.nextDose.isEmpty ? entry.nextPeptide : "\(entry.nextPeptide) · \(entry.nextDose)")
                    .font(.caption2)
                    .lineLimit(1)
                    .privacySensitive()
            }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var spoken: String {
        entry.awaitsToday ? String(localized: "Open Atlas on iPhone")
            : entry.totalToday == 0
            ? String(localized: "No doses today")
            : String(localized: "\(entry.completedToday) of \(entry.totalToday) doses taken")
    }
}

struct WatchAccessoryInlineView: View {
    let entry: WatchDoseEntry

    var body: some View {
        if let time = entry.nextDoseTime, !entry.nextPeptide.isEmpty {
            Text("\(entry.nextPeptide) · \(time.formatted(.dateTime.hour().minute()))")
                .privacySensitive()
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
                .widgetURL(WatchPage.protocols.url)
        }
        .configurationDisplayName("Next Dose")
        .description("Shows your next peptide dose at a glance.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Atlas Score / Health / Training

struct WatchMomentumEntry: TimelineEntry {
    let date: Date
    /// False until the phone has written `watch_data.json`, so the zeros
    /// below aren't shown as the user's real score and habits.
    var synced = true
    let score: Int
    let level: Int
    let tier: String
    let progress: Double
    let todayEarned: Int
    let healthDone: Int
    let healthTotal: Int
    let trainingDone: Int
    let trainingTotal: Int
    /// The last push is from an earlier day: the score still stands, but
    /// today's habits are unknown until the phone pushes again.
    var awaitsToday = false

    /// Whether the habit complications have today's counts to show.
    var habitsKnown: Bool { synced && !awaitsToday }

    static func unsynced(at date: Date) -> WatchMomentumEntry {
        WatchMomentumEntry(
            date: date, synced: false, score: 0, level: 1, tier: "bronze", progress: 0,
            todayEarned: 0, healthDone: 0, healthTotal: 0,
            trainingDone: 0, trainingTotal: 0
        )
    }

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
    /// counts, even when the refresh runs late. New data reloads the
    /// timeline from `WatchStore.apply`, so there is no polling before then.
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchMomentumEntry>) -> Void) {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        completion(Timeline(entries: [entry(at: .now), entry(at: midnight)], policy: .after(midnight)))
    }

    private func entry(at date: Date) -> WatchMomentumEntry {
        guard let url = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
                .appendingPathComponent("watch_data.json"),
              let data = try? Data(contentsOf: url),
              let wd = try? Self.decoder.decode(WatchData.self, from: data).forDisplay(at: date)
        else { return .unsynced(at: date) }

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
            trainingTotal: wd.trainingHabitsTotal ?? 0,
            awaitsToday: wd.awaitsToday(at: date)
        )
    }
}

// MARK: Atlas Score views

struct WatchAtlasCircularView: View {
    let entry: WatchMomentumEntry
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.synced {
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
                    Text("Lv \(entry.level)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "bolt.fill")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.synced
                            ? String(localized: "Atlas Score \(entry.score), level \(entry.level)")
                            : String(localized: "Open Atlas on iPhone"))
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct WatchAtlasRectangularView: View {
    let entry: WatchMomentumEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(entry.synced ? String(localized: "Atlas · \(WatchFormat.tierName(entry.tier))") : String(localized: "Atlas"),
                  systemImage: "bolt.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WatchPalette.tier(entry.tier))
                .labelStyle(.titleAndIcon)
            if entry.synced {
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
            } else {
                Text("Open Atlas on iPhone")
                    .font(.headline)
                    .lineLimit(2)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct WatchAtlasInlineView: View {
    let entry: WatchMomentumEntry
    var body: some View {
        Text(entry.synced
             ? String(localized: "Atlas Lv \(entry.level) · \(entry.score) pts")
             : String(localized: "Atlas —"))
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
                .widgetURL(WatchPage.today.url)
        }
        .configurationDisplayName("Atlas Score")
        .description("Your Atlas Score, level and tier at a glance.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: Health / Training habit views (shared, color-parameterized)

struct WatchHabitCircularView: View {
    let title: String
    let icon: String
    let tint: Color
    let known: Bool
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .containerBackground(for: .widget) { Color.clear }
    }

    /// Matches the Today page's stat wording.
    private var spoken: String {
        !known ? String(localized: "\(title), open Atlas on iPhone")
            : total > 0 ? String(localized: "\(title), \(done) of \(total) done")
            : String(localized: "\(title), no habits today")
    }
}

struct WatchHabitRectangularView: View {
    let title: String
    let icon: String
    let tint: Color
    let synced: Bool
    let done: Int
    let total: Int
    private var progress: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .labelStyle(.titleAndIcon)
            if !synced {
                Text("Open Atlas on iPhone")
                    .font(.headline)
                    .lineLimit(2)
            } else if total > 0 {
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
            WatchHabitCircularView(title: String(localized: "Health"), icon: "heart.fill",
                                   tint: WatchPalette.health, known: entry.habitsKnown,
                                   done: entry.healthDone, total: entry.healthTotal)
        case .accessoryInline:
            Text(entry.healthTotal > 0
                 ? String(localized: "Health \(entry.healthDone)/\(entry.healthTotal)")
                 : String(localized: "Health —"))
        default:
            WatchHabitRectangularView(title: String(localized: "Health"), icon: "heart.fill",
                                      tint: WatchPalette.health, synced: entry.habitsKnown,
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
            WatchHabitCircularView(title: String(localized: "Training"), icon: "figure.run",
                                   tint: WatchPalette.training, known: entry.habitsKnown,
                                   done: entry.trainingDone, total: entry.trainingTotal)
        case .accessoryInline:
            Text(entry.trainingTotal > 0
                 ? String(localized: "Training \(entry.trainingDone)/\(entry.trainingTotal)")
                 : String(localized: "Training —"))
        default:
            WatchHabitRectangularView(title: String(localized: "Training"), icon: "figure.run",
                                      tint: WatchPalette.training, synced: entry.habitsKnown,
                                      done: entry.trainingDone, total: entry.trainingTotal)
        }
    }
}

struct WatchHealthHabitsWidget: Widget {
    let kind = "WatchHealthHabitsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchMomentumProvider()) { entry in
            WatchHealthEntryView(entry: entry)
                .widgetURL(WatchPage.today.url)
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
                .widgetURL(WatchPage.today.url)
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
