import SwiftUI

/// "Today at a glance" supporting card. Originally hosted the
/// compliance ring + next-dose strip + stat tiles + insight, but
/// the ring + eyebrow + compliance pill moved up into
/// `HeroMetricTrio` + `TodayContextRow` in the Bevel-style redesign.
/// This card now focuses on what's still uniquely its: the
/// tappable next-dose strip plus the 2×2 lifestyle stat grid
/// (Calories / Meal streak / Check-in / Water) and the rotating
/// daily insight.
///
/// The hero strip taps the next-pending dose so the user is one
/// tap away from logging from the top of the scroll. Stat tiles
/// stay glanceable (no tap-to-dive); the insight row routes to
/// labs or dismisses the nudge via `onTapInsight`.
struct TodayOverviewCard: View {
    let snapshot: TodayOverviewSnapshot
    /// Called when the user taps the hero. Receives the next
    /// pending dose if there is one, else nil — the host decides
    /// whether to open the logging sheet or no-op.
    let onTapHero: (ProtocolEntry?) -> Void
    /// Called when the user taps the bottom insight row. Lets the
    /// host route a "latest lab" insight to the labs view or just
    /// dismiss the nudge.
    let onTapInsight: (TodayOverviewSnapshot.BottomInsight) -> Void

    private var heroAccessibilityLabel: String {
        if let dose = snapshot.nextDose {
            let timeString = Self.timeFormatter.string(from: dose.date)
            return "Next dose: \(dose.peptide.name), \(dose.dose) at \(timeString)"
        }
        if snapshot.dosesTotalToday > 0 {
            return "All \(snapshot.dosesTotalToday) doses logged today"
        }
        return "No doses scheduled today"
    }

    var body: some View {
        GlassCard(tinted: true) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                nextDoseStrip
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
    // into HeroMetricTrio + TodayContextRow; what's still
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
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
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
                        .font(.system(size: 13, weight: .bold))
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.accentPrimary)
        }
        .frame(width: 40, height: 40)
    }

    private var stripIcon: String {
        if snapshot.nextDose != nil { return "syringe.fill" }
        if snapshot.dosesTotalToday > 0 { return "checkmark.circle.fill" }
        return "plus.circle.fill"
    }

    private var stripEyebrow: String {
        if snapshot.nextDose != nil { return String(localized: "NEXT DOSE") }
        if snapshot.dosesTotalToday > 0 { return String(localized: "ALL DONE") }
        return String(localized: "PROTOCOL")
    }

    private var stripTitle: String {
        if let dose = snapshot.nextDose {
            return dose.peptide.name
        }
        if snapshot.dosesTotalToday > 0 {
            return String(localized: "You're set for today")
        }
        return String(localized: "Add a protocol to get started")
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
            caloriesTile
            mealStreakTile
            checkInTile
            waterTile
        }
    }

    private var caloriesTile: some View {
        OverviewTile(
            icon: "flame.fill",
            iconTint: AppColor.macroProtein,
            label: String(localized: "Calories"),
            value: snapshot.caloriesToday > 0 || snapshot.calorieTarget != nil
                ? "\(snapshot.caloriesToday)"
                : "—",
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
        OverviewTile(
            icon: "leaf.fill",
            iconTint: AppColor.streak,
            label: String(localized: "Meal streak"),
            value: snapshot.mealStreak > 0 ? "\(snapshot.mealStreak)" : "—",
            footnote: snapshot.mealStreak == 1
                ? String(localized: "day")
                : (snapshot.mealStreak > 1
                    ? String(localized: "days in a row")
                    : String(localized: "Log to start")),
            progress: nil
        )
    }

    private var checkInTile: some View {
        OverviewTile(
            icon: "heart.text.square.fill",
            iconTint: AppColor.metricHRV,
            label: String(localized: "Check-in"),
            value: snapshot.checkInScore.map { String(format: "%.1f", $0) } ?? "—",
            footnote: snapshot.checkInScore != nil
                ? String(localized: "of 5.0")
                : String(localized: "30-sec check-in"),
            progress: snapshot.checkInScore.map { $0 / 5.0 }
        )
    }

    private var waterTile: some View {
        OverviewTile(
            icon: "drop.fill",
            iconTint: AppColor.macroWater,
            label: String(localized: "Water"),
            value: snapshot.waterToday > 0 ? "\(snapshot.waterToday)" : "—",
            footnote: snapshot.waterToday > 0
                ? String(localized: "oz today")
                : String(localized: "Quick-add from Watch"),
            progress: nil
        )
    }

    // MARK: - Bottom insight

    private func bottomInsight(_ insight: TodayOverviewSnapshot.BottomInsight) -> some View {
        Button {
            Haptics.impact(.soft)
            onTapInsight(insight)
        } label: {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(AppColor.accentPrimary.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: insight.icon)
                        .font(.system(size: 15, weight: .semibold))
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
        .buttonStyle(ScalePressStyle(pressedScale: 0.98))
        .accessibilityLabel("\(insight.title). \(insight.body)")
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

// MARK: - Tile

/// One stat tile in the 2×2 grid. The progress arc is optional —
/// when nil the tile renders a flat icon chip instead, keeping
/// the row visually balanced when only some domains have a
/// meaningful target to fill.
private struct OverviewTile: View {
    let icon: String
    let iconTint: Color
    let label: String
    let value: String
    let footnote: String
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                ZStack {
                    if let progress {
                        Circle()
                            .stroke(iconTint.opacity(0.18), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: max(0.001, progress))
                            .stroke(
                                iconTint,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)
                    } else {
                        Circle()
                            .fill(iconTint.opacity(0.18))
                    }
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(iconTint)
                }
                .frame(width: 28, height: 28)
                Spacer()
            }
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .heavy))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(AppColor.textSecondary)
            Text(footnote)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(AppColor.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.cardOverlay)
                .overlay {
                    RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                        .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value). \(footnote)")
    }
}

// `CompactCompliancePill` lived in the card's deleted header and
// went away with it — same role now covered by HeroMetricTrio +
// TodayContextRow.

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
