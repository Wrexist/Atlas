import SwiftUI

/// "Sleep" on the Biology tab: the last two weeks of nights from Apple
/// Health, reduced by `SleepInsightsEngine` to duration, efficiency,
/// stages, the regularity of bedtime and wake time, and sleep debt.
/// The parent shows it only once `load()` finds at least
/// `SleepInsightsEngine.minNights` nights, so a new user never sees a
/// card of dashes. Last night's wrist temperature, when Apple Watch has
/// recorded enough nights for a baseline, rides along as one quiet row.
struct SleepInsightsSection: View {
    let insights: SleepInsightsEngine.Insights
    var wristTemperature: WristTemperatureEngine.Deviation?
    var unit: MeasurementUnit = .metric

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            BiologySectionHeader(
                title: "Sleep",
                subtitle: "Last \(insights.nightCount) nights from Apple Health"
            )
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    summary(insights)
                    if let shares = insights.stageShares {
                        stages(shares)
                    }
                    Divider().overlay(AppColor.glassBorder)
                    clock(insights)
                    debt(insights)
                    if let wristTemperature {
                        wristTemperatureRow(wristTemperature)
                            .transition(.opacity)
                    }
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

    // MARK: - Rows

    private func summary(_ insights: SleepInsightsEngine.Insights) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(Self.duration(insights.averageAsleep))
                    .font(AppFont.scaled(28, weight: .light, relativeTo: .title1))
                    .fontDesign(.rounded)
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
                Text("Average asleep")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                Text(insights.efficiency.formatted(.percent.precision(.fractionLength(0))))
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .monospacedDigit()
                Text("Efficiency")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func stages(_ shares: SleepInsightsEngine.StageShares) -> some View {
        let parts: [(LocalizedStringKey, Double, Color)] = [
            ("Deep sleep", shares.deep, AppColor.metricHRV),
            ("Core sleep", shares.core, AppColor.accentLight),
            ("REM sleep", shares.rem, AppColor.metricSleep),
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

            HStack(alignment: .top, spacing: Spacing.md) {
                ForEach(parts.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(parts[index].1.formatted(.percent.precision(.fractionLength(0))))
                            .font(AppFont.scaled(16, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .monospacedDigit()
                        HStack(spacing: Spacing.xs) {
                            Circle()
                                .fill(parts[index].2)
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            Text(parts[index].0)
                                .font(AppFont.scaled(13))
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func clock(_ insights: SleepInsightsEngine.Insights) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            row(
                icon: "moon.fill",
                title: "Bedtime",
                value: Text("\(Self.time(insights.averageBedtime)) ± \(Self.minutes(insights.bedtimeSpread))")
            )
            row(
                icon: "sunrise.fill",
                title: "Wake time",
                value: Text("\(Self.time(insights.averageWake)) ± \(Self.minutes(insights.wakeSpread))")
            )
            Text(Self.consistencyText(insights.consistency))
                .font(AppFont.scaled(13))
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func debt(_ insights: SleepInsightsEngine.Insights) -> some View {
        row(
            icon: "hourglass",
            title: "Sleep debt, last 7 nights",
            value: insights.sleepDebt < 60
                ? Text("None")
                : Text(Self.duration(insights.sleepDebt))
        )
    }

    private func wristTemperatureRow(_ deviation: WristTemperatureEngine.Deviation) -> some View {
        HStack(spacing: Spacing.md) {
            rowIcon("thermometer.medium")
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Wrist temperature")
                    .font(AppFont.scaled(16))
                    .foregroundStyle(AppColor.textPrimary)
                Text("Last night vs your baseline")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: Spacing.sm)
            Text(Self.temperatureDelta(deviation.celsius, unit: unit))
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }

    private func row(icon: String, title: LocalizedStringKey, value: Text) -> some View {
        HStack(spacing: Spacing.md) {
            rowIcon(icon)
            Text(title)
                .font(AppFont.scaled(16))
                .foregroundStyle(AppColor.textPrimary)
            Spacer(minLength: Spacing.sm)
            value
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func rowIcon(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(AppFont.scaled(13, weight: .semibold))
            .foregroundStyle(AppColor.metricSleep)
            .frame(width: 28, height: 28)
            .background {
                RoundedRectangle(cornerRadius: Spacing.chipCornerRadius, style: .continuous)
                    .fill(AppColor.metricSleep.opacity(0.15))
            }
            .accessibilityHidden(true)
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
        let start = Calendar.current.startOfDay(for: .now)
        return start.addingTimeInterval(minutesAfterMidnight.rounded() * 60)
            .formatted(date: .omitted, time: .shortened)
    }

    private static func consistencyText(_ consistency: SleepInsightsEngine.Consistency) -> LocalizedStringKey {
        switch consistency {
        case .steady: "Your sleep schedule is steady. A regular clock helps recovery."
        case .variable: "Your sleep schedule shifts by up to an hour. Steadier times help recovery."
        case .irregular: "Your sleep schedule shifts by more than an hour. Try going to bed and waking at the same times."
        }
    }
}
