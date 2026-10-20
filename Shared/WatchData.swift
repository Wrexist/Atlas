import Foundation

struct WatchEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let protocolId: UUID
    let peptideName: String
    let abbreviation: String
    let dose: String
    /// Wall-clock time the dose is scheduled for. Stored as a Date and
    /// transported over the WatchConnectivity JSON pipeline using the
    /// `.iso8601` encoding strategy on both ends, so display formatting
    /// stays a UI concern instead of leaking locale assumptions into the
    /// payload (which previously made `scheduledTime` unparseable for any
    /// non-en_US user).
    let scheduledTime: Date
    var completed: Bool
}

/// Compact nutrition snapshot for the Watch app. Mirrors the
/// macro-ring data shown on the iOS Meals tab so the Watch
/// surface can render a coherent "where am I against my target
/// today" glance without depending on shared types from the
/// iOS-only target. Optional throughout so the Watch app can
/// hide nutrition gracefully on installs where the user hasn't
/// logged anything yet.
struct WatchNutritionSnapshot: Codable, Hashable, Sendable {
    let caloriesToday: Int
    let calorieTarget: Int
    let proteinToday: Int
    let proteinTarget: Int
    let mealLoggingStreak: Int
    /// Number of meal entries logged today — drives the
    /// "3 meals logged" subtitle on the Watch view.
    let mealEntriesToday: Int

    var calorieProgress: Double {
        guard calorieTarget > 0 else { return 0 }
        return min(1.0, Double(caloriesToday) / Double(calorieTarget))
    }

    var proteinProgress: Double {
        guard proteinTarget > 0 else { return 0 }
        return min(1.0, Double(proteinToday) / Double(proteinTarget))
    }
}

/// Recovery and sleep glance for the Watch. Computed on the phone — the
/// Watch app holds no HealthKit entitlement, and computing here keeps the
/// wrist reading the same Recovery number the iPhone Today screen shows.
/// Every metric is optional: a user with HRV but no resting heart rate
/// still gets the fields they have.
struct WatchVitalsSnapshot: Codable, Hashable, Sendable {
    /// 0…100, from `RecoveryScoreEngine`.
    let recoveryScore: Int?
    /// 3-day average resting heart rate, bpm.
    let restingHeartRate: Int?
    /// 30-day average resting heart rate, bpm.
    let restingHeartRateBaseline: Int?
    /// 3-day average HRV (SDNN), ms.
    let hrv: Int?
    /// 30-day average HRV (SDNN), ms.
    let hrvBaseline: Int?
    let sleep: WatchSleepSnapshot?
    /// When the phone ran the HealthKit queries this snapshot came from.
    let measuredAt: Date
}

/// Last night, split by stage. Sources that only record "asleep" (most
/// third-party trackers, iPhone-only sleep) land in `unspecifiedMinutes`
/// and `hasStages` is false.
struct WatchSleepSnapshot: Codable, Hashable, Sendable {
    /// 0…100, from `SleepScoreEngine`.
    let score: Int
    let start: Date
    let end: Date
    let deepMinutes: Int
    let coreMinutes: Int
    let remMinutes: Int
    let unspecifiedMinutes: Int
    let awakeMinutes: Int

    var asleepMinutes: Int { deepMinutes + coreMinutes + remMinutes + unspecifiedMinutes }
    /// Staged only when most of the night carries stages. A mostly
    /// unspecified night with a few staged minutes is shown and scored as
    /// one "Asleep" block, matching `SleepScoreEngine.Night.hasStages`.
    var hasStages: Bool {
        asleepMinutes > 0 && Double(deepMinutes + coreMinutes + remMinutes) / Double(asleepMinutes) >= 0.5
    }
    var band: SleepBand { SleepBand(score: score) }
}

/// Score bands for the sleep glance, on the cut-points and names Apple's
/// own Sleep Score uses since watchOS 26.2, so the two never disagree
/// about what "High" means.
enum SleepBand: Sendable {
    case veryLow, low, ok, high, veryHigh

    init(score: Int) {
        switch score {
        case ..<41: self = .veryLow
        case 41..<61: self = .low
        case 61..<81: self = .ok
        case 81..<96: self = .high
        default: self = .veryHigh
        }
    }

