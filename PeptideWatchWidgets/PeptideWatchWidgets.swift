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
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchDoseEntry>) -> Void) {
        let entry = currentEntry()
        let calendar = Calendar.current
        // Refresh at the next dose time, otherwise every 15 minutes, otherwise
        // at midnight.
        let midnight = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        let fifteenMin = calendar.date(byAdding: .minute, value: 15, to: .now) ?? .now
        let nextUpdate: Date
        if let doseDate = entry.nextDoseTime, doseDate > .now, doseDate <= fifteenMin {
            nextUpdate = min(doseDate.addingTimeInterval(60), midnight)
        } else {
            nextUpdate = min(fifteenMin, midnight)
        }
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    /// Reads the same `watch_data.json` the watch app already syncs to via
    /// `WatchSyncService` — the widget surface piggybacks on the existing
    /// pipeline, no new sync code required.
    private func currentEntry() -> WatchDoseEntry {
        guard let url = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
                .appendingPathComponent("watch_data.json"),
              let data = try? Data(contentsOf: url),
              let watchData = try? Self.decoder.decode(WatchData.self, from: data)
        else {
            return WatchDoseEntry(
                date: .now, nextPeptide: "", nextDose: "",
                nextDoseTime: nil, completedToday: 0, totalToday: 0
            )
        }

        let next = watchData.todayEntries.first { !$0.completed }

        return WatchDoseEntry(
            date: .now,
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
            Text("PeptideX")
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

@main
struct PeptideWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WatchNextDoseWidget()
    }
}
