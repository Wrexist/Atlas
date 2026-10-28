import Foundation

/// Builds the weekly check-in: weight trend, calorie and protein adherence,
/// training days and sleep for the last seven days against the seven
/// before, plus one rule-based suggestion for next week. Pure — the caller
/// passes everything in, including the calendar and the current time.
enum WeeklyCheckInEngine {
    /// Per-day weight of the exponential trend. A gap of several days
    /// between weigh-ins counts as that many days of smoothing, so sparse
    /// logging still converges on the real weight.
    static let trendSmoothing = 0.25
    /// Week-on-week movement smaller than this reads as standing still.
    static let stallThresholdKg = 0.2
    /// A day hits the calorie target within ±10% of it.
    static let calorieTolerance = 0.10
    /// A day hits the protein target at 90% of it or more.
    static let proteinFloor = 0.90
    /// Losing more than 1% of body weight a week costs muscle.
    static let fastLossFraction = 0.01
    /// Gaining more than 0.5% a week on a lean bulk is mostly fat.
    static let fastGainFraction = 0.005
    /// The size of every calorie nudge.
    static let adjustmentKcal = 150
    /// Below this, a share of days is too noisy to coach on.
    static let minimumLoggedDays = 3
    static let poorAdherence = 0.5
    static let sleepFloorHours = 7.0
    static let minimumWeighIns = 3

