import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct DoseEntry: TimelineEntry {
    let date: Date
    let peptideName: String
    let dose: String
    let nextDoseDate: Date?
    let completed: Int
    let total: Int
    let compliance: Double
    let upcoming: [WidgetDoseSlot]
    /// The payload was written on an earlier day. Its doses and progress
    /// are yesterday's, and today's schedule isn't known until the app
    /// writes it, so the views show a neutral prompt instead.
    var isOutdated = false
    /// A protocol is active, whether or not it doses today.
    var hasActiveProtocol = false
    /// The payload couldn't be read (still protected before the first
    /// unlock, or undecodable): the views draw redacted, not empty.
    var isUnavailable = false

    /// Doses are scheduled today.
    var hasProtocol: Bool { total > 0 }
    /// A protocol is running but has nothing on today, such as the rest
    /// day of a three-times-a-week schedule.
    var isRestDay: Bool { !hasProtocol && hasActiveProtocol }
    var allDone: Bool { hasProtocol && peptideName.isEmpty }
    /// The next dose's time has passed without it being logged.
    var isOverdue: Bool { nextDoseDate.map { date >= $0 } ?? false }

    /// "2/4" for a header; nil with no doses today.
    var doseCount: String? { hasProtocol ? "\(completed)/\(total)" : nil }
    /// The same count as it should be spoken.
    var spokenDoseCount: Text { Text("\(completed) of \(total) doses logged") }

    static let empty = DoseEntry(
        date: .now, peptideName: "", dose: "", nextDoseDate: nil,
        completed: 0, total: 0, compliance: 0, upcoming: []
    )

    /// Gallery preview. Neutral supplements, since this is the first
    /// thing someone browsing a fitness app's widgets sees.
    static let placeholder = DoseEntry(
        date: .now,
        peptideName: "Vitamin D",
        dose: "2000 IU",
        nextDoseDate: .now.addingTimeInterval(3600),
        completed: 2,
        total: 4,
        compliance: 0.5,
        upcoming: [
            WidgetDoseSlot(peptideName: "Creatine", dose: "5 g", time: .now.addingTimeInterval(-7200), completed: true),
            WidgetDoseSlot(peptideName: "Vitamin D", dose: "2000 IU", time: .now.addingTimeInterval(3600), completed: false),
            WidgetDoseSlot(peptideName: "Magnesium", dose: "400 mg", time: .now.addingTimeInterval(10_800), completed: false),
        ]
    )
}

// MARK: - Timeline Provider

struct DoseTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DoseEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (DoseEntry) -> Void) {
        completion(context.isPreview ? .placeholder : entry(from: WidgetStore.load(), at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DoseEntry>) -> Void) {
        let now = Date.now
        let payload = WidgetStore.load()
        let next = payload.reloadDate(after: now)
        var entries = [entry(from: payload, at: now)]
        if payload.isLoaded {
            // An imminent dose: add an entry at its time, so the widget
            // flags it overdue if it passes unlogged. Logging it reloads
            // the timeline from the app.
            if let due = entries[0].nextDoseDate, due > now, due < next {
                entries.append(entry(from: payload, at: due))
            }
            // WidgetKit may run the reload late; this entry turns
            // yesterday's doses into the outdated prompt at midnight
            // regardless.
            entries.append(entry(from: payload, at: WidgetData.nextMidnight(after: now)))
        }
        completion(Timeline(entries: entries, policy: .after(next)))
    }

    private func entry(from payload: WidgetPayload, at date: Date) -> DoseEntry {
        let data: WidgetData
        switch payload {
        case .missing: return .empty
        case .unreadable:
            var entry = DoseEntry.placeholder
            entry.isUnavailable = true
            return entry
        case .loaded(let loaded): data = loaded
        }
        guard !data.isProtocolOutdated(at: date) else {
            return DoseEntry(
                date: date, peptideName: "", dose: "", nextDoseDate: nil,
                completed: 0, total: 0, compliance: 0, upcoming: [],
                isOutdated: true
            )
        }
        return DoseEntry(
            date: date,
            peptideName: data.nextPeptideName,
            dose: data.nextDose,
            nextDoseDate: data.nextDoseTime,
            completed: data.completedToday,
            total: data.totalToday,
            compliance: data.compliance,
            upcoming: data.upcoming,
            hasActiveProtocol: data.hasActiveProtocol
        )
    }
}

