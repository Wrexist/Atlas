import SwiftUI

/// Today's lifestyle overview: meal streak and check-in tiles, plus a
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
        case calories, mealStreak, checkIn
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

    private var statsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Spacing.sm),
                GridItem(.flexible(), spacing: Spacing.sm),
            ],
            spacing: Spacing.sm
        ) {
            if snapshot.calorieTarget == nil {
                tileButton(.calories, hint: "Opens your calorie target or Meals") { caloriesTile }
            }
            tileButton(.mealStreak, hint: "Opens Meals") { mealStreakTile }
            tileButton(.checkIn, hint: "Goes to today's check-in") { checkInTile }
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

    private var mealStreakTile: some View {
        StatTile(
            label: "Meal streak",
            value: snapshot.mealStreak > 0 ? "\(snapshot.mealStreak)" : "—",
            icon: "flame.fill",
            tint: AppColor.accentPrimary,
            footnote: snapshot.mealStreak == 1
                ? String(localized: "day")
                : (snapshot.mealStreak > 1
                    ? String(localized: "days in a row")
                    : (isToday ? String(localized: "Log to start") : String(localized: "No streak")))
        )
    }

    private var checkInTile: some View {
        StatTile(
            label: "Check-in",
            value: snapshot.checkInScore.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
            icon: "heart.text.square.fill",
            tint: AppColor.accentPrimary,
            footnote: snapshot.checkInScore != nil
                ? String(localized: "of 5.0")
                : (isToday ? String(localized: "30-sec check-in") : String(localized: "No check-in")),
            progress: snapshot.checkInScore.map { $0 / 5.0 }
        )
    }

    // MARK: - Bottom insight

    /// Protocol insights have no destination, so they render as plain
    /// text rather than a row that looks pressable and does nothing.
    @ViewBuilder
    private func bottomInsight(_ insight: TodayOverviewSnapshot.BottomInsight) -> some View {
        if case .protocolInsight = insight {
            insightRow(insight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(insight.title). \(insight.body)")
        } else {
            Button {
                Haptics.impact(.soft)
                onTapInsight(insight)
            } label: {
                insightRow(insight)
            }
            .buttonStyle(ScalePressStyle(pressedScale: 0.98))
            .accessibilityLabel("\(insight.title). \(insight.body)")
        }
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