    var label: String {
        switch self {
        case .veryLow: return String(localized: "Very Low")
        case .low: return String(localized: "Low")
        case .ok: return String(localized: "OK")
        case .high: return String(localized: "High")
        case .veryHigh: return String(localized: "Very High")
        }
    }
}

struct WatchData: Codable, Sendable {
    private(set) var todayEntries: [WatchEntry]
    private(set) var completedToday: Int
    private(set) var totalToday: Int
    let lastUpdated: Date
    /// Current dose-logging streak. Decode-if-present so a phone running an
    /// older build that doesn't write this field still decodes cleanly on
    /// the watch — the watch app should render "—" rather than fail.
    let currentStreak: Int?
    /// 7-day compliance as a 0…1 fraction. Same back-compat policy.
    let weeklyCompliance: Double?
    /// Total completed doses ever. Surfaced on the Watch Stats view.
    let totalDosesLogged: Int?
    /// Today's nutrition snapshot. Optional so an older build that
    /// doesn't write this field still decodes on the watch — the
    /// nutrition surface hides itself gracefully when absent.
    let nutrition: WatchNutritionSnapshot?
    /// Atlas Score (cumulative momentum) + level/tier/progress for the
    /// Watch complications. Decode-if-present like the fields above so an
    /// older phone build that doesn't write them still decodes on the watch.
    let atlasScore: Int?
    let atlasLevel: Int?
    /// Tier rawValue — bronze/silver/gold/platinum/diamond — mapped to a
    /// tint widget-side (which can't see the app's MomentumEngine).
    let atlasTier: String?
    /// 0…1 progress toward the next level.
    let atlasProgress: Double?
    /// Points banked today (drives the "+N today" affordance).
    let atlasTodayEarned: Int?
    /// Today's habit completion split by domain — health (green) and
    /// training/fitness (blue) — powering the color-coded complications.
    let healthHabitsDone: Int?
    let healthHabitsTotal: Int?
    let trainingHabitsDone: Int?
    let trainingHabitsTotal: Int?
    /// `MeasurementUnit` rawValue — "metric" or "imperial". A String for
    /// the same reason `atlasTier` is: this file is shared with the watch
    /// and widget targets, which cannot see the app target's model types.
    /// Water is stored in fluid ounces, so without this the watch showed
    /// ounces to a user whose phone was set to millilitres.
    let measurementUnit: String?
    /// Recovery + sleep. Nil when Apple Health isn't connected on the
    /// phone; the Watch hides the Recovery and Sleep pages in that case.
    let vitals: WatchVitalsSnapshot?
    /// The workout in progress on the phone, or nil. Drives the Watch's
    /// Workout page and the live state of the Training complication.
    private(set) var workout: WatchWorkoutSnapshot?
    /// This week's training, for the Training complication between workouts.
    let training: WatchTrainingSnapshot?

    var compliance: Double {
        totalToday > 0 ? Double(completedToday) / Double(totalToday) : 0
    }

