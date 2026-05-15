import SwiftUI

/// Premium "Today at a glance" overview that sits at the top of
/// Home. One ring + two stat tiles + one rotating insight row —
/// every visible number reads from the same `TodayOverviewSnapshot`
/// so a fresh build is one struct rebuild, not a six-service
/// scrape per render.
///
/// Design intent: feel like the App Store's "Today" hero — a
/// soft accent-coloured tinted card with a single hero focal
/// point, then a minimal grid of supporting numbers, then a
/// rotating insight strip at the bottom. No tap-to-dive on the
/// stat tiles themselves (they're glanceable summaries); the
/// hero tile taps the next-pending dose so the user is one tap
/// away from logging it from the top of the scroll.
struct TodayOverviewCard: View {
    let snapshot: TodayOverviewSnapshot
    let userName: String
    let hapticsEnabled: Bool
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
                header
                hero
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

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("TODAY")
                    .font(AppFont.caption)
                    .tracking(1.5)
                    .foregroundStyle(AppColor.textSecondary)
                Text(headerTitle)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textPrimary)
            }
            Spacer()
            if let fraction = snapshot.complianceFraction {
                CompactCompliancePill(
                    completed: snapshot.dosesCompletedToday,
                    total: snapshot.dosesTotalToday,
                    fraction: fraction
                )
            }
        }
    }

    private var headerTitle: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return String(localized: "Your day at a glance") }
        let first = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        return String(format: String(localized: "%@'s day at a glance"), first)
    }

    // MARK: - Hero

    private var hero: some View {
        Button {
            if hapticsEnabled {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            onTapHero(snapshot.nextDose)
        } label: {
            HStack(alignment: .center, spacing: Spacing.lg) {
                HeroRing(
                    fraction: snapshot.complianceFraction,
                    completed: snapshot.dosesCompletedToday,
                    total: snapshot.dosesTotalToday
                )
                .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(heroEyebrow)
                        .font(AppFont.caption)
                        .tracking(1.2)
                        .foregroundStyle(AppColor.textSecondary)
                    Text(heroTitle)
                        .font(AppFont.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = heroSubtitle {
                        Text(subtitle)
                            .font(AppFont.subheadline)
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

    private var heroEyebrow: String {
        if snapshot.nextDose != nil { return String(localized: "NEXT DOSE") }
        if snapshot.dosesTotalToday > 0 { return String(localized: "ALL DONE") }
        return String(localized: "PROTOCOL") }

    private var heroTitle: String {
        if let dose = snapshot.nextDose {
            return dose.peptide.name
        }
        if snapshot.dosesTotalToday > 0 {
            return String(localized: "You're set for today")
        }
        return String(localized: "Add a protocol to get started")
    }

    private var heroSubtitle: String? {
        if let dose = snapshot.nextDose {
            let time = Self.timeFormatter.string(from: dose.date)
            return "\(dose.dose) · \(time)"
        }
        if snapshot.dosesTotalToday > 0 {
            return snapshot.doseStreak > 1
                ? String(format: String(localized: "%d-day streak"), snapshot.doseStreak)
                : String(localized: "Great job staying consistent")
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
            if hapticsEnabled {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
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

    nonisolated(unsafe) private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}

// MARK: - Hero ring

/// Mini compliance ring sized for the hero. Renders a soft empty
/// ring when there are no scheduled doses today so the layout
/// doesn't collapse on a brand-new install.
private struct HeroRing: View {
    let fraction: Double?
    let completed: Int
    let total: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    AppColor.glassBorder,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
            if let fraction {
                Circle()
                    .trim(from: 0, to: max(0.001, fraction))
                    .stroke(
                        AngularGradient(
                            colors: [
                                AppColor.accentLight,
                                AppColor.accentPrimary,
                                AppColor.accentDark,
                                AppColor.accentLight,
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.55, dampingFraction: 0.85), value: fraction)
            }
            VStack(spacing: 1) {
                if fraction != nil {
                    Text("\(completed)")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(String(format: String(localized: "of %d"), total))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                } else {
                    Image(systemName: "syringe.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
        }
    }
}

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

// MARK: - Compliance pill

private struct CompactCompliancePill: View {
    let completed: Int
    let total: Int
    let fraction: Double

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text("\(completed)/\(total)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(tint.opacity(0.15))
                .overlay {
                    Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5)
                }
        }
        .accessibilityHidden(true)
    }

    private var tint: Color {
        if fraction >= 1.0 { return AppColor.success }
        if fraction >= 0.5 { return AppColor.accentPrimary }
        return AppColor.warning
    }
}

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
                    icon: "target"
                )
            ),
            userName: "Alex",
            hapticsEnabled: false,
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
            userName: "",
            hapticsEnabled: false,
            onTapHero: { _ in },
            onTapInsight: { _ in }
        )
        .padding(Spacing.screenPadding)
    }
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}
