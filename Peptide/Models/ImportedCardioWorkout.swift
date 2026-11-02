import Foundation
import HealthKit

/// A workout another app or device saved to Apple Health — an Apple Watch
/// run, a Strava ride. Read on demand for the training history and never
/// stored, so Health stays the only copy.
struct ImportedCardioWorkout: Identifiable, Hashable, Sendable {
    /// The HealthKit sample's uuid.
    let id: UUID
    let activity: CardioActivity
    let start: Date
    /// Seconds.
    let duration: TimeInterval
    let distanceMeters: Double?
    let activeKilocalories: Double?
    /// Beats per minute.
    let averageHeartRate: Double?
    /// The app or device that recorded it ("Strava", "Apple Watch").
    let sourceName: String

    var end: Date { start.addingTimeInterval(duration) }
}

/// The kinds of workout the history tells apart. HealthKit has ~80
/// activity types; the long tail lands in `.other`.
enum CardioActivity: String, CaseIterable, Sendable {
    case running, walking, hiking, cycling, swimming, rowing, elliptical
    case stairs, hiit, mixedCardio, crossTraining, jumpRope, dance
    case yoga, pilates, coreTraining, flexibility, cooldown, strength
    case boxing, martialArts, climbing, downhillSkiing, crossCountrySkiing
    case snowboarding, paddling, surfing, tennis, racketSports, soccer
    case basketball, teamSports, golf, wheelchair, other

    init(_ type: HKWorkoutActivityType) {
        switch type {
        case .running: self = .running
        case .walking: self = .walking
        case .hiking: self = .hiking
        case .cycling, .handCycling: self = .cycling
        case .swimming: self = .swimming
        case .rowing: self = .rowing
        case .elliptical: self = .elliptical
        case .stairClimbing, .stairs, .stepTraining: self = .stairs
        case .highIntensityIntervalTraining: self = .hiit
        case .mixedCardio: self = .mixedCardio
        case .crossTraining: self = .crossTraining
        case .jumpRope: self = .jumpRope
        case .socialDance, .cardioDance: self = .dance
        case .yoga, .mindAndBody: self = .yoga
        case .pilates, .barre: self = .pilates
        case .coreTraining: self = .coreTraining
        case .flexibility, .preparationAndRecovery: self = .flexibility
        case .cooldown: self = .cooldown
        case .traditionalStrengthTraining, .functionalStrengthTraining: self = .strength
        case .boxing, .kickboxing: self = .boxing
        case .martialArts, .taiChi, .wrestling: self = .martialArts
        case .climbing: self = .climbing
        case .downhillSkiing, .snowSports: self = .downhillSkiing
        case .crossCountrySkiing: self = .crossCountrySkiing
        case .snowboarding: self = .snowboarding
        case .paddleSports, .sailing: self = .paddling
        case .surfingSports: self = .surfing
        case .tennis: self = .tennis
        case .tableTennis, .badminton, .squash, .racquetball, .pickleball: self = .racketSports
        case .soccer: self = .soccer
        case .basketball: self = .basketball
        case .americanFootball, .australianFootball, .rugby, .volleyball, .handball,
             .hockey, .baseball, .softball, .lacrosse, .cricket:
            self = .teamSports
        case .golf: self = .golf
        case .wheelchairRunPace, .wheelchairWalkPace: self = .wheelchair
        default: self = .other
        }
    }

    var name: String {
        switch self {
        case .running: String(localized: "Running")
        case .walking: String(localized: "Walking")
        case .hiking: String(localized: "Hiking")
        case .cycling: String(localized: "Cycling")
        case .swimming: String(localized: "Swimming")
        case .rowing: String(localized: "Rowing")
        case .elliptical: String(localized: "Elliptical")
        case .stairs: String(localized: "Stair climbing")
        case .hiit: String(localized: "HIIT")
        case .mixedCardio: String(localized: "Mixed cardio")
        case .crossTraining: String(localized: "Cross training")
        case .jumpRope: String(localized: "Jump rope")
        case .dance: String(localized: "Dance")
        case .yoga: String(localized: "Yoga")
        case .pilates: String(localized: "Pilates")
        case .coreTraining: String(localized: "Core training")
        case .flexibility: String(localized: "Flexibility")
        case .cooldown: String(localized: "Cooldown")
        case .strength: String(localized: "Strength training")
        case .boxing: String(localized: "Boxing")
        case .martialArts: String(localized: "Martial arts")
        case .climbing: String(localized: "Climbing")
        case .downhillSkiing: String(localized: "Downhill skiing")
        case .crossCountrySkiing: String(localized: "Cross-country skiing")
        case .snowboarding: String(localized: "Snowboarding")
        case .paddling: String(localized: "Paddling")
        case .surfing: String(localized: "Surfing")
        case .tennis: String(localized: "Tennis")
        case .racketSports: String(localized: "Racket sports")
        case .soccer: String(localized: "Soccer")
        case .basketball: String(localized: "Basketball")
        case .teamSports: String(localized: "Team sports")
        case .golf: String(localized: "Golf")
        case .wheelchair: String(localized: "Wheelchair")
        case .other: String(localized: "Workout")
        }
    }

    /// SF Symbol for the row and the detail sheet.
    var symbol: String {
        switch self {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .hiking: "figure.hiking"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .rowing: "figure.rower"
        case .elliptical: "figure.elliptical"
        case .stairs: "figure.stair.stepper"
        case .hiit: "figure.highintensity.intervaltraining"
        case .mixedCardio: "figure.mixed.cardio"
        case .crossTraining: "figure.cross.training"
        case .jumpRope: "figure.jumprope"
        case .dance: "figure.dance"
        case .yoga: "figure.yoga"
        case .pilates: "figure.pilates"
        case .coreTraining: "figure.core.training"
        case .flexibility: "figure.flexibility"
        case .cooldown: "figure.cooldown"
        case .strength: "figure.strengthtraining.traditional"
        case .boxing: "figure.boxing"
        case .martialArts: "figure.martial.arts"
        case .climbing: "figure.climbing"
        case .downhillSkiing: "figure.skiing.downhill"
        case .crossCountrySkiing: "figure.skiing.crosscountry"
        case .snowboarding: "figure.snowboarding"
        case .paddling: "oar.2.crossed"
        case .surfing: "figure.surfing"
        case .tennis: "figure.tennis"
        case .racketSports: "figure.racquetball"
        case .soccer: "figure.soccer"
        case .basketball: "figure.basketball"
        case .teamSports: "sportscourt.fill"
        case .golf: "figure.golf"
        case .wheelchair: "figure.roll"
        case .other: "figure.mixed.cardio"
        }
    }
}
