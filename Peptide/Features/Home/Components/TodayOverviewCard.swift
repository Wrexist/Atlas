import SwiftUI

/// "Today at a glance" supporting card. Originally hosted the
/// compliance ring + next-dose strip + stat tiles + insight, but
/// the ring + eyebrow + compliance pill moved up into
/// `HeroMetricTrio` in the Bevel-style redesign.
/// This card now focuses on what's still uniquely its: the
/// tappable next-dose strip plus the 2×2 lifestyle stat grid
/// (Calories / Meal streak / Check-in / Water) and the rotating
/// daily insight.
///
/// The hero strip taps the next-pending dose so the user is one
/// tap away from logging from the top of the scroll. Each stat tile
/// opens the action its footnote names via `onTapTile`; the insight
/// row routes to labs or the nudge's destination via `onTapInsight`.
struct TodayOverviewCard: View {
    let snapshot: TodayOverviewSnapshot
    /// Water is stored in fluid ounces. Defaulted so previews stay
    /// two-line; the one live call site passes the profile's setting.
    var unit: MeasurementUnit = .metric
    /// Called when the user taps the hero. Receives the next
    /// pending dose if there is one, else nil — the host decides
    /// whether to open the logging sheet or no-op.
    let onTapHero: (ProtocolEntry?) -> Void
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

    private var heroAccessibilityLabel: String {
        if let dose = snapshot.nextDose {
            let timeString = Self.timeFormatter.string(from: dose.date)
            return "Next dose: \(dose.peptide.name), \(dose.dose) at \(timeString)"
        }
        return "All \(snapshot.dosesTotalToday) doses logged today"
    }

    /// Users with no doses scheduled today (most fitness-only users)
    /// have nothing to log here, so the strip is hidden rather than
    /// shown as a dead, protocol-led button.
    private var showsNextDoseStrip: Bool {
        snapshot.nextDose != nil || snapshot.dosesTotalToday > 0
    }

    var body: some View {
        GlassCard(tinted: true) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if showsNextDoseStrip {
                    nextDoseStrip
                }
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

    // MARK: - Next-dose strip
    //
    // Slim replacement for the old hero section. The compliance
    // ring + eyebrow + title that lived here previously moved up
    // into HeroMetricTrio; what's still
    // genuinely useful is a one-tap entry into the next pending
    // dose's logging sheet from anywhere on the scroll.

    private var nextDoseStrip: some View {
        Button {
            Haptics.impact(.light)
            onTapHero(snapshot.nextDose)
        } label: {
            HStack(spacing: Spacing.md) {
                iconBadge

                VStack(alignment: .leading, spacing: 2) {
                    Text(stripEyebrow)
                        .font(AppFont.scaled(11, weight: .heavy, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(AppColor.accentLight)
                    Text(stripTitle)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let subtitle = stripSubtitle {
                        Text(subtitle)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if snapshot.nextDose != nil {
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(13, weight: .bold))
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle(pressedScale: 0.985))
        .disabled(snapshot.nextDose == nil)
        .accessibilityLabel(heroAccessibilityLabel)
    }

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(AppColor.accentPrimary.opacity(0.18))
            Image(systemName: stripIcon)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(AppColor.accentPrimary)
        }
        .frame(width: 40, height: 40)
    }

    private var stripIcon: String {
        snapshot.nextDose != nil ? "syringe.fill" : "checkmark.circle.fill"
    }

    private var stripEyebrow: String {
        snapshot.nextDose != nil ? String(localized: "NEXT DOSE") : String(localized: "ALL DONE")
    }

    private var stripTitle: String {
        if let dose = snapshot.nextDose {
            return dose.peptide.name
        }
        return String(localized: "You're set for today")
    }

    private var stripSubtitle: String? {
        if let dose = snapshot.nextDose {
            let time = Self.timeFormatter.string(from: dose.date)
            return "\(dose.dose) · \(time)"
        }
        if snapshot.dosesTotalToday > 0, snapshot.doseStreak > 1 {
            return String(format: String(localized: "%d-day streak"), snapshot.doseStreak)
        }
        return nil
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
                ? "\(unit.volumeSuffix) today"
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

    // MARK: - Helpers

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}

// `HeroRing` (the compliance ring that lived in this card's hero
// slot) was deleted in the Phase 1.5 polish — its role moved up
// into `HeroMetricTrio.adherence`, so the duplicate ring was both
// redundant data and ~80pt of wasted vertical space. Stat tiles +
// next-dose strip + insight are the remaining responsibilities.

// `CompactCompliancePill` lived in the card's deleted header and
// went away with it — same role now covered by HeroMetricTrio.

#Preview("Mid-day, partial compliance") {
    ScrollView {
        TodayOverviewCard(
            snapshot: TodayOverviewSnapshot(
                complianceFraction: 0.5,
                dosesCompletedToday: 1,
                dosesTotalToday: 2,
                nextDose: nil,
                doseStreak: 12,
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
            onTapHero: { _ in },
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
                complianceFraction: nil,
                dosesCompletedToday: 0,
                dosesTotalToday: 0,
                nextDose: nil,
                doseStreak: 0,
                caloriesToday: 0,
                calorieTarget: nil,
                waterToday: 0,
                mealStreak: 0,
                checkInScore: nil,
                latestLab: nil,
                bottomInsight: nil
            ),
            onTapHero: { _ in },
            onTapInsight: { _ in }
        )
        .padding(Spacing.screenPadding)
    }
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}
