import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

/// Flattened for the same reason `DoseEntry` is: the views render, they
/// don't derive. Volumes arrive already converted into `unitSuffix` so
/// no unit maths happens inside a body.
struct TrainingEntry: TimelineEntry {
    let date: Date
    /// Where the running workout's clock counts from: its start shifted
    /// by the time spent paused, so `Text(style: .timer)` agrees with the
    /// app after a pause and resume. Nil when no workout is running.
    let clockStart: Date?
    /// Elapsed seconds frozen at the open pause, or nil while the clock
    /// runs.
    let pausedElapsed: Int?
    let workoutsThisWeek: Int
    let weeklySets: Int
    let weeklyVolume: Double
    let unitSuffix: String
    let week: [TrainingDay]
    let lastName: String
    let lastFinishedAt: Date?
    let lastSets: Int
    let lastVolume: Double
    let lastDurationMinutes: Int

    var isActive: Bool { clockStart != nil }

    /// Nothing to look back on yet — the widget offers the first
    /// workout instead of an empty stat block.
    var hasHistory: Bool { lastFinishedAt != nil }

    /// An unnamed session falls back to the weekday it happened on — the
    /// payload carries "" rather than a second optional.
    var lastTitle: String {
        guard let finished = lastFinishedAt else { return "" }
        return lastName.isEmpty ? finished.formatted(.dateTime.weekday(.wide)) : lastName
    }

    static var empty: TrainingEntry {
        TrainingEntry(
            date: .now, clockStart: nil, pausedElapsed: nil, workoutsThisWeek: 0,
            weeklySets: 0, weeklyVolume: 0, unitSuffix: "kg",
            week: TrainingDay.week(containing: .now, trained: []),
            lastName: "", lastFinishedAt: nil, lastSets: 0, lastVolume: 0,
            lastDurationMinutes: 0
        )
    }

    static var placeholder: TrainingEntry {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let trained = [0, 2, 4]
            .compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
            .filter { $0 <= .now }
        return TrainingEntry(
            date: .now,
            clockStart: nil,
            pausedElapsed: nil,
            workoutsThisWeek: trained.count,
            weeklySets: 42,
            weeklyVolume: 12_480,
            unitSuffix: "kg",
            week: TrainingDay.week(containing: .now, trained: trained),
            lastName: "Push A",
            lastFinishedAt: .now.addingTimeInterval(-86_400),
            lastSets: 16,
            lastVolume: 4_320,
            lastDurationMinutes: 58
        )
    }
}

/// One day of the Monday-to-Sunday strip.
struct TrainingDay: Hashable {
    let date: Date
    let trained: Bool
    let isToday: Bool
    let isFuture: Bool

    /// The seven days of the week containing `now`, in the user's
    /// calendar, each marked against the days a session finished on.
    static func week(
        containing now: Date,
        trained: [Date],
        calendar: Calendar = .current
    ) -> [TrainingDay] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else {
                return nil
            }
            let isToday = calendar.isDate(day, inSameDayAs: now)
            return TrainingDay(
                date: day,
                trained: trained.contains { calendar.isDate($0, inSameDayAs: day) },
                isToday: isToday,
                isFuture: !isToday && day > now
            )
        }
    }
}

// MARK: - Timeline Provider

struct TrainingTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrainingEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (TrainingEntry) -> Void) {
        completion(context.isPreview ? .placeholder : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrainingEntry>) -> Void) {
        let entry = currentEntry()
        // A running workout's timer ticks on its own; the reload is only
        // there to catch the finish, so it stays cheap either way.
        let next = WidgetStore.nextRefresh(after: .now, minutes: entry.isActive ? 15 : 30)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry() -> TrainingEntry {
        guard let data = WidgetStore.load() else { return .empty }
        let last = data.lastWorkout
        // The weekly figures belong to the week the app last wrote them
        // in. Past a Monday with no app launch they would be last week's,
        // so the widget starts the new week at zero instead.
        let sameWeek = Calendar.current.isDate(data.lastUpdated, equalTo: .now, toGranularity: .weekOfYear)
        let start = data.activeWorkoutStart(at: .now)
        var pausedElapsed: Int?
        if let start, let pausedAt = data.activeWorkoutPausedAt {
            pausedElapsed = max(0, Int(pausedAt.timeIntervalSince(start) - data.activeWorkoutPausedSeconds))
        }
        return TrainingEntry(
            date: .now,
            clockStart: start?.addingTimeInterval(data.activeWorkoutPausedSeconds),
            pausedElapsed: pausedElapsed,
            workoutsThisWeek: sameWeek ? data.workoutsThisWeek : 0,
            weeklySets: sameWeek ? data.weeklySetCount : 0,
            weeklyVolume: sameWeek ? data.volumeInUserUnit(data.weeklyVolumeKg) : 0,
            unitSuffix: data.weightSuffix,
            week: TrainingDay.week(containing: .now, trained: sameWeek ? data.trainingDaysThisWeek : []),
            lastName: last?.name ?? "",
            lastFinishedAt: last?.finishedAt,
            lastSets: last?.setCount ?? 0,
            lastVolume: data.volumeInUserUnit(last?.volumeKg ?? 0),
            lastDurationMinutes: last?.durationMinutes ?? 0
        )
    }
}

