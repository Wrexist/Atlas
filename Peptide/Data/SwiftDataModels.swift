import Foundation
import SwiftData

// MARK: - Shared codec (reused by all model conversions)

private let sdEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    return e
}()

private let sdDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}()

// MARK: - StoredProtocol

@Model
final class StoredProtocol {
    @Attribute(.unique) var id: UUID
    var name: String
    var cycleLengthWeeks: Int
    var startDate: Date
    var statusRaw: String
    var notes: String
    var peptideData: Data     // JSON-encoded [Peptide]
    var scheduleData: Data    // JSON-encoded EncodedSchedule (or legacy ProtocolSchedule)
    var authorName: String?
    var authorHandle: String?
    var forkedFromStackIdString: String?
    var createdAt: Date?

    init(id: UUID, name: String, cycleLengthWeeks: Int, startDate: Date,
         statusRaw: String, notes: String, peptideData: Data, scheduleData: Data,
         authorName: String? = nil, authorHandle: String? = nil,
         forkedFromStackIdString: String? = nil, createdAt: Date? = nil) {
        self.id = id
        self.name = name
        self.cycleLengthWeeks = cycleLengthWeeks
        self.startDate = startDate
        self.statusRaw = statusRaw
        self.notes = notes
        self.peptideData = peptideData
        self.scheduleData = scheduleData
        self.authorName = authorName
        self.authorHandle = authorHandle
        self.forkedFromStackIdString = forkedFromStackIdString
        self.createdAt = createdAt
    }

    static func make(from proto: PeptideProtocol) throws -> StoredProtocol {
        let peptideData = try sdEncoder.encode(proto.peptides)
        let scheduleData = try sdEncoder.encode(EncodedSchedule(from: proto))
        return StoredProtocol(
            id: proto.id,
            name: proto.name,
            cycleLengthWeeks: proto.cycleLengthWeeks,
            startDate: proto.startDate,
            statusRaw: proto.status.rawValue,
            notes: proto.notes,
            peptideData: peptideData,
            scheduleData: scheduleData,
            authorName: proto.authorName,
            authorHandle: proto.authorHandle,
            forkedFromStackIdString: proto.forkedFromStackId?.uuidString,
            createdAt: proto.createdAt
        )
    }

    func update(from proto: PeptideProtocol) throws {
        name = proto.name
        cycleLengthWeeks = proto.cycleLengthWeeks
        startDate = proto.startDate
        statusRaw = proto.status.rawValue
        notes = proto.notes
        peptideData = try sdEncoder.encode(proto.peptides)
        scheduleData = try sdEncoder.encode(EncodedSchedule(from: proto))
        authorName = proto.authorName
        authorHandle = proto.authorHandle
        forkedFromStackIdString = proto.forkedFromStackId?.uuidString
        createdAt = proto.createdAt
    }

    func toPeptideProtocol() throws -> PeptideProtocol {
        let peptides = try sdDecoder.decode([Peptide].self, from: peptideData)
        let status = ProtocolStatus(rawValue: statusRaw) ?? .active

        // Try the new wrapped format first; fall back to bare ProtocolSchedule for legacy saves.
        let schedule: ProtocolSchedule
        let overrides: [UUID: ProtocolSchedule]
        if let wrapped = try? sdDecoder.decode(EncodedSchedule.self, from: scheduleData) {
            schedule = wrapped.defaultSchedule
            overrides = wrapped.decodedOverrides
        } else {
            schedule = try sdDecoder.decode(ProtocolSchedule.self, from: scheduleData)
            overrides = [:]
        }

        return PeptideProtocol(
            id: id,
            name: name,
            peptides: peptides,
            schedule: schedule,
            peptideSchedules: overrides,
            cycleLengthWeeks: cycleLengthWeeks,
            startDate: startDate,
            status: status,
            notes: notes,
            authorName: authorName,
            authorHandle: authorHandle,
            forkedFromStackId: forkedFromStackIdString.flatMap(UUID.init(uuidString:)),
            createdAt: createdAt ?? Date()
        )
    }
}

/// Wrapper that lets us store both the protocol-wide default schedule and any
/// per-peptide overrides inside the existing `scheduleData` blob — avoids a
/// SwiftData schema migration.
private struct EncodedSchedule: Codable {
    let defaultSchedule: ProtocolSchedule
    let overrides: [String: ProtocolSchedule]?

    init(from proto: PeptideProtocol) {
        self.defaultSchedule = proto.schedule
        if proto.peptideSchedules.isEmpty {
            self.overrides = nil
        } else {
            self.overrides = Dictionary(uniqueKeysWithValues:
                proto.peptideSchedules.map { ($0.key.uuidString, $0.value) }
            )
        }
    }

