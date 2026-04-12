import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct DoseEntry: TimelineEntry {
    let date: Date
    let peptideName: String
    let dose: String
    let doseTime: String
    let completed: Int
    let total: Int
    let compliance: Double
}

// MARK: - Timeline Provider

struct DoseTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DoseEntry {
        DoseEntry(date: .now, peptideName: "BPC-157", dose: "250 mcg", doseTime: "8:00 AM", completed: 3, total: 5, compliance: 0.6)
    }

    func getSnapshot(in context: Context, completion: @escaping (DoseEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DoseEntry>) -> Void) {
        // Widget data sharing requires App Groups (future work).
        // For now, show placeholder data that refreshes every 30 min.
        let entry = placeholder(in: context)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
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

            if entry.dose.isEmpty {
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
        HStack(spacing: 16) {
            VStack(spacing: 8) {
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

            VStack(alignment: .leading, spacing: 4) {
                Text("Next Dose")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if entry.dose.isEmpty {
                    Text("All doses completed!")
                        .font(.headline)
                        .foregroundStyle(.green)
                } else {
                    Text(entry.peptideName)
                        .font(.headline)
                    Text("\(entry.dose) \u{2022} \(entry.doseTime)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
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
