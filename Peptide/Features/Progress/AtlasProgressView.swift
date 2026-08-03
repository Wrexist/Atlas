import SwiftUI

/// "Your Progress" — the show-my-improvement surface. Visualizes the
/// earned Atlas Score trend, active streaks, and habit consistency with
/// positive framing ("+N this week", "↑ vs previous 30 days"). Reached
/// from the Atlas Score card on Today. Custom `Path` charts (no
/// SwiftCharts), matching the app's existing chart style.
struct AtlasProgressView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    atlasScoreSection
                    streaksSection
                    consistencySection
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.lg)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(AppColor.background)
            .navigationTitle("Your Progress")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.accentPrimary)
                }
            }
        }
    }

    // MARK: - Atlas Score

    private var atlasScoreSection: some View {
        let momentum = dataStore.momentum
        let history = dataStore.profile.momentumHistory.sorted { $0.date < $1.date }
        let tint = Color(hex: UInt(momentum.tier.tintHex))
        let week = weekEarned(history)

        return VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Atlas Score", systemImage: "bolt.fill")

            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text("\(momentum.score)")
                    .font(AppFont.scaled(40, weight: .heavy, design: .rounded, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.textPrimary)
                    .contentTransition(.numericText())
                Text("pts")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: momentum.tier.symbol)
                        .font(AppFont.scaled(11, weight: .semibold))
                    Text("Level \(momentum.level) · \(momentum.tier.name)")
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(tint)
            }

            if week > 0 {
                Text("+\(week) points this week")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.streak)
            }

            if history.count >= 2 {
                MomentumTrendChart(points: history)
                    .padding(.top, Spacing.xs)
            } else {
                Text("Keep logging — your score trend appears here as it grows.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .padding(.top, Spacing.xs)
            }
        }
        .cardChrome()
    }

    private func weekEarned(_ history: [MomentumDayPoint]) -> Int {
        let cutoff = Calendar.current.date(
            byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        return history.filter { $0.date >= cutoff }.reduce(0) { $0 + $1.earned }
    }

    // MARK: - Streaks

    private var streaksSection: some View {
        let habitCurrent = dataStore.activeHabits
            .map { HabitsService.summary(for: $0, entries: dataStore.profile.habitEntries).currentStreak }
            .max() ?? 0

        return VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Streaks", systemImage: "flame.fill")
            HStack(spacing: Spacing.md) {
                streakTile(label: "Habits", current: habitCurrent, best: dataStore.bestHabitStreak, tint: AppColor.streak)
                if !dataStore.protocols.isEmpty {
                    streakTile(label: "Doses", current: dataStore.currentStreak, best: dataStore.bestStreak, tint: AppColor.accentPrimary)
                }
                if !dataStore.profile.mealHistory.isEmpty {
                    streakTile(label: "Meals", current: dataStore.mealLoggingStreak, best: dataStore.bestMealLoggingStreak, tint: AppColor.macroProtein)
                }
            }
        }
        .cardChrome()
    }

    private func streakTile(label: String, current: Int, best: Int, tint: Color) -> some View {
        VStack(spacing: Spacing.xxs) {
            Image(systemName: "flame.fill")
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(current > 0 ? tint : AppColor.textTertiary)
            Text("\(current)")
                .font(AppFont.scaled(20, weight: .heavy, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            Text("best \(best)")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                .fill(AppColor.surfaceElevated.opacity(0.5))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(current) day streak, best \(best)")
    }

    // MARK: - Consistency

    private var consistencySection: some View {
        let entries = dataStore.profile.habitEntries
        let habits = dataStore.activeHabits
        let rate30 = HabitsService.completionRate(habits: habits, entries: entries, days: 30)
        let prevEnd = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let ratePrev = HabitsService.completionRate(habits: habits, entries: entries, days: 30, endingOn: prevEnd)

        return VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Habit consistency", systemImage: "checkmark.seal.fill")
            if let rate30 {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text("\(Int((rate30 * 100).rounded()))%")
                        .font(AppFont.scaled(36, weight: .heavy, design: .rounded, relativeTo: .largeTitle))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.textPrimary)
                    Text("last 30 days")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                    Spacer()
                    if let ratePrev, ratePrev > 0 {
                        deltaBadge(now: rate30, prev: ratePrev)
                    }
                }
            } else {
                Text("Add a daily or weekday habit to track your consistency over time.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
        .cardChrome()
    }

    private func deltaBadge(now: Double, prev: Double) -> some View {
        let delta = Int(((now - prev) * 100).rounded())
        let improving = delta >= 0
        return HStack(spacing: 3) {
            Image(systemName: improving ? "arrow.up.right" : "arrow.down.right")
                .font(AppFont.scaled(11, weight: .bold))
            Text("\(abs(delta))% vs prev 30")
                .font(AppFont.scaled(11, weight: .semibold))
        }
        .foregroundStyle(improving ? AppColor.success : AppColor.textTertiary)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 4)
        .background(Capsule().fill((improving ? AppColor.success : AppColor.textTertiary).opacity(0.15)))
    }

    // MARK: - Shared

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(AppColor.accentLight)
            Text(title)
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

private extension View {
    /// Shared glass card chrome for the progress sections.
    func cardChrome() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .stroke(AppColor.glassBorder, lineWidth: 0.5)
            )
    }
}

/// Score-over-time sparkline (area + line), Path-based. Decorative — the
/// numeric headline above it carries the meaning for VoiceOver.
private struct MomentumTrendChart: View {
    let points: [MomentumDayPoint] // ascending by date

    var body: some View {
        GeometryReader { geo in
            let scores = points.map { Double($0.score) }
            let minScore = scores.min() ?? 0
            let maxScore = scores.max() ?? 1
            let range = max(1, maxScore - minScore)
            let stepX = points.count > 1 ? geo.size.width / CGFloat(points.count - 1) : 0
            let pts: [CGPoint] = scores.enumerated().map { index, score in
                let x = CGFloat(index) * stepX
                let y = geo.size.height * (1 - CGFloat((score - minScore) / range))
                return CGPoint(x: x, y: y)
            }

            ZStack {
                Path { path in
                    guard let first = pts.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geo.size.height))
                    path.addLine(to: first)
                    for point in pts.dropFirst() { path.addLine(to: point) }
                    if let last = pts.last {
                        path.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                    }
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [AppColor.accentPrimary.opacity(0.25), AppColor.accentPrimary.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Path { path in
                    guard let first = pts.first else { return }
                    path.move(to: first)
                    for point in pts.dropFirst() { path.addLine(to: point) }
                }
                .stroke(
                    LinearGradient(
                        colors: [AppColor.accentDark, AppColor.accentLight],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(height: 110)
        .accessibilityHidden(true)
    }
}