    var decodedOverrides: [UUID: ProtocolSchedule] {
        guard let overrides else { return [:] }
        return Dictionary(uniqueKeysWithValues: overrides.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
    }
}

// MARK: - StoredEntry

@Model
final class StoredEntry {
    @Attribute(.unique) var id: UUID
    var protocolId: UUID
    var date: Date
    var dose: String
    var notes: String
    var completed: Bool
    var actualDose: String?
    var actualTime: Date?
    var injectionSite: String?
    var peptideData: Data     // JSON-encoded Peptide

    init(id: UUID, protocolId: UUID, date: Date, dose: String, notes: String,
         completed: Bool, actualDose: String?, actualTime: Date?,
         injectionSite: String?, peptideData: Data) {
        self.id = id
        self.protocolId = protocolId
        self.date = date
        self.dose = dose
        self.notes = notes
        self.completed = completed
        self.actualDose = actualDose
        self.actualTime = actualTime
        self.injectionSite = injectionSite
        self.peptideData = peptideData
    }

    static func make(from entry: ProtocolEntry) throws -> StoredEntry {
        let peptideData = try sdEncoder.encode(entry.peptide)
        return StoredEntry(
            id: entry.id,
            protocolId: entry.protocolId,
            date: entry.date,
            dose: entry.dose,
            notes: entry.notes,
            completed: entry.completed,
            actualDose: entry.actualDose,
            actualTime: entry.actualTime,
            injectionSite: entry.injectionSite,
            peptideData: peptideData
        )
    }

    func update(from entry: ProtocolEntry) throws {
        completed = entry.completed
        actualDose = entry.actualDose
        actualTime = entry.actualTime
        injectionSite = entry.injectionSite
        notes = entry.notes
        dose = entry.dose
        peptideData = try sdEncoder.encode(entry.peptide)
    }

    func toProtocolEntry() throws -> ProtocolEntry {
        let peptide = try sdDecoder.decode(Peptide.self, from: peptideData)
        return ProtocolEntry(
            id: id,
            protocolId: protocolId,
            peptide: peptide,
            date: date,
            dose: dose,
            notes: notes,
            completed: completed,
            actualDose: actualDose,
            actualTime: actualTime,
            injectionSite: injectionSite
        )
    }
}

// MARK: - StoredProfile

@Model
final class StoredProfile {
    var name: String
    var memberSince: Date
    var healthConnected: Bool
    var hapticFeedbackEnabled: Bool
    var doseRemindersEnabled: Bool
    var biometricLockEnabled: Bool
    var goalsData: Data       // JSON-encoded [String]
    /// JSON-encoded BodyMetrics. Optional for legacy stores written before
    /// metrics existed; `toUserProfile` falls back to `.unspecified`.
    var bodyMetricsData: Data?
    /// JPEG-encoded avatar. Optional for legacy stores; nil means no avatar.
    var avatarImageData: Data?
    var bio: String?
    var primaryGoal: String?
    /// JSON-encoded `ProfileExtension` carrying the long-tail Lifestyle/
    /// onboarding fields that don't warrant their own columns (nutrition
    /// targets, weight + workout history, daily consumption buckets, etc.).
    /// Optional so existing rows decode cleanly — `toUserProfile` falls
    /// back to empty collections on a missing/legacy blob.
    var extensionData: Data?

    init(name: String, memberSince: Date, healthConnected: Bool,
         hapticFeedbackEnabled: Bool, doseRemindersEnabled: Bool,
         biometricLockEnabled: Bool, goalsData: Data,
         bodyMetricsData: Data? = nil,
         avatarImageData: Data? = nil,
         bio: String? = nil,
         primaryGoal: String? = nil,
         extensionData: Data? = nil) {
        self.name = name
        self.memberSince = memberSince
        self.healthConnected = healthConnected
        self.hapticFeedbackEnabled = hapticFeedbackEnabled
        self.doseRemindersEnabled = doseRemindersEnabled
        self.biometricLockEnabled = biometricLockEnabled
        self.goalsData = goalsData
        self.bodyMetricsData = bodyMetricsData
        self.avatarImageData = avatarImageData
        self.bio = bio
        self.primaryGoal = primaryGoal
        self.extensionData = extensionData
    }

    static func make(from profile: UserProfile) throws -> StoredProfile {
        let goalsData = try sdEncoder.encode(profile.goals)
        let metricsData = try sdEncoder.encode(profile.bodyMetrics)
        let extData = try sdEncoder.encode(ProfileExtension.snapshot(of: profile))
        return StoredProfile(
            name: profile.name,
            memberSince: profile.memberSince,
            healthConnected: profile.healthConnected,
            hapticFeedbackEnabled: profile.hapticFeedbackEnabled,
            doseRemindersEnabled: profile.doseRemindersEnabled,
            biometricLockEnabled: profile.biometricLockEnabled,
            goalsData: goalsData,
            bodyMetricsData: metricsData,
            avatarImageData: profile.avatarImageData,
            bio: profile.bio.isEmpty ? nil : profile.bio,
            primaryGoal: profile.primaryGoal,
            extensionData: extData
        )
    }

