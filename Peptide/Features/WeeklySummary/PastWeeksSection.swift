import SwiftUI

/// Archive list of past weekly summaries on the Insights tab.
/// Newest-first; a tap on any row pushes the same
/// `WeeklySummaryDetailView` the Today hero links to. Empty state
/// renders nothing — Insights still has plenty of other content,
/// so an "empty archive" placeholder would just be noise.
struct PastWeeksSection: View {
    @Environment(DataStore.self) private var dataStore
    @State private var selectedWeekStart: String?

    private var sortedSummaries: [WeeklySummary] {
        dataStore.profile.weeklySummaries.values.sorted { $0.weekStart > $1.weekStart }
    }

    var body: some View {
        if !sortedSummaries.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HomeSectionHeader(eyebrow: "Past weeks", title: "Recap archive")

                VStack(spacing: Spacing.sm) {
                    ForEach(sortedSummaries.prefix(8)) { summary in
                        Button {
                            selectedWeekStart = summary.weekStart
                        } label: {
                            archiveRow(summary)
                        }
                        .buttonStyle(ScalePressStyle(pressedScale: 0.985))
                    }
                }
            }
            .navigationDestination(item: $selectedWeekStart) { weekStart in
                if let binding = bindingForSummary(weekStart: weekStart) {
                    WeeklySummaryDetailView(
                        summary: binding,
                        onRefresh: {
                            // Archive rows refresh against the
                            // specific week, not the current one —
                            // the AI proxy accepts the aggregate
                            // for any week, but we only re-run the
                            // current-week call from here. Older
                            // weeks are read-only.
                        }
                    )
                }
            }
        }
    }

    private func archiveRow(_ summary: WeeklySummary) -> some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(AppColor.recap.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .font(AppFont.scaled(14, weight: .heavy))
                    .foregroundStyle(AppColor.recap)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(weekTitle(for: summary.weekStart))
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                Text(previewSubtitle(summary))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(AppFont.scaled(12, weight: .heavy))
                .foregroundStyle(AppColor.textTertiary)
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.cardOverlay)
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
    }

    /// Builds a `Binding<WeeklySummary>` into the profile's
    /// dictionary so the detail view's refresh can write back into
    /// the store. Nil when the entry has been deleted between
    /// pushing and rendering — caller falls through to no-op.
    private func bindingForSummary(weekStart: String) -> Binding<WeeklySummary>? {
        guard dataStore.profile.weeklySummaries[weekStart] != nil else { return nil }
        return Binding(
            get: { dataStore.profile.weeklySummaries[weekStart] ?? .placeholder(weekStart: weekStart) },
            set: { newValue in
                dataStore.profile.weeklySummaries[weekStart] = newValue
                dataStore.persistProfile()
            }
        )
    }

    private func weekTitle(for isoWeekStart: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withFullDate]
        guard let date = parser.date(from: isoWeekStart) else { return isoWeekStart }
        let display = DateFormatter()
        display.dateFormat = "MMM d"
        display.locale = .current
        return String(format: String(localized: "Week of %@"), display.string(from: date))
    }

    private func previewSubtitle(_ summary: WeeklySummary) -> String {
        let pct = Int((summary.keyStats.compliancePct * 100).rounded())
        let streak = summary.keyStats.currentStreak
        return String(
            format: String(localized: "%d%% compliance · %d-day streak"),
            pct, streak
        )
    }
}

extension WeeklySummary {
    /// Used by the archive row's binding `get` fallback when the
    /// entry is deleted between push + render. The view checks
    /// for the missing entry before constructing this, so in
    /// practice the placeholder is never actually rendered — but
    /// SwiftUI requires a non-nil value out of the binding closure.
    static func placeholder(weekStart: String) -> WeeklySummary {
        WeeklySummary(
            weekStart: weekStart,
            text: "",
            keyStats: .init(
                compliancePct: 0,
                dosesCompleted: 0,
                dosesTotal: 0,
                currentStreak: 0,
                avgCheckInScore: nil,
                avgCalories: nil,
                hrvDelta: nil
            ),
            kind: .offline,
            generatedAt: Date()
        )
    }
}
