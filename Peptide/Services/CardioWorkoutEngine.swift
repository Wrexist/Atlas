import Foundation

/// Labels and totals for the workouts Apple Health hands the training
/// history (`ImportedCardioWorkout`).
enum CardioWorkoutEngine {
    /// How far back the history looks. Fetched on each visit, never stored.
    static let historyWindowDays = 30

    /// The types the type picker lists first. Diving leads because the
    /// Health app's own label for a dive often reads as a plain "Workout".
    static let suggestedTypes: [CardioActivity] = [
        .diving, .strength, .swimming, .running, .walking, .cycling, .hiit, .yoga,
    ]

    /// Every other pickable type, alphabetical in the user's language.
    /// `.other` is left out: picking "Workout" is what the user is undoing.
    static func moreTypes() -> [CardioActivity] {
        CardioActivity.allCases
            .filter { $0 != .other && !suggestedTypes.contains($0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Kilometres or miles, following the user's unit setting. Nil when
    /// the workout recorded no distance.
    static func distance(meters: Double?, unit: MeasurementUnit) -> Measurement<UnitLength>? {
        guard let meters, meters > 0 else { return nil }
        let target: UnitLength = unit == .metric ? .kilometers : .miles
        return Measurement(value: meters, unit: UnitLength.meters).converted(to: target)
    }

    /// "5.23 km" — two decimals under ten, one above, so a long ride
    /// doesn't read as more precise than the GPS was.
    static func distanceLabel(meters: Double?, unit: MeasurementUnit, locale: Locale = .autoupdatingCurrent) -> String? {
        guard let distance = distance(meters: meters, unit: unit) else { return nil }
        let digits = distance.value < 10 ? 2 : 1
        let style = Measurement<UnitLength>.FormatStyle(
            width: .abbreviated,
            locale: locale,
            usage: .asProvided,
            numberFormatStyle: FloatingPointFormatStyle<Double>(locale: locale).precision(.fractionLength(digits))
        )
        return distance.formatted(style)
    }

    /// "1 hr, 5 min", rounded to the minute.
    static func durationLabel(_ seconds: TimeInterval) -> String {
        let minutes = max(1, (seconds / 60).rounded())
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    static func energyLabel(_ kilocalories: Double?) -> String? {
        guard let kilocalories, kilocalories >= 1 else { return nil }
        return String(localized: "\(Int(kilocalories.rounded())) kcal")
    }

    static func heartRateLabel(_ beatsPerMinute: Double?) -> String? {
        guard let beatsPerMinute, beatsPerMinute > 0 else { return nil }
        return String(localized: "\(Int(beatsPerMinute.rounded())) bpm")
    }

    /// Whole minutes of the workouts that started in the calendar week
    /// containing `now`, by the calendar's own first weekday.
    static func minutesThisWeek(
        _ workouts: [ImportedCardioWorkout],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        let seconds = workouts
            .filter { $0.start >= week.start && $0.start < week.end }
            .reduce(0) { $0 + $1.duration }
        return Int((seconds / 60).rounded())
    }

    /// The row's second line: distance, energy and where it came from,
    /// leaving out whatever the workout didn't record.
    static func summary(
        of workout: ImportedCardioWorkout,
        unit: MeasurementUnit,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        [
            distanceLabel(meters: workout.distanceMeters, unit: unit, locale: locale),
            energyLabel(workout.activeKilocalories),
            workout.sourceName.isEmpty ? nil : workout.sourceName,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}
