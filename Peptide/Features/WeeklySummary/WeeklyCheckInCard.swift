import SwiftUI

/// The weekly check-in: weight trend with a sparkline, calorie and protein
/// adherence, training days, sleep, and one suggestion for next week.
/// Presentation only — `DataStore.weeklyCheckIn(sleepHours:)` builds it.
struct WeeklyCheckInCard: View {
    let checkIn: WeeklyCheckIn
    let unit: MeasurementUnit
    /// Shown as a button when there is no recent weigh-in. Nil hides it.
    var onLogWeight: (() -> Void)?

    /// Adherence bars grow in once the card is on screen.
    @State private var revealed = false

    private var accent: Color { AppColor.accentPrimary }

    var body: some View {
        GlassCard(tinted: true) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                weightBlock
                if hasMetricRows {
                    Divider().overlay(AppColor.glassBorder)
                    metricRows
                }
                suggestionCallout
            }
        }
        .appAnimation(AppAnimation.settle, value: checkIn)
        .onAppear {
            AppAnimation.with(AppAnimation.springSmooth) { revealed = true }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(AppColor.accentFill)
                    .frame(width: 44, height: 44)
                Image(systemName: "list.bullet.clipboard.fill")
                    .font(AppFont.scaled(16, weight: .heavy))
                    .foregroundStyle(AppColor.onAccent)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly check-in")
                    .font(AppFont.scaled(11, weight: .heavy))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(accent)
                Text("Last 7 days")
                    .font(AppFont.scaled(AppFont.Scale.title, weight: .heavy, design: .rounded, relativeTo: .title3))
                    .foregroundStyle(AppColor.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Weight

    @ViewBuilder
    private var weightBlock: some View {
        if let weight = checkIn.weight {
            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Weight trend")
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        Text(unit.weightValue(weight.currentKg, fractionDigits: 1...1))
                            .font(AppFont.scaled(28, weight: .heavy, design: .rounded, relativeTo: .title1))
                            .foregroundStyle(AppColor.textPrimary)
                            .contentTransition(.numericText())
                        Text(unit.weightSuffix)
                            .font(AppFont.scaled(16, weight: .semibold))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    changeChip(weight)
                }
                Spacer(minLength: Spacing.sm)
                if weight.trend.count >= 2 {
                    BiomarkerSparkline(
                        samples: weight.trend.map { .init(date: $0.date, value: $0.kg) },
                        tint: accent,
                        height: 48
                    )
                    .frame(maxWidth: 120)
                    .transition(.opacity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(weightAccessibilityLabel(weight))
        } else {
            noWeightRow
        }
    }

    private func changeChip(_ weight: WeeklyCheckIn.Weight) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: changeSymbol(weight.changeKgPerWeek))
                .font(AppFont.scaled(11, weight: .heavy))
            Text(changeText(weight))
                .font(AppFont.scaled(13, weight: .semibold))
                .contentTransition(.numericText())
        }
        .foregroundStyle(AppColor.textPrimary)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(accent.opacity(0.15), in: Capsule())
    }

    private var noWeightRow: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Weight trend")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
                Text("No weigh-ins in two weeks")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
            }
            Spacer(minLength: 0)
            if let onLogWeight {
                Button {
                    Haptics.impact(.light)
                    onLogWeight()
                } label: {
                    Text("Log weight")
                        .font(AppFont.chipText)
                        .foregroundStyle(AppColor.accentInkOnWash)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .glassControl(.capsule, tint: accent.opacity(0.15), interactive: false)
                }
                .buttonStyle(ScalePressStyle())
                .minimumHitArea()
            }
        }
    }

    // MARK: - Metric rows

    private var hasMetricRows: Bool {
        checkIn.nutrition != nil || checkIn.training != nil || checkIn.sleep != nil
    }

    private var metricRows: some View {
        VStack(spacing: Spacing.md) {
            if let nutrition = checkIn.nutrition {
                MetricRow(
                    symbol: "flame.fill",
                    tint: AppColor.streak,
                    title: String(localized: "Calories"),
                    value: String(localized: "\(nutrition.averageKcal) kcal a day"),
                    detail: adherenceDetail(nutrition.kcalAdherence, loggedDays: nutrition.loggedDays),
                    progress: nutrition.kcalAdherence,
                    revealed: revealed
                )
                MetricRow(
                    symbol: "fork.knife",
                    tint: AppColor.macroProtein,
                    title: String(localized: "Protein"),
                    value: String(localized: "\(nutrition.averageProteinG) g a day"),
                    detail: adherenceDetail(nutrition.proteinAdherence, loggedDays: nutrition.loggedDays),
                    progress: nutrition.proteinAdherence,
                    revealed: revealed
                )
            }
            if let training = checkIn.training {
                MetricRow(
                    symbol: "figure.strengthtraining.traditional",
                    tint: AppColor.metricActivity,
                    title: String(localized: "Workouts"),
                    value: trainingValue(training),
                    detail: String(localized: "Last week: \(training.previousDays)"),
                    progress: training.goal.map { min(Double(training.days) / Double(max($0, 1)), 1) },
                    revealed: revealed
                )
            }
            if let sleep = checkIn.sleep {
                MetricRow(
                    symbol: "bed.double.fill",
                    tint: AppColor.metricSleep,
                    title: String(localized: "Sleep"),
                    value: String(localized: "\(hours(sleep.averageHours)) h a night"),
                    detail: sleep.previousAverageHours.map { String(localized: "Last week: \(hours($0)) h") },
                    progress: nil,
                    revealed: revealed
                )
            }
        }
    }

    // MARK: - Suggestion

    private var suggestionCallout: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: suggestionSymbol)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Next week")
                    .font(AppFont.scaled(11, weight: .heavy))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.textSecondary)
                Text(suggestionText)
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(suggestionText)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background(
            accent.opacity(0.12),
            in: RoundedRectangle(cornerRadius: Spacing.concentric(in: Spacing.cardCornerRadius, inset: Spacing.cardPadding), style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private var suggestionText: String {
        switch checkIn.suggestion {
        case .hitCalorieTarget:
            String(localized: "Land closer to your calorie target on more days")
        case .weightStalledEatLess(let kcal):
            String(localized: "Weight has held steady for two weeks: cut \(kcal) kcal a day")
        case .weightStalledEatMore(let kcal):
            String(localized: "Weight has held steady for two weeks: add \(kcal) kcal a day")
        case .losingFast(let kcal):
            String(localized: "You're losing fast: add \(kcal) kcal a day to protect muscle")
        case .gainingFast(let kcal):
            String(localized: "You're gaining fast: cut \(kcal) kcal a day")
        case .prioritizeProtein:
            String(localized: "Get protein into every meal to reach your target")
        case .planWorkouts(let goal):
            String(localized: "Book your \(goal) workouts in the calendar now")
        case .prioritizeSleep:
            String(localized: "Aim for at least 7 hours of sleep a night")
        case .weighInMore:
            String(localized: "Weigh in at least 3 mornings for a clearer trend")
        case .keepGoing:
            String(localized: "Good pace, keep it up")
        }
    }

    private var suggestionSymbol: String {
        switch checkIn.suggestion {
        case .hitCalorieTarget, .weightStalledEatLess, .weightStalledEatMore, .losingFast, .gainingFast:
            "dial.medium.fill"
        case .prioritizeProtein: "fork.knife"
        case .planWorkouts: "calendar.badge.plus"
        case .prioritizeSleep: "moon.zzz.fill"
        case .weighInMore: "scalemass.fill"
        case .keepGoing: "hand.thumbsup.fill"
        }
    }

    // MARK: - Formatting

    private func signedWeight(_ kg: Double) -> String {
        let sign = kg > 0 ? "+" : (kg < 0 ? "−" : "±")
        return "\(sign)\(unit.weightValue(abs(kg), fractionDigits: 1...1)) \(unit.weightSuffix)"
    }

    private func changeText(_ weight: WeeklyCheckIn.Weight) -> String {
        guard let change = weight.changeKgPerWeek else {
            return String(localized: "Weigh-ins this week: \(weight.weighInsThisWeek)")
        }
        return String(localized: "\(signedWeight(change)) a week")
    }

    private func changeSymbol(_ change: Double?) -> String {
        guard let change else { return "scalemass.fill" }
        if abs(change) < WeeklyCheckInEngine.stallThresholdKg { return "arrow.right" }
        return change < 0 ? "arrow.down.right" : "arrow.up.right"
    }

    private func weightAccessibilityLabel(_ weight: WeeklyCheckIn.Weight) -> String {
        let value = "\(unit.weightValue(weight.currentKg, fractionDigits: 1...1)) \(unit.weightSpokenUnit)"
        return String(localized: "Weight trend, \(value), \(changeText(weight))")
    }

    private func adherenceDetail(_ adherence: Double?, loggedDays: Int) -> String {
        guard let adherence else { return String(localized: "Logged \(loggedDays) of 7 days") }
        return String(localized: "On target \(percent(adherence)) of logged days")
    }

    private func trainingValue(_ training: WeeklyCheckIn.Training) -> String {
        switch (training.goal, training.goalSource) {
        case (let goal?, .planned?):
            String(localized: "\(training.days) of \(goal) planned")
        case (let goal?, _):
            String(localized: "\(training.days) vs usual \(goal)")
        default:
            String(localized: "Training days: \(training.days)")
        }
    }

    private func percent(_ share: Double) -> String {
        share.formatted(.percent.precision(.fractionLength(0)))
    }

    private func hours(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

/// One line of the check-in: tinted glyph, label, value, a detail line and
/// an optional bar that fills to the share of the week on target.
private struct MetricRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let value: String
    let detail: String?
    let progress: Double?
    let revealed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: symbol)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
                .padding(.top, Spacing.xxs)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(AppColor.textSecondary)
                    Spacer(minLength: Spacing.sm)
                    Text(value)
                        .font(AppFont.scaled(16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .contentTransition(.numericText())
                        .multilineTextAlignment(.trailing)
                }
                if let progress {
                    ProgressBar(value: revealed ? progress : 0, tint: tint)
                }
                if let detail {
                    Text(detail)
                        .font(AppFont.scaled(11, weight: .medium))
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ProgressBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.15))
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

#Preview("On track") {
    ScrollView {
        WeeklyCheckInCard(
            checkIn: WeeklyCheckIn(
                weight: .init(
                    currentKg: 79.8,
                    changeKgPerWeek: -0.4,
                    weighInsThisWeek: 5,
                    trend: (0..<10).map { .init(date: .now.addingTimeInterval(Double($0) * 86_400), kg: 80.4 - Double($0) * 0.07) }
                ),
                nutrition: .init(
                    loggedDays: 6, averageKcal: 2050, previousAverageKcal: 2200, targetKcal: 2000,
                    kcalAdherence: 0.83, averageProteinG: 152, targetProteinG: 150, proteinAdherence: 0.67
                ),
                training: .init(days: 3, previousDays: 4, goal: 4, goalSource: .planned),
                sleep: .init(averageHours: 7.4, previousAverageHours: 6.9),
                suggestion: .planWorkouts(goal: 4)
            ),
            unit: .metric
        )
        .padding(Spacing.screenPadding)
    }
    .background(AppColor.background)
}

#Preview("No weigh-ins") {
    ScrollView {
        WeeklyCheckInCard(
            checkIn: WeeklyCheckIn(
                weight: nil,
                nutrition: nil,
                training: .init(days: 2, previousDays: 3, goal: 3, goalSource: .usual),
                sleep: nil,
                suggestion: .planWorkouts(goal: 3)
            ),
            unit: .metric,
            onLogWeight: {}
        )
        .padding(Spacing.screenPadding)
    }
    .background(AppColor.background)
}
