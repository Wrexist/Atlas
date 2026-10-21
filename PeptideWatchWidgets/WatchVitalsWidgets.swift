import SwiftUI
import WidgetKit

// MARK: - Provider

struct WatchVitalsEntry: TimelineEntry {
    let date: Date
    let vitals: WatchVitalsSnapshot?

    static let placeholder = WatchVitalsEntry(
        date: .now,
        vitals: WatchVitalsSnapshot(
            recoveryScore: 82,
            restingHeartRate: 56,
            restingHeartRateBaseline: 58,
            hrv: 64,
            hrvBaseline: 59,
            sleep: WatchSleepSnapshot(
                score: 84,
                start: .now.addingTimeInterval(-8 * 3600),
                end: .now.addingTimeInterval(-30 * 60),
                deepMinutes: 72,
                coreMinutes: 236,
                remMinutes: 104,
                unspecifiedMinutes: 0,
                awakeMinutes: 18
            ),
            measuredAt: .now
        )
    )
}

/// Reads the vitals the Watch app mirrors into `watch_data.json`. The
/// phone recomputes them on each app activation, so an hourly refresh
/// is plenty to pick up a new snapshot.
struct WatchVitalsProvider: TimelineProvider {
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func placeholder(in context: Context) -> WatchVitalsEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (WatchVitalsEntry) -> Void) {
        completion(context.isPreview ? .placeholder : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchVitalsEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [currentEntry()], policy: .after(next)))
    }

    private func currentEntry() -> WatchVitalsEntry {
        guard let url = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
                .appendingPathComponent("watch_data.json"),
              let data = try? Data(contentsOf: url),
              let watchData = try? Self.decoder.decode(WatchData.self, from: data).forDisplay(at: .now)
        else { return WatchVitalsEntry(date: .now, vitals: nil) }
        return WatchVitalsEntry(date: .now, vitals: watchData.vitals)
    }
}

// MARK: - Recovery

struct WatchRecoveryEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchVitalsEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: rectangular
        }
    }

    private var vitals: WatchVitalsSnapshot? { entry.vitals }

    private var circular: some View {
        Gauge(value: Double(vitals?.recoveryScore ?? 0), in: 0...100) {
            Image(systemName: "heart.fill")
        } currentValueLabel: {
            Text(vitals?.recoveryScore.map { "\($0)" } ?? "—")
                .widgetAccentable()
        }
        .gaugeStyle(.accessoryCircular)
        .tint(WatchPalette.heart)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Recovery", systemImage: "heart.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WatchPalette.heart)
            if let vitals {
                Text(vitals.recoveryScore.map { "\($0)" } ?? "—")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .widgetAccentable()
                Text(detail(vitals))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Connect Apple Health in Atlas")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var inline: some View {
        Label(
            vitals?.recoveryScore.map { String(localized: "Recovery \($0)") } ?? String(localized: "Recovery —"),
            systemImage: "heart.fill"
        )
        .containerBackground(for: .widget) { Color.clear }
    }

    private func detail(_ vitals: WatchVitalsSnapshot) -> String {
        [
            vitals.restingHeartRate.map { String(localized: "\($0) bpm") },
            vitals.hrv.map { String(localized: "HRV \($0) ms") },
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

struct WatchRecoveryWidget: Widget {
    let kind = "WatchRecoveryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchVitalsProvider()) { entry in
            WatchRecoveryEntryView(entry: entry)
                .widgetURL(WatchPage.recovery.url)
        }
        .configurationDisplayName("Recovery")
        .description("Your Recovery score, resting heart rate and HRV.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Sleep

struct WatchSleepEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchVitalsEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: rectangular
        }
    }

    private var sleep: WatchSleepSnapshot? { entry.vitals?.sleep }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let sleep {
                SleepStageRing(slices: sleep.slices, lineWidth: 5)
                    .padding(2)
                Text("\(sleep.score)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .widgetAccentable()
            } else {
                Image(systemName: "bed.double.fill")
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Sleep Score", systemImage: "bed.double.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WatchPalette.sleepAccent)
            if let sleep {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(sleep.score)")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .widgetAccentable()
                    Text(sleep.band.label)
                        .font(.caption.weight(.semibold))
                }
                Text("\(WatchFormat.duration(minutes: sleep.asleepMinutes)) asleep")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("No sleep recorded last night")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var inline: some View {
        Label(
            sleep.map { String(localized: "Sleep \($0.score) · \(WatchFormat.duration(minutes: $0.asleepMinutes))") }
                ?? String(localized: "Sleep —"),
            systemImage: "bed.double.fill"
        )
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct WatchSleepWidget: Widget {
    let kind = "WatchSleepWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchVitalsProvider()) { entry in
            WatchSleepEntryView(entry: entry)
                .widgetURL(WatchPage.sleep.url)
        }
        .configurationDisplayName("Sleep Score")
        .description("Last night's Sleep Score and time asleep.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
