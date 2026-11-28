import SwiftUI

/// Today's lifestyle overview: the minimum-day week tile, plus a
/// calorie tile only while no target is set (with one, calories and
/// water live in the hero card's bars), and the rotating daily insight. Doses
/// are deliberately absent — they have one home on Today, the
/// "Today's doses" section.
///
/// Each stat tile opens the action its footnote names via
/// `onTapTile`; the insight row routes to labs or the nudge's
/// destination via `onTapInsight`.
struct TodayOverviewCard: View {
    let snapshot: TodayOverviewSnapshot
    /// Called when the user taps the bottom insight row. Lets the
    /// host route a "latest lab" insight to the labs view or just
    /// dismiss the nudge.
    let onTapInsight: (TodayOverviewSnapshot.BottomInsight) -> Void
    /// Called when a stat tile is tapped. Nil keeps the tiles
    /// display-only (previews).
    var onTapTile: ((Tile) -> Void)?
    /// False while Today browses a past day, so a footnote doesn't
    /// invite logging into a day that's over.
    var isToday = true

    enum Tile {
        case calories, minimumDay
    }

    var body: some View {
        GlassCard(tinted: true) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                statsGrid
                if let insight = snapshot.bottomInsight {
                    bottomInsight(insight)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity
                        ))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Stats grid

    /// One row that splits its width between the tiles shown, so a lone
    /// minimum-day tile spans the card instead of leaving half of it empty.
    private var statsGrid: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            if snapshot.calorieTarget == nil {
                tileButton(.calories, hint: "Opens your calorie target or Meals") { caloriesTile }
            }
            tileButton(.minimumDay, hint: "Opens your minimum day") { minimumDayTile }
        }
    }

    @ViewBuilder
    private func tileButton<Content: View>(
        _ tile: Tile,
        hint: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if let onTapTile {
            Button { onTapTile(tile) } label: { content() }
                .buttonStyle(ScalePressStyle(pressedScale: 0.97))
                .accessibilityHint(hint)
        } else {
            content()
        }
    }

    private var caloriesTile: some View {
        StatTile(
            label: "Calories",
            value: snapshot.caloriesToday > 0 || snapshot.calorieTarget != nil
                ? snapshot.caloriesToday.formatted()
                : "—",
            icon: "fork.knife",
            tint: AppColor.accentPrimary,
            footnote: caloriesFootnote,
            progress: caloriesProgress
        )
    }

    private var caloriesProgress: Double? {
        guard let target = snapshot.calorieTarget, target > 0 else { return nil }
        return min(Double(snapshot.caloriesToday) / Double(target), 1.0)
    }

    private var caloriesFootnote: String {
        if let target = snapshot.calorieTarget {
            return String(localized: "of \(target.formatted()) kcal")
        }
        if snapshot.caloriesToday > 0 {
            return String(localized: "kcal logged")
        }
        return isToday ? String(localized: "Set a target") : String(localized: "No calories logged")
    }

    /// Days met this week out of five. Never a zero: an empty week reads
    /// as a fresh start, and the footnote names the next step.
    private var minimumDayTile: some View {
        let minimum = snapshot.minimum
        return StatTile(
            label: "Minimum day",
            // Capped at the goal: a kept week is a kept week, not "7/5".
            value: minimum.metThisWeek > 0 ? "\(min(minimum.metThisWeek, MinimumDay.weeklyGoal))/\(MinimumDay.weeklyGoal)" : "—",
            icon: "checkmark.circle",
            tint: AppColor.accentPrimary,
            footnote: minimumFootnote,
            progress: minimum.weekProgress,
            accessibilityLabel: minimum.metThisWeek > 0
                ? String(localized: "Minimum day, \(minimum.metThisWeek) of \(MinimumDay.weeklyGoal) days this week. \(minimumFootnote)")
                : String(localized: "Minimum day. \(minimumFootnote)")
        )
    }

    private var minimumFootnote: String {
        guard isToday else {
            return snapshot.minimum.status == .doneToday
                ? String(localized: "Minimum met")
                : String(localized: "Minimum not met")
        }
        return switch snapshot.minimum.status {
        case .doneToday: String(localized: "Done today")
        case .start: String(localized: "Do the minimum to count today")
        case .newWeek: String(localized: "New week. Start with the minimum")
        case .newDay: String(localized: "New day. Do the minimum")
        case .keepGoing: String(localized: "this week")
        }
    }

    // MARK: - Bottom insight

    private func bottomInsight(_ insight: TodayOverviewSnapshot.BottomInsight) -> some View {
        Button {
            Haptics.impact(.soft)
            onTapInsight(insight)
        } label: {
            insightRow(insight)
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityLabel("\(insight.title). \(insight.body)")
    }

    private func insightRow(_ insight: TodayOverviewSnapshot.BottomInsight) -> some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(AppColor.accentPrimary.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: insight.icon)
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(insight.title)
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
                Text(insight.body)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.cardOverlay)
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .contentShape(Rectangle())
    }
}

#Preview("Mid-day") {
    ScrollView {
        TodayOverviewCard(
            snapshot: TodayOverviewSnapshot(
                caloriesToday: 1280,
                calorieTarget: 2400,
                waterToday: 48,
                mealStreak: 7,
                minimum: .init(metThisWeek: 3, total: 21, status: .keepGoing),
                checkInScore: 4.2,
                latestLab: nil,
                bottomInsight: .nudge(
                    title: "Set a calorie target",
                    body: "Unlocks the macro rings and Watch glance.",
                    icon: "target",
                    action: .setCalorieTarget
                )
            ),
            onTapInsight: { _ in }
        )
        .padding(Spacing.screenPadding)
    }
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}

#Preview("Empty state") {
    ScrollView {
        TodayOverviewCard(
            snapshot: TodayOverviewSnapshot(
                caloriesToday: 0,
                calorieTarget: nil,
                waterToday: 0,
                mealStreak: 0,
                minimum: .init(metThisWeek: 0, total: 0, status: .start),
                checkInScore: nil,
                latestLab: nil,
                bottomInsight: nil
            ),
            onTapInsight: { _ in }
        )
        .padding(Spacing.screenPadding)
    }
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}