    func update(from profile: UserProfile) throws {
        name = profile.name
        memberSince = profile.memberSince
        healthConnected = profile.healthConnected
        hapticFeedbackEnabled = profile.hapticFeedbackEnabled
        doseRemindersEnabled = profile.doseRemindersEnabled
        biometricLockEnabled = profile.biometricLockEnabled
        goalsData = try sdEncoder.encode(profile.goals)
        bodyMetricsData = try sdEncoder.encode(profile.bodyMetrics)
        avatarImageData = profile.avatarImageData
        bio = profile.bio.isEmpty ? nil : profile.bio
        primaryGoal = profile.primaryGoal
        extensionData = try sdEncoder.encode(ProfileExtension.snapshot(of: profile))
    }

    func toUserProfile() throws -> UserProfile {
        let goals = try sdDecoder.decode([String].self, from: goalsData)
        let metrics: BodyMetrics
        if let data = bodyMetricsData,
           let decoded = try? sdDecoder.decode(BodyMetrics.self, from: data) {
            metrics = decoded
        } else {
            metrics = .unspecified
        }
        let ext: ProfileExtension
        if let data = extensionData,
           let decoded = try? sdDecoder.decode(ProfileExtension.self, from: data) {
            ext = decoded
        } else {
            ext = .empty
        }
        return UserProfile(
            name: name,
            goals: goals,
            memberSince: memberSince,
            healthConnected: healthConnected,
            hapticFeedbackEnabled: hapticFeedbackEnabled,
            doseRemindersEnabled: doseRemindersEnabled,
            biometricLockEnabled: biometricLockEnabled,
            bodyMetrics: metrics,
            nutritionTargets: ext.nutritionTargets,
            creatorAttribution: ext.creatorAttribution,
            emailSubscription: ext.emailSubscription,
            weightHistory: ext.weightHistory,
            progressPhotoFilenames: ext.progressPhotoFilenames,
            dailyConsumption: ext.dailyConsumption,
            workoutHistory: ext.workoutHistory,
            avatarImageData: avatarImageData,
            bio: bio ?? "",
            primaryGoal: primaryGoal,
            customFoods: ext.customFoods,
            favoriteFoodIDs: Set(ext.favoriteFoodIDs),
            mealHistory: ext.mealHistory,
            healthKitNutritionEnabled: ext.healthKitNutritionEnabled,
            outcomeHistory: ext.outcomeHistory
        )
    }
}

/// Sidecar blob persisted on `StoredProfile.extensionData`. Holds the
/// long-tail Lifestyle / onboarding fields so we can add new ones without
/// migrating the SwiftData schema each time.
///
/// All fields default to nil / empty so a freshly-introduced blob that
/// omits a future field still decodes against an older build (Swift's
/// synthesized `init(from:)` skips missing keys when the property has a
/// default value).
private struct ProfileExtension: Codable {
    var nutritionTargets: NutritionTargets? = nil
    var creatorAttribution: CreatorAttribution? = nil
    var emailSubscription: EmailSubscription? = nil
    var weightHistory: [WeightEntry] = []
    var progressPhotoFilenames: [String] = []
    var dailyConsumption: [String: DailyConsumption] = [:]
    var workoutHistory: [WorkoutEntry] = []
    var customFoods: [CustomFood] = []
    /// Encoded as `[String]` so the round-trip JSON has a deterministic
    /// shape (Set has no ordering guarantee). The accessor on
    /// `toUserProfile()` collapses back to `Set<String>`.
    var favoriteFoodIDs: [String] = []
    var mealHistory: [MealEntry] = []
    var healthKitNutritionEnabled: Bool = false
    var outcomeHistory: [OutcomeEntry] = []

    static let empty = ProfileExtension()

    static func snapshot(of profile: UserProfile) -> ProfileExtension {
        ProfileExtension(
            nutritionTargets: profile.nutritionTargets,
            creatorAttribution: profile.creatorAttribution,
            emailSubscription: profile.emailSubscription,
            weightHistory: profile.weightHistory,
            progressPhotoFilenames: profile.progressPhotoFilenames,
            dailyConsumption: profile.dailyConsumption,
            workoutHistory: profile.workoutHistory,
            customFoods: profile.customFoods,
            favoriteFoodIDs: Array(profile.favoriteFoodIDs).sorted(),
            mealHistory: profile.mealHistory,
            healthKitNutritionEnabled: profile.healthKitNutritionEnabled,
            outcomeHistory: profile.outcomeHistory
        )
    }
}
