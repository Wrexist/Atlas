import SwiftUI

/// Today's lifestyle overview: the 2×2 stat grid (Calories / Meal
/// streak / Check-in / Water) and the rotating daily insight. Doses
/// are deliberately absent — they have one home on Today, the
/// "Today's doses" section.
///
/// Each stat tile opens the action its footnote names via
/// `onTapTile`; the insight row routes to labs or the nudge's
/// destination via `onTapInsight`.
struct TodayOverviewCard: View {
    let snapshot: TodayOverviewSnapshot
    /// Water is stored in fluid ounces. Defaulted so previews stay
    /// two-line; the one live call site passes the profile's setting.
    var unit: MeasurementUnit = .metric
    /// Called when the user taps the bottom insight row. Lets the
    /// host route a "latest lab" insight to the labs view or just
    /// dismiss the nudge.
    let onTapInsight: (TodayOverviewSnapshot.BottomInsight) -> Void
    /// Called when a stat tile is tapped. Nil keeps the tiles
    /// display-only (previews).
    var onTapTile: ((Tile) -> Void)?

    enum Tile {
        case calories, mealStreak, checkIn, water
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

    // MARK: - Stats grid (2×2)

    private var statsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Spacing.sm),
                GridItem(.flexible(), spacing: Spacing.sm),
            ],
            spacing: Spacing.sm
        ) {
            tileButton(.calories, hint: "Opens your calorie target or Meals") { caloriesTile }
            tileButton(.mealStreak, hint: "Opens Meals") { mealStreakTile }
            tileButton(.checkIn, hint: "Goes to today's check-in") { checkInTile }
            tileButton(.water, hint: "Adds a glass of water") { waterTile }
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
                ? "\(snapshot.caloriesToday)"
                : "—",
            icon: "fork.knife",
            tint: AppColor.macroProtein,
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
            return String(format: String(localized: "of %d kcal"), target)
        }
        if snapshot.caloriesToday > 0 {
            return String(localized: "kcal logged")
        }
        return String(localized: "Set a target")
    }

    private var mealStreakTile: some View {
        StatTile(
            label: "Meal streak",
            value: snapshot.mealStreak > 0 ? "\(snapshot.mealStreak)" : "—",
            icon: "flame.fill",
            tint: AppColor.streak,
            footnote: snapshot.mealStreak == 1
                ? String(localized: "day")
                : (snapshot.mealStreak > 1
                    ? String(localized: "days in a row")
                    : String(localized: "Log to start"))
        )
    }

    private var checkInTile: some View {
        StatTile(
            label: "Check-in",
            value: snapshot.checkInScore.map { String(format: "%.1f", $0) } ?? "—",
            icon: "heart.text.square.fill",
            tint: AppColor.metricHRV,
            footnote: snapshot.checkInScore != nil
                ? String(localized: "of 5.0")
                : String(localized: "30-sec check-in"),
            progress: snapshot.checkInScore.map { $0 / 5.0 }
        )
    }

    private var waterTile: some View {
        StatTile(
            label: "Water",
            value: snapshot.waterToday > 0 ? "\(unit.volumeValue(snapshot.waterToday))" : "—",
            icon: "drop.fill",
            tint: AppColor.macroWater,
            footnote: snapshot.waterToday > 0
                ? String(localized: "\(unit.volumeSuffix) today")
                : String(localized: "Tap to add")
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
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(AppFont.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                Text(insight.body)
                    .font(AppFont.caption)
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