// MARK: - Pieces

private let trainingTint = WidgetPalette.training
private let trainingGlyph = "figure.strengthtraining.traditional"

private func sessionsWord(_ count: Int) -> LocalizedStringKey {
    count == 1 ? "session" : "sessions"
}

/// Monday to Sunday, a dot per day: filled where a session finished,
/// ringed for today, faded for days still to come. The week's rhythm at
/// a glance, which a count alone can't show.
private struct WeekStrip: View {
    let days: [TrainingDay]
    var showsLetters = true
    var dot: CGFloat = 12

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.date) { day in
                VStack(spacing: 3) {
                    Circle()
                        .fill(day.trained ? trainingTint : WidgetPalette.track)
                        .overlay {
                            if day.isToday && !day.trained {
                                Circle().strokeBorder(trainingTint, lineWidth: 1.5)
                            }
                        }
                        .frame(width: dot, height: dot)
                        .opacity(day.isFuture ? 0.5 : 1)
                        .widgetAccentable(day.trained || day.isToday)
                    if showsLetters {
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(day.isToday ? .bold : .medium))
                            .foregroundStyle(day.isToday ? .primary : .secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Trained \(days.filter(\.trained).count) of 7 days this week"))
    }
}

/// The running workout's clock, or the frozen time while it's paused —
/// matching the Live Activity instead of ticking on past it.
private struct WorkoutClock: View {
    let entry: TrainingEntry
    let font: Font

    var body: some View {
        Group {
            if let paused = entry.pausedElapsed {
                Text(Self.frozenTime(paused))
            } else if let start = entry.clockStart {
                Text(start, style: .timer)
            }
        }
        .font(font)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    /// H:MM:SS from the first hour on, M:SS before it, like the running timer.
    static func frozenTime(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(
            .time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond)
        )
    }
}

private struct ActiveWorkoutBlock: View {
    let entry: TrainingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WorkoutClock(entry: entry, font: .system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(entry.pausedElapsed == nil ? trainingTint : Color.secondary)
                .widgetAccentable()
            Label(
                entry.pausedElapsed == nil ? LocalizedStringKey("In progress") : "Paused",
                systemImage: entry.pausedElapsed == nil ? "record.circle" : "pause.circle.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
    }
}

private struct SessionCount: View {
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(count)")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(trainingTint)
                .contentTransition(.numericText(value: Double(count)))
                .widgetAccentable()
            Text(sessionsWord(count))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }
}

/// A user with history but nothing yet this week: point back at the last
/// session instead of a large blue zero.
private struct FreshWeekBlock: View {
    let entry: TrainingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Fresh week")
                .font(.headline)
            if let finished = entry.lastFinishedAt {
                Text("Last: \(entry.lastTitle), \(finished.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct FirstWorkoutPrompt: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "dumbbell.fill")
                .font(.title2)
                .foregroundStyle(trainingTint)
                .widgetAccentable()
            Text("No workouts yet")
                .font(.headline)
            Text("Tap to start your first session.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StatPair: View {
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private func header(_ entry: TrainingEntry) -> WidgetHeader {
    WidgetHeader(
        glyph: trainingGlyph,
        title: entry.isActive ? "Workout" : "This week",
        tint: trainingTint
    )
}

// MARK: - Home screen

private struct SmallTrainingView: View {
    let entry: TrainingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(entry)
            Spacer(minLength: 6)
            if entry.isActive {
                ActiveWorkoutBlock(entry: entry)
                Spacer(minLength: 0)
            } else if !entry.hasHistory {
                FirstWorkoutPrompt()
                Spacer(minLength: 0)
            } else {
                if entry.workoutsThisWeek == 0 {
                    FreshWeekBlock(entry: entry)
                } else {
                    SessionCount(count: entry.workoutsThisWeek)
                }
                Spacer(minLength: 6)
                WeekStrip(days: entry.week)
            }
        }
        .widgetBackdrop(trainingTint)
    }
}

private struct MediumTrainingView: View {
    let entry: TrainingEntry

    var body: some View {
        Group {
            if !entry.isActive && !entry.hasHistory {
                // One empty state across the full width, not two half
                // ones next to a "0 sessions" column.
                VStack(alignment: .leading, spacing: 0) {
                    header(entry)
                    Spacer(minLength: 0)
                    FirstWorkoutPrompt()
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 16) {
                    weekColumn
                    Divider()
                    lastWorkoutColumn
                }
            }
        }
        .widgetBackdrop(trainingTint)
    }

    private var weekColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(entry)
            Spacer(minLength: 6)
            if entry.isActive {
                ActiveWorkoutBlock(entry: entry)
            } else if entry.workoutsThisWeek == 0 {
                FreshWeekBlock(entry: entry)
            } else {
                SessionCount(count: entry.workoutsThisWeek)
                Text("\(entry.weeklySets) sets · \(WidgetFormat.volume(entry.weeklyVolume, suffix: entry.unitSuffix))")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            WeekStrip(days: entry.week)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lastWorkoutColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Last workout")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)
            if let finished = entry.lastFinishedAt {
                Text(entry.lastTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(finished.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 10) {
                    StatPair(value: "\(entry.lastSets)", label: "sets")
                    StatPair(value: WidgetFormat.duration(minutes: entry.lastDurationMinutes), label: "time")
                    StatPair(value: WidgetFormat.volume(entry.lastVolume, suffix: entry.unitSuffix), label: "volume")
                }
            } else {
                Text("Your first finished session lands here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Lock screen

private struct CircularTrainingView: View {
    let entry: TrainingEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: entry.pausedElapsed == nil ? trainingGlyph : "pause.fill")
                    .font(.caption)
                    .accessibilityHidden(true)
                if entry.isActive {
                    WorkoutClock(entry: entry, font: .caption.weight(.bold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                } else {
                    Text("\(entry.workoutsThisWeek)")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .contentTransition(.numericText(value: Double(entry.workoutsThisWeek)))
                        .accessibilityLabel(Text("\(entry.workoutsThisWeek) workouts this week"))
                }
            }
            .widgetAccentable()
        }
    }
}

private struct RectangularTrainingView: View {
    let entry: TrainingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(headline, systemImage: entry.pausedElapsed == nil ? trainingGlyph : "pause.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .widgetAccentable()
            if entry.isActive {
                WorkoutClock(entry: entry, font: .headline)
            } else {
                Text("^[\(entry.workoutsThisWeek) session](inflect: true)")
                    .font(.headline)
                WeekStrip(days: entry.week, showsLetters: false, dot: 8)
            }
        }
        .lineLimit(1)
    }

    private var headline: LocalizedStringKey {
        guard entry.isActive else { return "This week" }
        return entry.pausedElapsed == nil ? "Workout" : "Paused"
    }
}

private struct InlineTrainingView: View {
    let entry: TrainingEntry

    var body: some View {
        if entry.isActive {
            Label {
                if let paused = entry.pausedElapsed {
                    Text("Paused at \(WorkoutClock.frozenTime(paused))")
                } else if let start = entry.clockStart {
                    Text("Workout \(Text(start, style: .timer))")
                }
            } icon: {
                Image(systemName: trainingGlyph)
            }
        } else {
            Label("^[\(entry.workoutsThisWeek) session](inflect: true) this week", systemImage: trainingGlyph)
        }
    }
}

// MARK: - Widget

struct TrainingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TrainingEntry

    var body: some View {
        switch family {
        case .systemMedium: MediumTrainingView(entry: entry)
        case .accessoryCircular: CircularTrainingView(entry: entry).accessoryBackdrop()
        case .accessoryRectangular: RectangularTrainingView(entry: entry).accessoryBackdrop()
        case .accessoryInline: InlineTrainingView(entry: entry).accessoryBackdrop()
        default: SmallTrainingView(entry: entry)
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
        .description("Your week at a glance, your last workout, and a live timer while you train.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}