    /// The check-in is surfaced on Today at the turn of the week.
    static func isCheckInDay(_ now: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: now)
        return weekday == 1 || weekday == 2  // Sunday, Monday
    }

    /// Nil when nothing was logged in the last four weeks.
    static func build(
        weights: [WeightEntry],
        consumption: [DailyConsumption],
        targets: NutritionTargets?,
        goalRaw: String?,
        workoutDates: [Date],
        plannedWorkoutsPerWeek: Int?,
        sleepHours: [(date: Date, value: Double)],
        now: Date,
        calendar: Calendar
    ) -> WeeklyCheckIn? {
        let weeks = (0..<4).compactMap { week($0, before: now, calendar: calendar) }
        guard weeks.count == 4 else { return nil }

        let weight = weightSection(weights, weeks: weeks, calendar: calendar)
        let nutrition = nutritionSection(consumption, targets: targets, weeks: weeks, calendar: calendar)
        let training = trainingSection(workoutDates, planned: plannedWorkoutsPerWeek, weeks: weeks, calendar: calendar)
        let sleep = sleepSection(sleepHours, weeks: weeks)
        guard weight != nil || nutrition != nil || training != nil || sleep != nil else { return nil }

        let intent = NutritionMath.GoalIntent(goalRaw: goalRaw)
        return WeeklyCheckIn(
            weight: weight,
            nutrition: nutrition,
            training: training,
            sleep: sleep,
            suggestion: suggestion(
                weight: weight,
                stalled: isStalled(weights, weeks: weeks),
                nutrition: nutrition,
                training: training,
                sleep: sleep,
                intent: intent
            )
        )
    }

    /// Seven whole days; week 0 ends with today.
    static func week(_ weeksBack: Int, before now: Date, calendar: Calendar) -> Range<Date>? {
        let today = calendar.startOfDay(for: now)
        guard
            let end = calendar.date(byAdding: .day, value: 1 - 7 * weeksBack, to: today),
            let start = calendar.date(byAdding: .day, value: -7, to: end)
        else { return nil }
        return start..<end
    }

    // MARK: - Weight

    static func weightSection(
        _ weights: [WeightEntry],
        weeks: [Range<Date>],
        calendar: Calendar
    ) -> WeeklyCheckIn.Weight? {
        let thisWeek = weights.filter { weeks[0].contains($0.date) }
        let lastWeek = weights.filter { weeks[1].contains($0.date) }
        let latest = (thisWeek + lastWeek).max { $0.date < $1.date }
        guard let current = average(thisWeek.map(\.kg)) ?? latest?.kg else { return nil }

        let change = average(thisWeek.map(\.kg)).flatMap { now in
            average(lastWeek.map(\.kg)).map { now - $0 }
        }
        let fortnight = weeks[1].lowerBound..<weeks[0].upperBound
        return WeeklyCheckIn.Weight(
            currentKg: current,
            changeKgPerWeek: change,
            weighInsThisWeek: thisWeek.count,
            trend: trend(weights, since: weeks[3].lowerBound, calendar: calendar)
                .filter { fortnight.contains($0.date) }
        )
    }

    /// Exponential moving average at each weigh-in from `start` on,
    /// weighted by the days between readings.
    static func trend(_ weights: [WeightEntry], since start: Date, calendar: Calendar) -> [WeeklyCheckIn.Point] {
        var points: [WeeklyCheckIn.Point] = []
        for entry in weights.filter({ $0.date >= start }).sorted(by: { $0.date < $1.date }) {
            guard let previous = points.last else {
                points.append(.init(date: entry.date, kg: entry.kg))
                continue
            }
            let gap = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: previous.date),
                to: calendar.startOfDay(for: entry.date)
            ).day ?? 1
            let alpha = 1 - pow(1 - trendSmoothing, Double(max(gap, 1)))
            points.append(.init(date: entry.date, kg: previous.kg + alpha * (entry.kg - previous.kg)))
        }
        return points
    }

    /// True when the weekly average has moved less than the threshold
    /// for two weeks running.
    static func isStalled(_ weights: [WeightEntry], weeks: [Range<Date>]) -> Bool {
        let averages = weeks.prefix(3).map { range in average(weights.filter { range.contains($0.date) }.map(\.kg)) }
        guard let now = averages[0], let last = averages[1], let before = averages[2] else { return false }
        return abs(now - last) < stallThresholdKg && abs(last - before) < stallThresholdKg
    }

    // MARK: - Nutrition

    static func nutritionSection(
        _ consumption: [DailyConsumption],
        targets: NutritionTargets?,
        weeks: [Range<Date>],
        calendar: Calendar
    ) -> WeeklyCheckIn.Nutrition? {
        let byDay = Dictionary(
            consumption.filter { $0.caloriesKcal > 0 }.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let thisWeek = byDay.filter { weeks[0].contains($0.key) }.map(\.value)
        let lastWeek = byDay.filter { weeks[1].contains($0.key) }.map(\.value)
        guard let kcal = average(thisWeek.map { Double($0.caloriesKcal) }),
              let protein = average(thisWeek.map { Double($0.proteinG) }) else { return nil }

        let targetKcal = targets.map(\.calories).flatMap { $0 > 0 ? $0 : nil }
        let targetProtein = targets.map(\.proteinG).flatMap { $0 > 0 ? $0 : nil }
        return WeeklyCheckIn.Nutrition(
            loggedDays: thisWeek.count,
            averageKcal: Int(kcal.rounded()),
            previousAverageKcal: average(lastWeek.map { Double($0.caloriesKcal) }).map { Int($0.rounded()) },
            targetKcal: targetKcal,
            kcalAdherence: targetKcal.map { target in
                share(of: thisWeek) { abs(Double($0.caloriesKcal - target)) <= Double(target) * calorieTolerance }
            },
            averageProteinG: Int(protein.rounded()),
            targetProteinG: targetProtein,
            proteinAdherence: targetProtein.map { target in
                share(of: thisWeek) { Double($0.proteinG) >= Double(target) * proteinFloor }
            }
        )
    }

    // MARK: - Training

    static func trainingSection(
        _ workoutDates: [Date],
        planned: Int?,
        weeks: [Range<Date>],
        calendar: Calendar
    ) -> WeeklyCheckIn.Training? {
        let daysPerWeek = weeks.map { range in
            Set(workoutDates.filter { range.contains($0) }.map { calendar.startOfDay(for: $0) }).count
        }
        let usual = Int((Double(daysPerWeek[1...].reduce(0, +)) / 3).rounded())
        var goal: Int?
        var goalSource: WeeklyCheckIn.Training.GoalSource?
        if let planned, planned > 0 {
            goal = planned
            goalSource = .planned
        } else if usual > 0 {
            goal = usual
            goalSource = .usual
        }
        guard goal != nil || daysPerWeek[0] > 0 || daysPerWeek[1] > 0 else { return nil }
        return WeeklyCheckIn.Training(
            days: daysPerWeek[0],
            previousDays: daysPerWeek[1],
            goal: goal,
            goalSource: goalSource
        )
    }

    // MARK: - Sleep

    static func sleepSection(
        _ series: [(date: Date, value: Double)],
        weeks: [Range<Date>]
    ) -> WeeklyCheckIn.Sleep? {
        let nights = series.filter { $0.value > 0 }
        guard let hours = average(nights.filter { weeks[0].contains($0.date) }.map(\.value)) else { return nil }
        return WeeklyCheckIn.Sleep(
            averageHours: hours,
            previousAverageHours: average(nights.filter { weeks[1].contains($0.date) }.map(\.value))
        )
    }

    // MARK: - Suggestion

    static func suggestion(
        weight: WeeklyCheckIn.Weight?,
        stalled: Bool,
        nutrition: WeeklyCheckIn.Nutrition?,
        training: WeeklyCheckIn.Training?,
        sleep: WeeklyCheckIn.Sleep?,
        intent: NutritionMath.GoalIntent
    ) -> WeeklyCheckIn.Suggestion {
        let coachable = (nutrition?.loggedDays ?? 0) >= minimumLoggedDays
        // A calorie nudge means nothing until the current target is met.
        if coachable, let adherence = nutrition?.kcalAdherence, adherence < poorAdherence {
            return .hitCalorieTarget
        }
        if let weightAdvice = weightSuggestion(weight, stalled: stalled, intent: intent) {
            return weightAdvice
        }
        if coachable, let adherence = nutrition?.proteinAdherence, adherence < poorAdherence {
            return .prioritizeProtein
        }
        if let training, let goal = training.goal, training.days < goal {
            return .planWorkouts(goal: goal)
        }
        if let sleep, sleep.averageHours < sleepFloorHours {
            return .prioritizeSleep
        }
        let tracksWeight = weight != nil || intent == .deficit || intent == .surplus
        if tracksWeight, (weight?.weighInsThisWeek ?? 0) < minimumWeighIns {
            return .weighInMore
        }
        return .keepGoing
    }

    private static func weightSuggestion(
        _ weight: WeeklyCheckIn.Weight?,
        stalled: Bool,
        intent: NutritionMath.GoalIntent
    ) -> WeeklyCheckIn.Suggestion? {
        guard let weight else { return nil }
        switch intent {
        case .deficit:
            if stalled { return .weightStalledEatLess(kcal: adjustmentKcal) }
            if let change = weight.changeKgPerWeek, -change > weight.currentKg * fastLossFraction {
                return .losingFast(kcal: adjustmentKcal)
            }
        case .surplus:
            if stalled { return .weightStalledEatMore(kcal: adjustmentKcal) }
            if let change = weight.changeKgPerWeek, change > weight.currentKg * fastGainFraction {
                return .gainingFast(kcal: adjustmentKcal)
            }
        case .recomp, .maintenance:
            break
        }
        return nil
    }

    // MARK: - Helpers

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func share<T>(of items: [T], where isHit: (T) -> Bool) -> Double {
        items.isEmpty ? 0 : Double(items.filter(isHit).count) / Double(items.count)
    }
}
