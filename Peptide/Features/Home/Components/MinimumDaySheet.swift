import SwiftUI

/// The minimum day: this week's count, the running total, and the small
/// things that count. Opened from the Minimum day tile on Today.
struct MinimumDaySheet: View {
    /// Today's steps; nil without Health, which leaves the walk unmeasured.
    let todaySteps: Double?

    @Environment(DataStore.self) private var dataStore

    var body: some View {
        let summary = dataStore.minimumDaySummary(todaySteps: todaySteps)
        let input = dataStore.minimumDayInput(for: Date(), steps: todaySteps)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                weekCard(summary)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("What counts")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        ForEach(MinimumDay.Part.allCases, id: \.self) { part in
                            partRow(part, state: MinimumDayEngine.state(of: part, in: input))
                        }
                    }
                    .padding(.horizontal, Spacing.cardPadding)
                    .glassSurface(cornerRadius: Spacing.cardCornerRadius)
                    if !countsAnything(input) {
                        Text("Pick at least one part that Atlas can check, or no day counts.")
                            .font(AppFont.footnote)
                            .foregroundStyle(AppColor.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("A missed day never resets anything. When a streak would break, your monthly freeze covers the day by itself.")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.screenPadding)
            .padding(.top, Spacing.xxl)
            .padding(.bottom, Spacing.lg)
        }
        .liquidGlassPresentation(detents: [.medium, .large])
    }

    /// False when every chosen part is unmeasured (or none is chosen), so
    /// no day can ever be met.
    private func countsAnything(_ input: MinimumDayEngine.DayInput) -> Bool {
        dataStore.minimumDay.parts.contains { MinimumDayEngine.state(of: $0, in: input) != .unmeasured }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Minimum day")
                .font(AppFont.title3)
                .foregroundStyle(AppColor.textPrimary)
            Text("The small floor for a bad day. A day at the minimum is a whole day, and five a week keeps the week.")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func weekCard(_ summary: MinimumDayEngine.Summary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Group {
                if summary.metThisWeek > 0 {
                    Text("\(summary.metThisWeek) of \(MinimumDay.weeklyGoal) days this week")
                } else if summary.status == .start {
                    Text("Do the minimum to count today")
                } else {
                    Text("New week. Start with the minimum")
                }
            }
            .font(AppFont.headline)
            .foregroundStyle(AppColor.textPrimary)
            GlassProgressBar(progress: summary.weekProgress)
                .accessibilityHidden(true)
            if summary.total > 0 {
                Text("^[\(summary.total) day](inflect: true) at the minimum in total")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: Spacing.cardCornerRadius)
        .accessibilityElement(children: .combine)
    }

    private func partRow(_ part: MinimumDay.Part, state: MinimumDayEngine.PartState) -> some View {
        Toggle(isOn: Binding(
            get: { dataStore.minimumDay.parts.contains(part) },
            set: { isOn in
                var parts = dataStore.minimumDay.parts
                if isOn { parts.insert(part) } else { parts.remove(part) }
                Haptics.selection()
                dataStore.setMinimumDayParts(parts)
            }
        )) {
            HStack(spacing: Spacing.md) {
                IconTile(Self.icon(for: part), size: 36)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(Self.title(for: part))
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(Self.detail(for: part, state: state))
                        .font(AppFont.footnote)
                        .foregroundStyle(state == .done ? AppColor.success : AppColor.textSecondary)
                }
            }
        }
        .tint(AppColor.accentPrimary)
        .frame(minHeight: Spacing.minimumHitTarget)
        .padding(.vertical, Spacing.sm)
    }

    private static func icon(for part: MinimumDay.Part) -> String {
        switch part {
        case .logFood: "fork.knife"
        case .protein: "scalemass"
        case .walk: "figure.walk"
        case .checkIn: "checkmark.circle"
        }
    }

    private static func title(for part: MinimumDay.Part) -> LocalizedStringKey {
        switch part {
        case .logFood: "Log something you ate"
        case .protein: "Reach your protein target"
        case .walk: "Walk 10 minutes"
        case .checkIn: "Do the daily check-in"
        }
    }

    private static func detail(for part: MinimumDay.Part, state: MinimumDayEngine.PartState) -> LocalizedStringKey {
        switch state {
        case .done: "Done today"
        case .notYet: "Not yet today"
        case .unmeasured: part == .walk ? "Needs Apple Health, skipped until then" : "Needs a protein target, skipped until then"
        }
    }
}
