import Foundation

/// User preferences scoped to training. Lives on `UserProfile` (added
/// as an optional field so existing profiles decode cleanly) and is
/// populated during onboarding's "Activity & schedule" + "Equipment
/// access" steps in the redesigned flow.
///
/// Kept separate from `BodyMetrics` because training prefs change at
/// a different cadence (gym moves, schedule shifts) than body
/// composition.
struct TrainingPreferences: Codable, Hashable, Sendable {
    var daysPerWeek: Int
    var preferredDays: Set<Weekday>
    var timeOfDay: PreferredTimeOfDay
    /// Default rest seconds applied when neither the routine nor the
    /// exercise specifies one. 90s lines up with the literature
    /// midpoint for hypertrophy work.
    var restTimerDefault: Int
    /// Kilo plates the user has access to. Drives the plate calculator
    /// and the smallest barbell jump in `ProgressionEngine`. Read through
    /// `plates(for:)`, which picks this or the pound set by display unit.
    var plateInventoryKg: [Double]
    /// Pound plates, nil until edited (reads as the standard pound set).
    /// A separate set rather than a conversion: a 45 lb plate is not a
    /// round number of kilos, and gyms stock one system or the other.
    var plateInventoryLb: [Double]?
    /// Empty-bar weights the user changed, by `BarKind` raw value. One
    /// map per unit for the same reason as the plates; an absent bar
    /// reads as `BarKind.standardWeight(for:)`.
    var barWeightsKg: [String: Double]?
    var barWeightsLb: [String: Double]?
    /// When true, sessions that hit the routine's target reps on every
    /// set auto-bump the recommended working weight on the next
    /// occurrence of the exercise.
    var autoProgression: Bool
    /// Equipment categories the user has access to. Filters the
    /// exercise library and the program recommendation engine.
    /// Defaults to `[.bodyweight]` — sensible floor that still lets
    /// the app function before onboarding completes.
    var equipmentAccess: Set<EquipmentKind>

    init(
        daysPerWeek: Int = 3,
        preferredDays: Set<Weekday> = [],
        timeOfDay: PreferredTimeOfDay = .anytime,
        restTimerDefault: Int = 90,
        plateInventoryKg: [Double] = TrainingPreferences.defaultPlatesKg,
        autoProgression: Bool = true,
        equipmentAccess: Set<EquipmentKind> = [.bodyweight]
    ) {
        self.daysPerWeek = daysPerWeek
        self.preferredDays = preferredDays
        self.timeOfDay = timeOfDay
        self.restTimerDefault = restTimerDefault
        self.plateInventoryKg = plateInventoryKg
        self.autoProgression = autoProgression
        self.equipmentAccess = equipmentAccess
    }

    /// Plates that ship pre-selected for a typical commercial gym (kg).
    /// The user can edit them in Profile → Training.
    static let defaultPlatesKg: [Double] = PlateCalculatorEngine.kilogramPlates

    /// Plates available in `unit`, in that unit.
    func plates(for unit: MeasurementUnit) -> [Double] {
        unit == .metric ? plateInventoryKg : (plateInventoryLb ?? PlateCalculatorEngine.poundPlates)
    }

    mutating func setPlates(_ plates: [Double], for unit: MeasurementUnit) {
        if unit == .metric { plateInventoryKg = plates } else { plateInventoryLb = plates }
    }

    /// Empty weight of `bar`, in `unit`.
    func barWeight(_ bar: BarKind, unit: MeasurementUnit) -> Double {
        let custom = unit == .metric ? barWeightsKg : barWeightsLb
        return custom?[bar.rawValue] ?? bar.standardWeight(for: unit)
    }

    mutating func setBarWeight(_ weight: Double, for bar: BarKind, unit: MeasurementUnit) {
        if unit == .metric {
            barWeightsKg = (barWeightsKg ?? [:]).merging([bar.rawValue: weight]) { _, new in new }
        } else {
            barWeightsLb = (barWeightsLb ?? [:]).merging([bar.rawValue: weight]) { _, new in new }
        }
    }
}

enum Weekday: String, Codable, CaseIterable, Identifiable, Sendable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .monday:    return "Mon"
        case .tuesday:   return "Tue"
        case .wednesday: return "Wed"
        case .thursday:  return "Thu"
        case .friday:    return "Fri"
        case .saturday:  return "Sat"
        case .sunday:    return "Sun"
        }
    }

    /// `Calendar` API uses 1=Sunday … 7=Saturday. Map onto our
    /// Monday-first enum so the onboarding picker can compose
    /// against the user's locale calendar without leaking the
    /// 1-indexed numbering through the model.
    var calendarWeekdayValue: Int {
        switch self {
        case .sunday:    return 1
        case .monday:    return 2
        case .tuesday:   return 3
        case .wednesday: return 4
        case .thursday:  return 5
        case .friday:    return 6
        case .saturday:  return 7
        }
    }
}

enum PreferredTimeOfDay: String, Codable, CaseIterable, Identifiable, Sendable {
    case morning, midday, evening, anytime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .morning:  return "Morning"
        case .midday:   return "Midday"
        case .evening:  return "Evening"
        case .anytime:  return "Anytime"
        }
    }
}
