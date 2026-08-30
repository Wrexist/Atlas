import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

/// Flattened for the same reason `DoseEntry` is: the views render, they
/// don't derive. Volumes arrive already converted into `unitSuffix` so
/// no unit maths happens inside a body.
struct TrainingEntry: TimelineEntry {
    let date: Date
    /// Start of the workout in progress, or nil when none is.
    let activeSince: Date?
    let workoutsThisWeek: Int
    let weeklySets: Int
    let weeklyVolume: Double
    let unitSuffix: String
    let lastName: String
    let lastFinishedAt: Date?
    let lastSets: Int
    let lastVolume: Double
    let lastDurationMinutes: Int

    /// Nothing to look back on yet — the widget offers the first
    /// workout instead of an empty stat block.
    var hasHistory: Bool { lastFinishedAt != nil }

    static let empty = TrainingEntry(
        date: .now, activeSince: nil, workoutsThisWeek: 0, weeklySets: 0,
        weeklyVolume: 0, unitSuffix: "kg", lastName: "", lastFinishedAt: nil,
        lastSets: 0, lastVolume: 0, lastDurationMinutes: 0
    )

    static let placeholder = TrainingEntry(
        date: .now,
        activeSince: nil,
        workoutsThisWeek: 3,
        weeklySets: 42,
        weeklyVolume: 12_480,
        unitSuffix: "kg",
        lastName: "Push A",
        lastFinishedAt: .now.addingTimeInterval(-86_400),
        lastSets: 16,
        lastVolume: 4_320,
        lastDurationMinutes: 58
    )
}

// MARK: - Timeline Provider

struct TrainingTimelineProvider: TimelineProvider {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func placeholder(in context: Context) -> TrainingEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (TrainingEntry) -> Void) {
        completion(context.isPreview ? .placeholder : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrainingEntry>) -> Void) {
        let entry = currentEntry()
        let calendar = Calendar.current
        // Midnight always, so a finished session stops reading as
        // "today" and a new week's counters start from zero.
        let midnight = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        // A running workout renders its elapsed time with
        // `Text(style: .timer)`, which ticks on its own — the reload is
        // only there to catch the finish, so it stays cheap either way.
        let cadence = entry.activeSince == nil ? 30 : 15
        let next = calendar.date(byAdding: .minute, value: cadence, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(min(next, midnight))))
    }

    private func currentEntry() -> TrainingEntry {
        guard let data = loadWidgetData() else { return .empty }
        let last = data.lastWorkout
        return TrainingEntry(
            date: .now,
            activeSince: data.activeWorkoutStartedAt,
            workoutsThisWeek: data.workoutsThisWeek,
            weeklySets: data.weeklySetCount,
            weeklyVolume: data.volumeInUserUnit(data.weeklyVolumeKg),
            unitSuffix: data.weightSuffix,
            lastName: last?.name ?? "",
            lastFinishedAt: last?.finishedAt,
            lastSets: last?.setCount ?? 0,
            lastVolume: data.volumeInUserUnit(last?.volumeKg ?? 0),
            lastDurationMinutes: last?.durationMinutes ?? 0
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

// MARK: - Shared pieces

/// Brand blue for training, matching the Watch complications'
/// `WatchScoreColor.training`. The widget extension can't import the
/// app module, so the value is reproduced rather than tokenised.
private let trainingTint = Color(red: 0.216, green: 0.541, blue: 0.867)

/// Volume reads as a count, not a measurement — nobody needs the
/// decimal on 12,480 kg lifted.
private func volumeLabel(_ value: Double, suffix: String) -> String {
    "\(Int(value.rounded()).formatted()) \(suffix)"
}

private struct TrainingHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(trainingTint)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

/// Elapsed time of the running workout. `Text(style: .timer)` counts up
/// from the start date without the extension being woken per second.
private struct ActiveWorkoutBlock: View {
    let since: Date
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(since, style: .timer)
                .font(.system(size: compact ? 26 : 30, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(trainingTint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("Workout in progress")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct StatPair: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 15, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Small

struct SmallTrainingView: View {
    let entry: TrainingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TrainingHeader(title: entry.activeSince == nil ? "This week" : "Training")

            Spacer(minLength: 0)

            if let since = entry.activeSince {
                ActiveWorkoutBlock(since: since, compact: true)
            } else if entry.hasHistory {
                weekSummary
            } else {
                firstWorkoutPrompt
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var weekSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(entry.workoutsThisWeek)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(trainingTint)
                Text(entry.workoutsThisWeek == 1 ? "session" : "sessions")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(volumeLabel(entry.weeklyVolume, suffix: entry.unitSuffix))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let finished = entry.lastFinishedAt {
                Text("Last \(finished.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var firstWorkoutPrompt: some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 22))
                .foregroundStyle(trainingTint)
            Text("No workouts yet")
                .font(.system(size: 14, weight: .semibold))
            Text("Tap to start one")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Medium

struct MediumTrainingView: View {
    let entry: TrainingEntry

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                TrainingHeader(title: entry.activeSince == nil ? "This week" : "Training")

                if let since = entry.activeSince {
                    ActiveWorkoutBlock(since: since, compact: false)
                    Spacer(minLength: 0)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(entry.workoutsThisWeek)")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(trainingTint)
                        Text(entry.workoutsThisWeek == 1 ? "session" : "sessions")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 12) {
                        StatPair(value: "\(entry.weeklySets)", label: "sets")
                        StatPair(
                            value: volumeLabel(entry.weeklyVolume, suffix: entry.unitSuffix),
                            label: "volume"
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            lastWorkoutColumn
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var lastWorkoutColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last workout")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let finished = entry.lastFinishedAt {
                // An unnamed session falls back to when it happened —
                // the payload carries "" rather than a second optional.
                Text(entry.lastName.isEmpty
                     ? finished.formatted(.dateTime.weekday(.wide))
                     : entry.lastName)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(finished.formatted(.relative(presentation: .named)))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    StatPair(value: "\(entry.lastSets)", label: "sets")
                    StatPair(value: "\(entry.lastDurationMinutes)m", label: "time")
                }
                Text(volumeLabel(entry.lastVolume, suffix: entry.unitSuffix))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Nothing logged yet")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Your first session lands here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Widget

struct TrainingWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: TrainingEntry

    var body: some View {
        switch family {
        case .systemMedium:
            MediumTrainingView(entry: entry)
        default:
            SmallTrainingView(entry: entry)
        }
    }
}

struct TrainingWidget: Widget {
    let kind = "TrainingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrainingTimelineProvider()) { entry in
            TrainingWidgetView(entry: entry)
                .widgetURL(WidgetDeepLink.train)
        }
        .configurationDisplayName("Training")
        .description("This week's sessions, and your last workout.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