// MARK: - Pieces

private let protocolTint = WidgetPalette.protocolDose

/// One pip per dose today, filled as they're logged. Reads as "two of
/// four" faster than a fraction does. Past ten doses the pips would be
/// slivers, so it becomes a single bar.
private struct DosePips: View {
    let completed: Int
    let total: Int

    var body: some View {
        Group {
            if total > 10 {
                WidgetBar(progress: Double(completed) / Double(total), tint: protocolTint)
            } else {
                HStack(spacing: 3) {
                    ForEach(0..<total, id: \.self) { index in
                        Capsule()
                            .fill(index < completed ? protocolTint : WidgetPalette.track)
                            .frame(height: 4)
                            .widgetAccentable(index < completed)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(completed) of \(total) doses logged"))
    }
}

private struct AllDoneLabel: View {
    var body: some View {
        Label("All done today", systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WidgetPalette.done)
            .widgetAccentable()
    }
}

private struct OutdatedLabel: View {
    var body: some View {
        Text("Open Atlas to load today's doses.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Deliberately not a "+" glyph: the widget opens Today, not the
/// protocol editor, so it shouldn't look like a button.
private struct NoProtocolLabel: View {
    var body: some View {
        Text("Add a protocol to track doses here.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A protocol is running but schedules nothing today: a calm note, not
/// a prompt to add one.
private struct RestDayLabel: View {
    var body: some View {
        Label("No doses today", systemImage: "moon.zzz")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Home screen

private struct SmallProtocolView: View {
    let entry: DoseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(
                glyph: "checklist",
                title: "Protocol",
                tint: protocolTint,
                trailing: entry.doseCount,
                trailingAccessibilityLabel: entry.spokenDoseCount
            )
            Spacer(minLength: 6)
            content
            Spacer(minLength: 6)
            if entry.hasProtocol {
                DosePips(completed: entry.completed, total: entry.total)
            }
        }
        .widgetBackdrop(protocolTint)
    }

    @ViewBuilder
    private var content: some View {
        if entry.isOutdated {
            OutdatedLabel()
        } else if entry.isRestDay {
            RestDayLabel()
        } else if !entry.hasProtocol {
            NoProtocolLabel()
        } else if entry.allDone {
            AllDoneLabel()
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.isOverdue ? "Overdue" : "Next")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(entry.isOverdue ? AnyShapeStyle(WidgetPalette.over) : AnyShapeStyle(.secondary))
                Text(entry.peptideName)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .privacySensitive()
                if !entry.dose.isEmpty {
                    Text(entry.dose)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .privacySensitive()
                }
                if let due = entry.nextDoseDate {
                    Text(due, style: .time)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(entry.isOverdue ? WidgetPalette.over : protocolTint)
                }
            }
        }
    }
}

private struct MediumProtocolView: View {
    let entry: DoseEntry

    var body: some View {
        HStack(spacing: 16) {
            dial
                .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(
                    glyph: "checklist",
                    title: "Today's protocol",
                    tint: protocolTint,
                    trailing: entry.doseCount,
                    trailingAccessibilityLabel: entry.spokenDoseCount
                )
                if entry.isOutdated {
                    OutdatedLabel()
                } else if entry.isRestDay {
                    RestDayLabel()
                } else if !entry.hasProtocol {
                    NoProtocolLabel()
                } else if entry.allDone || entry.upcoming.isEmpty {
                    AllDoneLabel()
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        // Keyed by position: two doses at the same minute
                        // share a timestamp, and a time id would drop one.
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, slot in
                            DoseRow(slot: slot, now: entry.date)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .widgetBackdrop(protocolTint)
    }

    /// With nothing scheduled a "0%" ring would read as a failed day,
    /// so the glyph stands in until there are doses to count.
    @ViewBuilder
    private var dial: some View {
        if entry.hasProtocol {
            WidgetRing(progress: entry.compliance, tint: protocolTint, lineWidth: 8)
                .overlay {
                    Text(entry.compliance.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: entry.compliance))
                        .widgetAccentable()
                }
        } else {
            Image(systemName: "checklist")
                .font(.title2.weight(.semibold))
                .foregroundStyle(protocolTint)
                .widgetAccentable()
                .accessibilityHidden(true)
        }
    }

    /// Doses still to take come first, so a morning's struck-through
    /// rows don't push the next one off the widget.
    private var rows: [WidgetDoseSlot] {
        let pending = entry.upcoming.filter { !$0.completed }
        let done = entry.upcoming.filter(\.completed)
        return Array((pending + done).prefix(3))
    }
}

private struct DoseRow: View {
    let slot: WidgetDoseSlot
    /// The entry's date, so a row turns overdue on the timeline entry
    /// scheduled at its time, as the small widget's "Overdue" does.
    let now: Date

    private var isOverdue: Bool { !slot.completed && slot.time <= now }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: slot.completed ? "checkmark.circle.fill" : "circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(slot.completed ? AnyShapeStyle(protocolTint) : AnyShapeStyle(.tertiary))
                .widgetAccentable(slot.completed)
            Text(slot.peptideName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(slot.completed ? .secondary : .primary)
                .strikethrough(slot.completed, color: .secondary)
                .privacySensitive()
            if !slot.dose.isEmpty {
                Text(slot.dose)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .privacySensitive()
            }
            Spacer(minLength: 4)
            Text(slot.time, style: .time)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(isOverdue ? AnyShapeStyle(WidgetPalette.over) : AnyShapeStyle(.secondary))
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isOverdue ? Text("Overdue") : Text(""))
    }
}

/// Protocol Adherence's medium layout: the day's adherence as a large
/// ring and a count, without the dose list Today's Protocol shows, so
/// the gallery's two medium protocol widgets don't look the same.
private struct AdherenceMediumView: View {
    let entry: DoseEntry

    var body: some View {
        HStack(spacing: 16) {
            WidgetRing(progress: entry.compliance, tint: protocolTint, lineWidth: 10)
                .overlay { ringCenter }
                .frame(width: 96, height: 96)
                // The count beside it says the same thing in words.
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(
                    glyph: "checklist",
                    title: "Adherence",
                    tint: protocolTint,
                    trailing: entry.doseCount,
                    trailingAccessibilityLabel: entry.spokenDoseCount
                )
                status
                Spacer(minLength: 0)
                if entry.hasProtocol {
                    DosePips(completed: entry.completed, total: entry.total)
                }
            }
        }
        .widgetBackdrop(protocolTint)
    }

    @ViewBuilder
    private var ringCenter: some View {
        if entry.hasProtocol {
            Text(entry.compliance.formatted(.percent.precision(.fractionLength(0))))
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText(value: entry.compliance))
                .widgetAccentable()
        } else {
            Image(systemName: "checklist")
                .font(.title2.weight(.semibold))
                .foregroundStyle(protocolTint)
                .widgetAccentable()
        }
    }

    @ViewBuilder
    private var status: some View {
        if entry.isOutdated {
            OutdatedLabel()
        } else if entry.isRestDay {
            RestDayLabel()
        } else if !entry.hasProtocol {
            NoProtocolLabel()
        } else if entry.allDone {
            AllDoneLabel()
        } else {
            entry.spokenDoseCount
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Lock screen

private struct CircularProtocolView: View {
    let entry: DoseEntry

    var body: some View {
        Group {
            if entry.hasProtocol {
                Gauge(value: entry.compliance) {
                    Image(systemName: "checklist")
                } currentValueLabel: {
                    Text("\(entry.completed)/\(entry.total)")
                }
                .gaugeStyle(.accessoryCircular)
            } else {
                // "0/0" counts nothing; the glyph alone says "no doses".
                Image(systemName: "checklist")
                    .font(.title3.weight(.semibold))
            }
        }
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// "2/3" reads as "two slash three"; say what the gauge counts.
    private var accessibilityText: Text {
        if entry.isOutdated { return Text("Open Atlas to update") }
        if entry.isRestDay { return Text("No doses today") }
        if !entry.hasProtocol { return Text("No protocol yet") }
        return entry.spokenDoseCount
    }
}

private struct RectangularProtocolView: View {
    let entry: DoseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Protocol", systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .widgetAccentable()
            if entry.isOutdated {
                Text("Open Atlas to update")
                    .font(.headline)
            } else if entry.isRestDay {
                Text("No doses today")
                    .font(.headline)
            } else if !entry.hasProtocol {
                Text("No protocol yet")
                    .font(.headline)
            } else if entry.allDone {
                Text("All done today")
                    .font(.headline)
            } else {
                Text(entry.peptideName)
                    .font(.headline)
                    .privacySensitive()
                if let due = entry.nextDoseDate {
                    dueLine(due)
                        .font(.caption)
                        .privacySensitive()
                }
            }
        }
        .lineLimit(1)
    }

    /// The dose and its time, led by "Overdue" once the time has passed
    /// unlogged — the monochrome lock screen can't carry the amber.
    private func dueLine(_ due: Date) -> Text {
        let time = Text(due, style: .time)
        switch (entry.isOverdue, entry.dose.isEmpty) {
        case (true, true): return Text("Overdue · \(time)")
        case (true, false): return Text("Overdue · \(entry.dose) · \(time)")
        case (false, true): return time
        case (false, false): return Text("\(entry.dose) · \(time)")
        }
    }
}

private struct InlineProtocolView: View {
    let entry: DoseEntry

    var body: some View {
        if entry.isOutdated {
            Label("Open Atlas to update", systemImage: "checklist")
        } else if entry.isRestDay {
            Label("No doses today", systemImage: "checklist")
        } else if !entry.hasProtocol {
            Label("No protocol yet", systemImage: "checklist")
        } else if entry.allDone {
            Label("All done today", systemImage: "checklist")
        } else if let due = entry.nextDoseDate {
            Label {
                entry.isOverdue
                    ? Text("Overdue: \(entry.peptideName) at \(Text(due, style: .time))")
                    : Text("\(entry.peptideName) at \(Text(due, style: .time))")
            } icon: {
                Image(systemName: "checklist")
            }
            .privacySensitive()
        } else {
            Label(entry.peptideName, systemImage: "checklist")
                .privacySensitive()
        }
    }
}

// MARK: - Widgets

/// Protocol Adherence: its own medium layout, the shared views otherwise.
struct ComplianceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DoseEntry

    var body: some View {
        if family == .systemMedium {
            AdherenceMediumView(entry: entry)
        } else {
            NextDoseWidgetView(entry: entry)
        }
    }
}

struct NextDoseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DoseEntry

    var body: some View {
        switch family {
        case .systemMedium: MediumProtocolView(entry: entry)
        case .accessoryCircular: CircularProtocolView(entry: entry).accessoryBackdrop()
        case .accessoryRectangular: RectangularProtocolView(entry: entry).accessoryBackdrop()
        case .accessoryInline: InlineProtocolView(entry: entry).accessoryBackdrop()
        default: SmallProtocolView(entry: entry)
        }
    }
}

/// Kind strings stay as shipped so widgets already on a home screen keep
/// working; only what the gallery shows changed.
struct NextDoseWidget: Widget {
    let kind = "NextDoseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DoseTimelineProvider()) { entry in
            NextDoseWidgetView(entry: entry)
                .redacted(reason: entry.isUnavailable ? .placeholder : [])
                .widgetURL(WidgetDeepLink.today)
        }
        .configurationDisplayName("Today's Protocol")
        .description("Your next scheduled dose and today's progress.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct ComplianceWidget: Widget {
    let kind = "ComplianceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DoseTimelineProvider()) { entry in
            ComplianceWidgetView(entry: entry)
                .redacted(reason: entry.isUnavailable ? .placeholder : [])
                .widgetURL(WidgetDeepLink.today)
        }
        .configurationDisplayName("Protocol Adherence")
        .description("How much of today's protocol you've logged.")
        .supportedFamilies([.systemMedium, .accessoryCircular])
    }
}
