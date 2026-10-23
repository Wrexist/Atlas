import SwiftUI

/// "Your progress" — the show-my-improvement surface. Visualizes the
/// earned Atlas Score trend, active streaks, habit consistency and the
/// on-device progress photos, with positive framing ("+N this week", "↑ vs previous 30 days"). Reached
/// from the Atlas Score card on Today. Custom `Path` charts (no
/// SwiftCharts), matching the app's existing chart style.
struct AtlasProgressView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    /// Engine passes (history sort, per-habit streaks, two completion-rate
    /// windows), computed once per store revision instead of in `body`.
    @State private var derived = Derived()

    private struct Derived {
        var history: [MomentumDayPoint] = []
        var habitCurrentStreak = 0
        var rate30: Double?
        var ratePrevious: Double?
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    atlasScoreSection
                        .sectionAppear(index: 0)
                    streaksSection
                        .sectionAppear(index: 1)
                    consistencySection
                        .sectionAppear(index: 2)
                    ProgressPhotosCard()
                        .sectionAppear(index: 3)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.lg)
                .readableContentWidth()
            }
            .background(AppColor.background)
            .navigationTitle("Your progress")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.accentPrimary)
                }
            }
            .task(id: dataStore.revision) { refreshDerived() }
        }
        .presentationSizing(.page)
    }

    private func refreshDerived() {
        let entries = dataStore.profile.habitEntries
        let habits = dataStore.activeHabits
        let frozen = dataStore.profile.streakFreezeDays
        let previousEnd = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let next = Derived(
            history: dataStore.profile.momentumHistory.sorted { $0.date < $1.date },
            // Same freeze days Today passes, so the two streaks agree.
            habitCurrentStreak: habits
                .map { HabitsService.summary(for: $0, entries: entries, frozenDayKeys: frozen).currentStreak }
                .max() ?? 0,
            // Today isn't over, so its unfinished habits aren't missed yet;
            // the previous window has no such day.
            rate30: HabitsService.completionRate(habits: habits, entries: entries, days: 30, pendingDay: Date()),
            ratePrevious: HabitsService.completionRate(habits: habits, entries: entries, days: 30, endingOn: previousEnd)
        )
        AppAnimation.with(AppAnimation.springSmooth) { derived = next }
    }

    // MARK: - Atlas Score

    private var atlasScoreSection: some View {
        let momentum = dataStore.momentum
        let history = derived.history
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
                HStack(spacing: Spacing.xs) {
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
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.streak)
            }

            if history.count >= 2 {
                MomentumTrendChart(points: history)
                    .padding(.top, Spacing.xs)
            } else {
                Text("Keep logging — your score trend appears here as it grows.")
                    .font(AppFont.caption2)
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
        let habitCurrent = derived.habitCurrentStreak

        return VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Streaks", systemImage: "flame.fill")
            HStack(spacing: Spacing.md) {
                streakTile(label: String(localized: "Habits"), current: habitCurrent, best: dataStore.bestHabitStreak, tint: AppColor.streak)
                if !dataStore.protocols.isEmpty {
                    streakTile(label: String(localized: "Doses"), current: dataStore.currentStreak, best: dataStore.bestStreak, tint: AppColor.accentPrimary)
                }
                if !dataStore.profile.mealHistory.isEmpty {
                    streakTile(label: String(localized: "Meals"), current: dataStore.mealLoggingStreak, best: dataStore.bestMealLoggingStreak, tint: AppColor.macroProtein)
                }
            }
        }
        .cardChrome()
    }

    private func streakTile(label: LocalizedStringKey, current: Int, best: Int, tint: Color) -> some View {
        VStack(spacing: Spacing.xxs) {
            Image(systemName: "flame.fill")
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(current > 0 ? tint : AppColor.textTertiary)
            Text("\(current)")
                .font(AppFont.scaled(20, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(AppColor.textPrimary)
            Text(label)
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.textSecondary)
            Text("Best \(best)")
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
        .accessibilityLabel(Text(label) + Text(verbatim: ": ") + Text("^[\(current) day](inflect: true) streak, best \(best)"))
    }

    // MARK: - Consistency

    private var consistencySection: some View {
        let rate30 = derived.rate30
        let ratePrev = derived.ratePrevious

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
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
        .cardChrome()
    }

    private func deltaBadge(now: Double, prev: Double) -> some View {
        let delta = Int(((now - prev) * 100).rounded())
        let tint = delta > 0 ? AppColor.success : AppColor.textTertiary
        let symbol = delta > 0 ? "arrow.up.right" : delta < 0 ? "arrow.down.right" : "arrow.right"
        let sign = delta > 0 ? "+" : "−"
        let label = delta == 0
            ? String(localized: "Same as previous 30 days")
            : String(localized: "\(sign)\(abs(delta)) pts vs previous 30 days")
        return HStack(spacing: Spacing.xxs) {
            Image(systemName: symbol)
                .font(AppFont.scaled(11, weight: .bold))
            Text(label)
                .font(AppFont.scaled(11, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.15)))
    }

    // MARK: - Shared

    private func sectionHeader(_ title: LocalizedStringKey, systemImage: String) -> some View {
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
            .glassSurface(cornerRadius: Spacing.cardCornerRadius)
    }
}

/// Score-over-time sparkline (area + line), Path-based. Decorative — the
/// numeric headline above it carries the meaning for VoiceOver.
private struct MomentumTrendChart: View {
    let points: [MomentumDayPoint] // ascending by date
    /// 0…1 share of the line drawn. Animates in on appear; under Reduce
    /// Motion `AppAnimation.with` sets it straight to 1.
    @State private var drawProgress: CGFloat = 0

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
                .trim(from: 0, to: drawProgress)
                .stroke(
                    LinearGradient(
                        colors: [AppColor.accentDark, AppColor.accentLight],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )

                // Today's score, arriving as the line finishes drawing.
                if let last = pts.last {
                    Circle()
                        .fill(AppColor.accentLight)
                        .frame(width: 8, height: 8)
                        .position(last)
                        .opacity(drawProgress >= 1 ? 1 : 0)
                }
            }
        }
        .frame(height: 110)
        .accessibilityHidden(true)
        .onAppear {
            AppAnimation.with(AppAnimation.draw) { drawProgress = 1 }
        }
    }
}
