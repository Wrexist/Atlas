import SwiftUI

struct CalendarHeatmap: View {
    let entries: [ProtocolEntry]
    let days: Int
    /// Optional callout pinned above the grid. Slot 5 in the App Store
    /// screenshot deck uses this for the "Tuesdays slip" annotation —
    /// real UI, not a Figma overlay.
    var insight: InsightEngine.Insight?

    init(entries: [ProtocolEntry], days: Int, insight: InsightEngine.Insight? = nil) {
        self.entries = entries
        self.days = days
        self.insight = insight
    }

    private var heatmapData: [(date: Date, intensity: Double)] {
        let calendar = Calendar.current
        // Group entries by start-of-day in one pass so the per-day lookup
        // below is O(1). The original `entries.filter` per day produced
        // O(days × entries) work on every body re-evaluation.
        let grouped: [Date: [ProtocolEntry]] = Dictionary(grouping: entries) {
            calendar.startOfDay(for: $0.date)
        }
        let now = Date()
        return (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let key = calendar.startOfDay(for: date)
            guard let dayEntries = grouped[key], !dayEntries.isEmpty else {
                return (date: date, intensity: 0)
            }
            let compliance = Double(dayEntries.filter(\.completed).count) / Double(dayEntries.count)
            return (date: date, intensity: compliance)
        }.reversed()
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Activity", systemImage: "square.grid.3x3.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)

                if let insight {
                    InsightBubble(insight: insight)
                }

                let data = heatmapData
                let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(colorForIntensity(item.intensity))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(days)-day activity heatmap")
                .accessibilityValue(heatmapVoiceOverValue(data: data))

                // Legend
                HStack(spacing: Spacing.sm) {
                    Text("Less")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)

                    ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(colorForIntensity(level))
                            .frame(width: 12, height: 12)
                    }

                    Text("More")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)

                    Spacer()
                }
            }
        }
    }

    private func colorForIntensity(_ intensity: Double) -> Color {
        switch intensity {
        case 0: return AppColor.surfaceElevated
        case 0.01..<0.25: return AppColor.accentDark.opacity(0.3)
        case 0.25..<0.50: return AppColor.accentDark.opacity(0.6)
        case 0.50..<0.75: return AppColor.accentPrimary.opacity(0.7)
        default: return AppColor.accentPrimary
        }
    }

    private func heatmapVoiceOverValue(data: [(date: Date, intensity: Double)]) -> String {
        let active = data.filter { $0.intensity > 0 }
        guard !active.isEmpty else { return "No activity in this period" }
        let avg = active.reduce(0.0) { $0 + $1.intensity } / Double(active.count)
        let pct = Int((avg * 100).rounded())
        return "\(active.count) of \(data.count) days active. Average compliance \(pct) percent."
    }
}

#Preview {
    ZStack {
        AppColor.background.ignoresSafeArea()
        CalendarHeatmap(entries: [], days: 90)
            .padding(Spacing.screenPadding)
    }
    .preferredColorScheme(.dark)
}
