import OSLog
import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct FastingEntry: TimelineEntry {
    let date: Date
    /// The open fast, or nil when the user isn't fasting.
    let active: FastingWidgetSnapshot.Active?
    /// The snapshot couldn't be read: the views draw redacted, not empty.
    var isUnavailable = false

    static func notFasting(at date: Date) -> FastingEntry {
        FastingEntry(date: date, active: nil)
    }

    static var placeholder: FastingEntry {
        let start = Date.now.addingTimeInterval(-11.5 * 3600)
        return FastingEntry(
            date: .now,
            active: FastingWidgetSnapshot.Active(
                fastId: UUID(),
                window: FastingWindow(startedAt: start, targetEnd: start.addingTimeInterval(16 * 3600)),
                protocolName: "16:8"
            )
        )
    }
}

// MARK: - Timeline Provider

struct FastingTimelineProvider: TimelineProvider {
    private static let log = Logger(subsystem: "com.peptidesai.app", category: "FastingWidget")

    func placeholder(in context: Context) -> FastingEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (FastingEntry) -> Void) {
        guard !context.isPreview else { return completion(.placeholder) }
        let now = Date.now
        switch Self.load() {
        case .loaded(let snapshot): completion(FastingEntry(date: now, active: snapshot.active))
        case .missing: completion(.notFasting(at: now))
        case .unreadable: completion(Self.unavailable(at: now))
        }
    }

    /// The clocks tick on their own; the entries move the progress bar
    /// and the gauge's minutes, and flip the widget to "Goal reached" on
    /// time. The app reloads
    /// this widget on every start and end, so the reload policy is only
    /// a backstop.
    func getTimeline(in context: Context, completion: @escaping (Timeline<FastingEntry>) -> Void) {
        let now = Date.now
        switch Self.load() {
        case .loaded(let snapshot):
            guard let active = snapshot.active else {
                return completion(Timeline(entries: [.notFasting(at: now)], policy: .never))
            }
            let entries = active.window.timelineDates(from: now).map { FastingEntry(date: $0, active: active) }
            completion(Timeline(entries: entries, policy: .atEnd))
        case .missing:
            completion(Timeline(entries: [.notFasting(at: now)], policy: .never))
        case .unreadable:
            let retry = now.addingTimeInterval(TimeInterval(WidgetStore.unreadableRetryMinutes * 60))
            completion(Timeline(entries: [Self.unavailable(at: now)], policy: .after(retry)))
        }
    }

    private static func unavailable(at date: Date) -> FastingEntry {
        var entry = FastingEntry.placeholder
        entry.isUnavailable = true
        return entry
    }

    private enum LoadResult {
        case loaded(FastingWidgetSnapshot)
        /// The app hasn't written one yet — never fasted on this build.
        case missing
        /// Still protected before first unlock, or no longer decodes.
        case unreadable
    }

    private static func load() -> LoadResult {
        guard let url = FastingWidgetSnapshot.fileURL else {
            log.error("App Group container unavailable; fasting snapshot unreadable")
            return .unreadable
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            return .loaded(try FastingWidgetSnapshot.decoded(from: Data(contentsOf: url)))
        } catch {
            log.error("fasting snapshot unreadable: \(error.localizedDescription, privacy: .public)")
            return .unreadable
        }
    }
}

// MARK: - Pieces

private let fastingTint = WidgetPalette.brand
private let fastingGlyph = "moon.zzz.fill"

private extension FastingEntry {
    var goalReached: Bool { active?.window.isGoalReached(at: date) ?? false }
    var tint: Color { goalReached ? WidgetPalette.done : fastingTint }
}

/// Time fasted, counting up on its own.
private struct ElapsedClock: View {
    let window: FastingWindow
    let font: Font

    var body: some View {
        Text(timerInterval: window.elapsedInterval, countsDown: false)
            .font(font)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// "3:12:40 left" while short of the goal, "Goal reached" after it.
private struct RemainingLine: View {
    let entry: FastingEntry
    let window: FastingWindow

    var body: some View {
        if entry.goalReached {
            Label("Goal reached", systemImage: "checkmark.seal.fill")
                .foregroundStyle(entry.tint)
        } else {
            Text("\(Text(timerInterval: window.countdownInterval(from: entry.date), countsDown: true)) left")
                .monospacedDigit()
        }
    }
}

private struct NotFastingPrompt: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: fastingGlyph)
                .font(.title2)
                .foregroundStyle(fastingTint)
                .widgetAccentable()
            Text("Not fasting")
                .font(.headline)
            Text("Tap to start a fast.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Home screen

private struct SmallFastingView: View {
    let entry: FastingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(glyph: fastingGlyph, title: "Fasting", tint: entry.tint, trailing: entry.active?.protocolName)
            Spacer(minLength: 6)
            if let active = entry.active {
                ElapsedClock(window: active.window, font: .system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(entry.tint)
                    .widgetAccentable()
                RemainingLine(entry: entry, window: active.window)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                WidgetBar(progress: active.window.progress(at: entry.date), tint: entry.tint, height: 6)
                Text("Goal at \(active.window.targetEnd.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 4)
            } else {
                NotFastingPrompt()
                Spacer(minLength: 0)
            }
        }
        .widgetBackdrop(entry.tint)
    }
}

// MARK: - Lock screen

private struct CircularFastingView: View {
    let entry: FastingEntry

    var body: some View {
        if let active = entry.active {
            Gauge(value: active.window.progress(at: entry.date)) {
                Image(systemName: fastingGlyph)
            } currentValueLabel: {
                Text(WidgetFormat.duration(minutes: Int(active.window.elapsed(at: entry.date) / 60)))
                    .minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .accessibilityLabel(Text("Fasting"))
            .accessibilityValue(Text(WidgetFormat.spokenDuration(minutes: Int(active.window.elapsed(at: entry.date) / 60))))
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: fastingGlyph)
                    .font(.title3)
                    .widgetAccentable()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Not fasting"))
        }
    }
}

private struct RectangularFastingView: View {
    let entry: FastingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(entry.active == nil ? LocalizedStringKey("Not fasting") : "Fasting", systemImage: fastingGlyph)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .widgetAccentable()
            if let active = entry.active {
                ElapsedClock(window: active.window, font: .headline)
                RemainingLine(entry: entry, window: active.window)
                    .font(.caption)
            } else {
                Text("Tap to start a fast.")
                    .font(.caption)
            }
        }
        .lineLimit(1)
    }
}

private struct InlineFastingView: View {
    let entry: FastingEntry

    var body: some View {
        if let active = entry.active {
            Label {
                Text("Fasting \(Text(timerInterval: active.window.elapsedInterval, countsDown: false))")
            } icon: {
                Image(systemName: fastingGlyph)
            }
        } else {
            Label("Not fasting", systemImage: fastingGlyph)
        }
    }
}

// MARK: - Widget

struct FastingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FastingEntry

    var body: some View {
        switch family {
        case .accessoryCircular: CircularFastingView(entry: entry).accessoryBackdrop()
        case .accessoryRectangular: RectangularFastingView(entry: entry).accessoryBackdrop()
        case .accessoryInline: InlineFastingView(entry: entry).accessoryBackdrop()
        default: SmallFastingView(entry: entry)
        }
    }
}

struct FastingWidget: Widget {
    let kind = FastingWidgetSnapshot.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FastingTimelineProvider()) { entry in
            FastingWidgetView(entry: entry)
                .redacted(reason: entry.isUnavailable ? .placeholder : [])
                .widgetURL(WidgetDeepLink.meals)
        }
        .configurationDisplayName("Fasting")
        .description("Your current fast: time fasted, time left and your goal.")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}