    init(
        todayEntries: [WatchEntry],
        completedToday: Int,
        totalToday: Int,
        lastUpdated: Date,
        currentStreak: Int? = nil,
        weeklyCompliance: Double? = nil,
        totalDosesLogged: Int? = nil,
        nutrition: WatchNutritionSnapshot? = nil,
        atlasScore: Int? = nil,
        atlasLevel: Int? = nil,
        atlasTier: String? = nil,
        atlasProgress: Double? = nil,
        atlasTodayEarned: Int? = nil,
        healthHabitsDone: Int? = nil,
        healthHabitsTotal: Int? = nil,
        trainingHabitsDone: Int? = nil,
        trainingHabitsTotal: Int? = nil,
        measurementUnit: String? = nil,
        vitals: WatchVitalsSnapshot? = nil,
        workout: WatchWorkoutSnapshot? = nil,
        training: WatchTrainingSnapshot? = nil
    ) {
        self.todayEntries = todayEntries
        self.completedToday = completedToday
        self.totalToday = totalToday
        self.lastUpdated = lastUpdated
        self.currentStreak = currentStreak
        self.weeklyCompliance = weeklyCompliance
        self.totalDosesLogged = totalDosesLogged
        self.nutrition = nutrition
        self.atlasScore = atlasScore
        self.atlasLevel = atlasLevel
        self.atlasTier = atlasTier
        self.atlasProgress = atlasProgress
        self.atlasTodayEarned = atlasTodayEarned
        self.healthHabitsDone = healthHabitsDone
        self.healthHabitsTotal = healthHabitsTotal
        self.trainingHabitsDone = trainingHabitsDone
        self.trainingHabitsTotal = trainingHabitsTotal
        self.measurementUnit = measurementUnit
        self.vitals = vitals
        self.workout = workout
        self.training = training
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        todayEntries = try c.decode([WatchEntry].self, forKey: .todayEntries)
        completedToday = try c.decode(Int.self, forKey: .completedToday)
        totalToday = try c.decode(Int.self, forKey: .totalToday)
        lastUpdated = try c.decode(Date.self, forKey: .lastUpdated)
        currentStreak = try c.decodeIfPresent(Int.self, forKey: .currentStreak)
        weeklyCompliance = try c.decodeIfPresent(Double.self, forKey: .weeklyCompliance)
        totalDosesLogged = try c.decodeIfPresent(Int.self, forKey: .totalDosesLogged)
        nutrition = try c.decodeIfPresent(WatchNutritionSnapshot.self, forKey: .nutrition)
        atlasScore = try c.decodeIfPresent(Int.self, forKey: .atlasScore)
        atlasLevel = try c.decodeIfPresent(Int.self, forKey: .atlasLevel)
        atlasTier = try c.decodeIfPresent(String.self, forKey: .atlasTier)
        atlasProgress = try c.decodeIfPresent(Double.self, forKey: .atlasProgress)
        atlasTodayEarned = try c.decodeIfPresent(Int.self, forKey: .atlasTodayEarned)
        healthHabitsDone = try c.decodeIfPresent(Int.self, forKey: .healthHabitsDone)
        healthHabitsTotal = try c.decodeIfPresent(Int.self, forKey: .healthHabitsTotal)
        trainingHabitsDone = try c.decodeIfPresent(Int.self, forKey: .trainingHabitsDone)
        trainingHabitsTotal = try c.decodeIfPresent(Int.self, forKey: .trainingHabitsTotal)
        measurementUnit = try c.decodeIfPresent(String.self, forKey: .measurementUnit)
        vitals = try c.decodeIfPresent(WatchVitalsSnapshot.self, forKey: .vitals)
        workout = try c.decodeIfPresent(WatchWorkoutSnapshot.self, forKey: .workout)
        training = try c.decodeIfPresent(WatchTrainingSnapshot.self, forKey: .training)
    }

    /// The same snapshot with a new dose list — what an optimistic Watch
    /// tap needs. Copying and mutating carries every other field forward;
    /// rebuilding through the memberwise init silently dropped whichever
    /// ones the caller forgot to re-pass.
    func replacingEntries(_ entries: [WatchEntry]) -> WatchData {
        var copy = self
        copy.todayEntries = entries
        copy.completedToday = entries.filter(\.completed).count
        copy.totalToday = entries.count
        return copy
    }

    /// The same snapshot with a new workout state, for an optimistic
    /// Watch tap and for the phone's set-by-set pushes.
    func replacingWorkout(_ workout: WatchWorkoutSnapshot?) -> WatchData {
        var copy = self
        copy.workout = workout
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case todayEntries, completedToday, totalToday, lastUpdated
        case currentStreak, weeklyCompliance, totalDosesLogged
        case nutrition
        case atlasScore, atlasLevel, atlasTier, atlasProgress, atlasTodayEarned
        case healthHabitsDone, healthHabitsTotal
        case trainingHabitsDone, trainingHabitsTotal
        case measurementUnit
        case vitals
        case workout, training
    }

    static let empty = WatchData(
        todayEntries: [],
        completedToday: 0,
        totalToday: 0,
        lastUpdated: .distantPast
    )
}

enum WatchMessage {
    static let markComplete = "markComplete"
    static let markIncomplete = "markIncomplete"
    static let entryIdKey = "entryId"
    static let protocolIdKey = "protocolId"
    /// Watch → phone "log water" command. Carries `ozKey` with an
    /// integer ounces amount. The phone applies the log through
    /// the same `dataStore.logWater` path used by the in-app
    /// quick-add chips, so widget reload + Watch sync + HK write
    /// all fire for free.
    static let logWater = "logWater"
    static let ozKey = "oz"
    /// Watch → phone workout command. Carries `workoutRequestKey` with a
    /// JSON-encoded `WatchWorkoutRequest`.
    static let workout = "workout"
    static let workoutRequestKey = "request"
}
