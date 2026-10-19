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

    var hasProtocol: Bool { total > 0 }
    var allDone: Bool { hasProtocol && dose.isEmpty }

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
        completion(context.isPreview ? .placeholder : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DoseEntry>) -> Void) {
        let entry = currentEntry()
        var next = WidgetStore.nextRefresh(after: .now)
        // An imminent dose: refresh a minute after it's due, so the
        // widget moves on to the one after it.
        if let due = entry.nextDoseDate, due > .now, due < next {
            next = due.addingTimeInterval(60)
        }
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry() -> DoseEntry {
        guard let data = WidgetStore.load() else { return .empty }
        return DoseEntry(
            date: .now,
            peptideName: data.nextPeptideName,
            dose: data.nextDose,
            nextDoseDate: data.nextDoseTime,
            completed: data.completedToday,
            total: data.totalToday,
            compliance: data.compliance,
            upcoming: data.upcoming
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

// MARK: - Home screen

private struct SmallProtocolView: View {
    let entry: DoseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(
                glyph: "checklist",
                title: "Protocol",
                tint: protocolTint,
                trailing: entry.hasProtocol ? "\(entry.completed)/\(entry.total)" : nil
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
        if !entry.hasProtocol {
            NoProtocolLabel()
        } else if entry.allDone {
            AllDoneLabel()
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Next")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(entry.peptideName)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .privacySensitive()
                Text(entry.dose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .privacySensitive()
                if let due = entry.nextDoseDate {
                    Text(due, style: .time)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(protocolTint)
                }
            }
        }
    }
}

private struct MediumProtocolView: View {
    let entry: DoseEntry

    var body: some View {
        HStack(spacing: 16) {
            WidgetRing(progress: entry.compliance, tint: protocolTint, lineWidth: 8)
                .overlay {
                    Text(entry.compliance.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: entry.compliance))
                        .widgetAccentable()
                }
                .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(
                    glyph: "checklist",
                    title: "Today's protocol",
                    tint: protocolTint,
                    trailing: entry.hasProtocol ? "\(entry.completed)/\(entry.total)" : nil
                )
                if !entry.hasProtocol {
                    NoProtocolLabel()
                } else if entry.allDone || entry.upcoming.isEmpty {
                    AllDoneLabel()
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        // Keyed by position: two doses at the same minute
                        // share a timestamp, and a time id would drop one.
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, slot in
                            DoseRow(slot: slot)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .widgetBackdrop(protocolTint)
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
            Text(slot.dose)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .privacySensitive()
            Spacer(minLength: 4)
            Text(slot.time, style: .time)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }
}

// MARK: - Lock screen

private struct CircularProtocolView: View {
    let entry: DoseEntry

    var body: some View {
        Gauge(value: entry.compliance) {
            Image(systemName: "checklist")
        } currentValueLabel: {
            Text("\(entry.completed)/\(entry.total)")
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
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
            if !entry.hasProtocol {
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
                    Text("\(entry.dose) · \(Text(due, style: .time))")
                        .font(.caption)
                        .privacySensitive()
                }
            }
        }
        .lineLimit(1)
    }
}

private struct InlineProtocolView: View {
    let entry: DoseEntry

    var body: some View {
        if !entry.hasProtocol {
            Label("No protocol yet", systemImage: "checklist")
        } else if entry.allDone {
            Label("All done today", systemImage: "checklist")
        } else if let due = entry.nextDoseDate {
            Label {
                Text("\(entry.peptideName) at \(Text(due, style: .time))")
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
            NextDoseWidgetView(entry: entry)
                .widgetURL(WidgetDeepLink.today)
        }
        .configurationDisplayName("Protocol Adherence")
        .description("How much of today's protocol you've logged.")
        .supportedFamilies([.systemMedium, .accessoryCircular])
    }
}
