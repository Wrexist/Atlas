import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct DoseEntry: TimelineEntry {
    let date: Date
    let peptideName: String
    let dose: String
    let doseTime: String
    let nextDoseDate: Date?
    let completed: Int
    let total: Int
    let compliance: Double
    let upcoming: [WidgetDoseSlot]

    static let placeholder = DoseEntry(
        date: .now,
        peptideName: "BPC-157",
        dose: "250 mcg",
        doseTime: "8:00 AM",
        nextDoseDate: .now,
        completed: 3,
        total: 5,
        compliance: 0.6,
        upcoming: [
            WidgetDoseSlot(peptideName: "BPC-157",     dose: "250 mcg", time: .now, completed: true),
            WidgetDoseSlot(peptideName: "TB-500",      dose: "2 mg",    time: .now.addingTimeInterval(3600), completed: false),
            WidgetDoseSlot(peptideName: "Glutathione", dose: "200 mg",  time: .now.addingTimeInterval(7200), completed: false),
        ]
    )
}

// MARK: - Timeline Provider

struct DoseTimelineProvider: TimelineProvider {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func placeholder(in context: Context) -> DoseEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (DoseEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DoseEntry>) -> Void) {
        let entry = currentEntry()
        let calendar = Calendar.current

        // Always refresh at midnight to show the new day's schedule
        let midnight = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        let fifteenMin = calendar.date(byAdding: .minute, value: 15, to: .now) ?? .now

        let nextUpdate: Date
        if let doseDate = entry.nextDoseDate, doseDate > .now, doseDate <= fifteenMin {
            // Dose is imminent: refresh 1 min after it's due
            nextUpdate = min(doseDate.addingTimeInterval(60), midnight)
        } else {
            // Standard 15-min refresh, but never past midnight
            nextUpdate = min(fifteenMin, midnight)
        }

        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func currentEntry() -> DoseEntry {
        guard let widgetData = loadWidgetData() else {
            return DoseEntry(
                date: .now,
                peptideName: "",
                dose: "",
                doseTime: "",
                nextDoseDate: nil,
                completed: 0,
                total: 0,
                compliance: 0,
                upcoming: []
            )
        }

        let doseTime: String
        if let time = widgetData.nextDoseTime {
            doseTime = time.formatted(.dateTime.hour().minute())
        } else {
            doseTime = ""
        }

        return DoseEntry(
            date: .now,
            peptideName: widgetData.nextPeptideName,
            dose: widgetData.nextDose,
            doseTime: doseTime,
            nextDoseDate: widgetData.nextDoseTime,
            completed: widgetData.completedToday,
            total: widgetData.totalToday,
            compliance: widgetData.compliance,
            upcoming: widgetData.upcoming
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

// MARK: - Small Widget View

struct SmallWidgetView: View {
    let entry: DoseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "flask.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                Text("PeptideX")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if entry.total == 0 {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
                Text("No protocols")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else if entry.dose.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
                Text("All done!")
                    .font(.headline)
            } else {
                Text(entry.peptideName)
                    .font(.headline)
                    .lineLimit(1)
                Text(entry.dose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.doseTime)
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Medium Widget View

struct MediumWidgetView: View {
    let entry: DoseEntry

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Compliance ring + counter — anchors the widget visually.
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: entry.compliance)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(entry.compliance * 100))%")
                        .font(.system(size: 14, weight: .bold))
                }
                .frame(width: 56, height: 56)

                Text("\(entry.completed)/\(entry.total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Today list — shows the day at a glance instead of a single
            // next dose. Capped at 3 rows so a default Dynamic Type viewport
            // never clips on the Medium family.
            VStack(alignment: .leading, spacing: 6) {
                Text("Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if entry.total == 0 {
                    Text("Create a protocol")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("to start tracking doses")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                } else if entry.upcoming.isEmpty {
                    Text("All doses completed!")
                        .font(.headline)
                        .foregroundStyle(.green)
                } else {
                    ForEach(entry.upcoming.prefix(3), id: \.time) { slot in
                        doseRow(slot)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func doseRow(_ slot: WidgetDoseSlot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: slot.completed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(slot.completed ? .green : .secondary)
            Text(slot.peptideName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(slot.completed ? .secondary : .primary)
                .strikethrough(slot.completed, color: .secondary)
                .lineLimit(1)
            Text("\u{2022} \(slot.dose)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(slot.time.formatted(.dateTime.hour().minute()))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Widget Definitions

struct NextDoseWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: DoseEntry

    var body: some View {
        switch family {
        case .systemMedium:
            MediumWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

struct NextDoseWidget: Widget {
    let kind = "NextDoseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DoseTimelineProvider()) { entry in
            NextDoseWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Dose")
        .description("Shows your next scheduled peptide dose")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ComplianceWidget: Widget {
    let kind = "ComplianceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DoseTimelineProvider()) { entry in
            MediumWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Compliance")
        .description("Track your daily dose completion")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Widget Bundle

@main
struct PeptideWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextDoseWidget()
        ComplianceWidget()
    }
}
