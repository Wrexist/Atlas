import SwiftUI

/// "Sleep" on the Biology tab: the last two weeks of nights from Apple
/// Health, reduced by `SleepInsightsEngine` to duration, efficiency,
/// stages, the regularity of bedtime and wake time, and sleep debt.
/// The parent shows it only once `load()` finds at least
/// `SleepInsightsEngine.minNights` nights, so a new user never sees a
/// card of dashes. Last night's wrist temperature, when Apple Watch has
/// recorded enough nights for a baseline, rides along as one more tile.
struct SleepInsightsSection: View {
    let insights: SleepInsightsEngine.Insights
    var wristTemperature: WristTemperatureEngine.Deviation?
    var unit: MeasurementUnit = .metric

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HomeSectionHeader(
                title: "Sleep",
                subtitle: "Last \(insights.nightCount) nights from Apple Health"
            )
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    summary(insights)
                    if let shares = insights.stageShares {
                        stages(shares)
                    }
                    tiles(insights)
                    consistencyNote(insights.consistency)
                }
            }
        }
        .biologyCardReveal()
    }

    /// The last two weeks of nights from Apple Health, or nil while there
    /// are too few to say anything.
    static func load(targetHours: Double = RecoveryScoreEngine.defaultSleepTargetHours) async -> SleepInsightsEngine.Insights? {
        let segments = await HealthKitService.shared.sleepSegments(nights: SleepInsightsEngine.windowNights)
        let nights = SleepScoreEngine.nights(from: segments, calendar: .current)
        return SleepInsightsEngine.insights(nights: nights, targetHours: targetHours, calendar: .current)
    }

    /// Last night's wrist temperature against the user's baseline, or nil
    /// without an Apple Watch reading from last night or enough nights before it.
    static func loadWristTemperature() async -> WristTemperatureEngine.Deviation? {
        let readings = await HealthKitService.shared.sleepingWristTemperatures(days: WristTemperatureEngine.readDays)
        return WristTemperatureEngine.deviation(readings: readings, now: .now, calendar: .current)
    }

    /// Two weeks of short, uneven nights for the screenshot demo.
    static let demoInsights = SleepInsightsEngine.Insights(
        nightCount: 14,
        averageAsleep: 5 * 3600 + 56 * 60,
        efficiency: 0.98,
        stageShares: .init(deep: 0.17, core: 0.58, rem: 0.25),
        averageBedtime: 52,
        averageWake: 6 * 60 + 57,
        bedtimeSpread: 70,
        wakeSpread: 104,
        sleepDebt: 17 * 3600 + 21 * 60
    )

    static let demoWristTemperature = WristTemperatureEngine.Deviation(
        night: .now,
        celsius: 0.1,
        baselineNights: 21,
        isLastNight: true
    )

    // MARK: - Rows

    private func summary(_ insights: SleepInsightsEngine.Insights) -> some View {
        let asleep = VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(Self.duration(insights.averageAsleep))
                .font(AppFont.scaled(28, weight: .light, relativeTo: .title1))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
            Text("Average asleep")
                .font(AppFont.scaled(13))
                .foregroundStyle(AppColor.textSecondary)
        }
        let efficiency = Text(insights.efficiency.formatted(.percent.precision(.fractionLength(0))))
            .font(AppFont.scaled(20, weight: .semibold))
            .foregroundStyle(AppColor.textPrimary)
            .monospacedDigit()
        let efficiencyLabel = Text("Efficiency")
            .font(AppFont.scaled(13))
            .foregroundStyle(AppColor.textSecondary)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                asleep
                Spacer()
                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                    efficiency
                    efficiencyLabel
                }
            }
            VStack(alignment: .leading, spacing: Spacing.md) {
                asleep
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    efficiency
                    efficiencyLabel
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func stages(_ shares: SleepInsightsEngine.StageShares) -> some View {
        let parts: [(LocalizedStringKey, Double, Color)] = [
            ("Deep sleep", shares.deep, AppColor.sleepDeep),
            ("Core sleep", shares.core, AppColor.sleepCore),
            ("REM sleep", shares.rem, AppColor.sleepREM),
        ]
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(parts.indices, id: \.self) { index in
                        Capsule()
                            .fill(parts[index].2)
                            .frame(width: max(0, proxy.size.width - 4) * parts[index].1)
                    }
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)

            // Three columns while the names fit; stacked rows otherwise,
            // so "Kärnsömn" never breaks mid-word.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    ForEach(parts.indices, id: \.self) { index in
                        stageLegend(name: parts[index].0, share: parts[index].1, tint: parts[index].2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(parts.indices, id: \.self) { index in
                        stageLegend(name: parts[index].0, share: parts[index].1, tint: parts[index].2)
                    }
                }
            }
        }
    }

    private func stageLegend(name: LocalizedStringKey, share: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(share.formatted(.percent.precision(.fractionLength(0))))
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(name)
                    .font(AppFont.scaled(13))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The schedule, the debt and the temperature as one grid of the
    /// app's stat tiles: each number leads, its name sits under it, and
    /// the qualifier ("varies 1 h 10 min") gets its own line instead of
    /// a "±" squeezed beside the time.
    private func tiles(_ insights: SleepInsightsEngine.Insights) -> some View {
        let columnCount = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.sm, alignment: .top), count: columnCount)
        return LazyVGrid(columns: columns, spacing: Spacing.sm) {
            StatTile(
                label: "Bedtime",
                value: Self.time(insights.averageBedtime),
                icon: "moon.fill",
                tint: AppColor.accentPrimary,
                footnote: String(localized: "Varies \(Self.minutes(insights.bedtimeSpread))")
            )
            StatTile(
                label: "Wake time",
                value: Self.time(insights.averageWake),
                icon: "sunrise.fill",
                tint: AppColor.accentPrimary,
                footnote: String(localized: "Varies \(Self.minutes(insights.wakeSpread))")
            )
            StatTile(
                label: "Sleep debt",
                value: insights.sleepDebt < 60
                    ? String(localized: "None")
                    : Self.duration(insights.sleepDebt),
                icon: "hourglass",
                tint: AppColor.accentPrimary,
                footnote: String(localized: "Short of your goal, last 7 nights")
            )
            if let wristTemperature {
                StatTile(
                    label: "Wrist temp",
                    value: Self.temperatureDelta(wristTemperature.celsius, unit: unit),
                    icon: "thermometer.medium",
                    tint: AppColor.accentPrimary,
                    footnote: wristTemperature.isLastNight
                        ? String(localized: "Last night vs your normal")
                        : String(localized: "Night before last vs your normal")
                )
                .transition(.opacity)
            }
        }
    }

    /// One plain-language line on how regular the schedule is, with a
    /// mark that says at a glance whether it is good news.
    private func consistencyNote(_ consistency: SleepInsightsEngine.Consistency) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: consistency == .steady ? "checkmark.circle.fill" : "info.circle.fill")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(consistency == .steady ? AppColor.success : AppColor.textSecondary)
                .accessibilityHidden(true)
            Text(Self.consistencyText(consistency))
                .font(AppFont.scaled(13))
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Formatting

    /// Signed, one decimal, in the user's unit: "+0.3 °C", "−0.5 °F".
    private static func temperatureDelta(_ celsius: Double, unit: MeasurementUnit) -> String {
        let delta = WristTemperatureEngine.displayDelta(celsius, unit: unit)
        let number = delta.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
        return number + (unit == .imperial ? " °F" : " °C")
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded()).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    private static func minutes(_ value: Double) -> String {
        Duration.seconds((value * 60).rounded()).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    private static func time(_ minutesAfterMidnight: Double) -> String {
        SleepInsightsEngine.clockTime(minutesAfterMidnight: minutesAfterMidnight, on: .now, calendar: .current)
            .formatted(date: .omitted, time: .shortened)
    }

    private static func consistencyText(_ consistency: SleepInsightsEngine.Consistency) -> LocalizedStringKey {
        switch consistency {
        case .steady: "Your bed and wake times are steady. That helps recovery."
        case .variable: "Your bed and wake times shift by up to an hour. Steadier times help recovery."
        case .irregular: "Your bed and wake times shift by more than an hour. Aim for the same times every day."
        }
    }
}
