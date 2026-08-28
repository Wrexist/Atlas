import Foundation
import SwiftData

// MARK: - Shared codec (reused by all model conversions)

private let sdEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    // Deterministic output: `StoredProfile.update(from:)` compares the
    // fresh encoding against the stored bytes to decide whether a
    // column actually changed (an untouched column is what lets
    // CloudKit merge concurrent edits). Without sorted keys, dictionary
    // fields re-encode in random order and every save looks like a
    // change.
    e.outputFormatting = [.sortedKeys]
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
    // CloudKit-backed stores impose two schema constraints, both
    // required for `SwiftDataRepository.makeCloudContainer()` to
    // succeed: (1) no `@Attribute(.unique)` — uniqueness is enforced
    // by the fetch-then-update-or-insert pattern in
    // `SwiftDataRepository.saveProtocols`; (2) every non-relationship
    // attribute must be optional or carry a default value. Without
    // the defaults the container init throws and the fallback chain
    // silently drops every user to a local-only store.
    var id: UUID = UUID()
    var name: String = ""
    var cycleLengthWeeks: Int = 8
    var startDate: Date = Date()
    var statusRaw: String = "active"
    var notes: String = ""
    var peptideData: Data = Data()     // JSON-encoded [Peptide]
    var scheduleData: Data = Data()    // JSON-encoded EncodedSchedule (or legacy ProtocolSchedule)
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
        let washoutWeeks: Int
        if let wrapped = try? sdDecoder.decode(EncodedSchedule.self, from: scheduleData) {
            schedule = wrapped.defaultSchedule
            overrides = wrapped.decodedOverrides
            washoutWeeks = wrapped.decodedWashoutWeeks
        } else {
            schedule = try sdDecoder.decode(ProtocolSchedule.self, from: scheduleData)
            overrides = [:]
            washoutWeeks = 0
        }

        return PeptideProtocol(
            id: id,
            name: name,
            peptides: peptides,
            schedule: schedule,
            peptideSchedules: overrides,
            cycleLengthWeeks: cycleLengthWeeks,
            washoutWeeks: washoutWeeks,
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
    /// Wash-out duration in weeks. Optional + decode-if-present so
    /// legacy rows (written before cycle/wash-out shipped) still
    /// decode cleanly — they default to `0`, which preserves the
    /// single-cycle behaviour exactly. Encoded only when non-zero
    /// so the blob stays compact for the typical non-cycling case.
    let washoutWeeks: Int?

    init(from proto: PeptideProtocol) {
        self.defaultSchedule = proto.schedule
        if proto.peptideSchedules.isEmpty {
            self.overrides = nil
        } else {
            self.overrides = Dictionary(uniqueKeysWithValues:
                proto.peptideSchedules.map { ($0.key.uuidString, $0.value) }
            )
        }
        self.washoutWeeks = proto.washoutWeeks > 0 ? proto.washoutWeeks : nil
    }

    var decodedOverrides: [UUID: ProtocolSchedule] {
        guard let overrides else { return [:] }
        return Dictionary(uniqueKeysWithValues: overrides.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
    }

    var decodedWashoutWeeks: Int { washoutWeeks ?? 0 }
}

// MARK: - StoredEntry

@Model
final class StoredEntry {
    // See StoredProtocol — CloudKit needs no `.unique` and every
    // attribute optional-or-defaulted. Uniqueness is enforced by the
    // fetch-then-update-or-insert pattern in
    // `SwiftDataRepository.saveEntries`.
    var id: UUID = UUID()
    var protocolId: UUID = UUID()
    var date: Date = Date()
    var dose: String = ""
    var notes: String = ""
    var completed: Bool = false
    var actualDose: String?
    var actualTime: Date?
    var injectionSite: String?
    var peptideData: Data = Data()     // JSON-encoded Peptide

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
    // CloudKit requires every attribute optional-or-defaulted — see
    // StoredProtocol. Defaults below are placeholders only; every row
    // is created via `make(from:)`/`update(from:)` which set real values.
    var name: String = ""
    var memberSince: Date = Date()
    var healthConnected: Bool = false
    var hapticFeedbackEnabled: Bool = true
    var doseRemindersEnabled: Bool = true
    var biometricLockEnabled: Bool = false
    var goalsData: Data = Data()       // JSON-encoded [String]
    /// JSON-encoded BodyMetrics. Optional for legacy stores written before
    /// metrics existed; `toUserProfile` falls back to `.unspecified`.
    var bodyMetricsData: Data?
    /// JPEG-encoded avatar. Optional for legacy stores; nil means no avatar.
    var avatarImageData: Data?
    var bio: String?
    var primaryGoal: String?
    /// JSON-encoded `ProfileExtension` carrying the long-tail Meals /
    /// Biology / onboarding fields that don't warrant their own columns
    /// (nutrition targets, biology config, training prefs, etc.).
    /// Optional so existing rows decode cleanly — `toUserProfile` falls
    /// back to empty collections on a missing/legacy blob.
    ///
    /// High-churn feature areas are deliberately NOT in this blob any
    /// more — see the split columns below. CloudKit resolves conflicts
    /// per record field, so two devices editing independent features
    /// inside one opaque blob meant one device's blob silently
    /// overwrote the other's. Splitting the frequently-and-
    /// independently-edited areas into their own columns confines a
    /// last-writer-wins conflict to the one feature actually edited on
    /// both devices.
    var extensionData: Data?

    // Split high-churn feature areas (audit Data Integrity 04, Phase 3).
    // All optional so existing rows decode without migration; reads fall
    // back to the same key inside the legacy `extensionData` blob, so no
    // up-front data migration runs and no legacy value is discarded.
    /// JSON `MealsSlice` — meal log + per-day consumption buckets.
    var mealsData: Data?
    /// JSON `HabitsSlice` — habit definitions + check-ins.
    var habitsData: Data?
    /// JSON `MomentumSlice` — Atlas Score state + history.
    var momentumData: Data?
    /// JSON `[WeightEntry]` — weigh-in history.
    var weightHistoryData: Data?
    /// JSON `[LabValue]` — lab/biomarker entries.
    var labsData: Data?
    /// JSON `[OutcomeEntry]` — daily outcome check-ins.
    var outcomesData: Data?
    /// JSON `FoodLibrarySlice` — custom foods + favorite food IDs.
    var foodLibraryData: Data?
    /// JSON `[String: WeeklySummary]` — weekly recap cache.
    var summariesData: Data?

    /// Deterministic singleton marker (audit Phase 8) — the same value
    /// on every device, so the profile row is identified by declared
    /// role rather than "whatever fetch returned first". Not a unique
    /// constraint (CloudKit forbids those); duplicate rows created by
    /// two devices racing first-launch are reconciled in
    /// `SwiftDataRepository.canonicalProfileRow`.
    var singletonKey: String = StoredProfile.canonicalSingletonKey
    /// Stamped on every content-changing local save. Duplicate-row
    /// reconciliation keeps the newest row as the winner.
    var updatedAt: Date = Date()

    static let canonicalSingletonKey = "atlas.profile.primary"

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
        self.singletonKey = Self.canonicalSingletonKey
        self.updatedAt = Date()
    }

    static func make(from profile: UserProfile) throws -> StoredProfile {
        let goalsData = try sdEncoder.encode(profile.goals)
        let metricsData = try sdEncoder.encode(profile.bodyMetrics)
        let extData = try sdEncoder.encode(ProfileExtension.residual(of: profile))
        let stored = StoredProfile(
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
        try stored.writeSlices(from: profile)
        return stored
    }

    func update(from profile: UserProfile) throws {
        // Assign only what actually changed. Every property assignment
        // marks its CloudKit record field dirty and ships it on the next
        // sync — and an untouched field is exactly what lets CloudKit
        // merge two devices' concurrent edits instead of clobbering.
        var contentChanged = false
        func assign<T: Equatable>(
            _ keyPath: ReferenceWritableKeyPath<StoredProfile, T>, _ value: T
        ) {
            guard self[keyPath: keyPath] != value else { return }
            self[keyPath: keyPath] = value
            contentChanged = true
        }
        assign(\.name, profile.name)
        assign(\.memberSince, profile.memberSince)
        assign(\.healthConnected, profile.healthConnected)
        assign(\.hapticFeedbackEnabled, profile.hapticFeedbackEnabled)
        assign(\.doseRemindersEnabled, profile.doseRemindersEnabled)
        assign(\.biometricLockEnabled, profile.biometricLockEnabled)
        assign(\.goalsData, try sdEncoder.encode(profile.goals))
        assign(\.bodyMetricsData, try sdEncoder.encode(profile.bodyMetrics))
        assign(\.avatarImageData, profile.avatarImageData)
        assign(\.bio, profile.bio.isEmpty ? nil : profile.bio)
        assign(\.primaryGoal, profile.primaryGoal)
        assign(\.extensionData, try sdEncoder.encode(ProfileExtension.residual(of: profile)))
        try writeSlices(from: profile, assign: { keyPath, value in
            assign(keyPath, value)
        })
        assign(\.singletonKey, Self.canonicalSingletonKey)
        if contentChanged { updatedAt = Date() }
    }

    /// Encodes each split feature area into its own column.
    private func writeSlices(
        from profile: UserProfile,
        assign: ((ReferenceWritableKeyPath<StoredProfile, Data?>, Data?) -> Void)? = nil
    ) throws {
        let set: (ReferenceWritableKeyPath<StoredProfile, Data?>, Data?) -> Void =
            assign ?? { self[keyPath: $0] = $1 }
        set(\.mealsData, try sdEncoder.encode(MealsSlice(
            mealHistory: profile.mealHistory,
            dailyConsumption: profile.dailyConsumption
        )))
        set(\.habitsData, try sdEncoder.encode(HabitsSlice(
            habits: profile.habits,
            habitEntries: profile.habitEntries
        )))
        set(\.momentumData, try sdEncoder.encode(MomentumSlice(
            atlasScore: profile.atlasScore,
            atlasLevel: profile.atlasLevel,
            momentumAwardedToday: profile.momentumAwardedToday,
            lastMomentumAwardDay: profile.lastMomentumAwardDay,
            momentumHistory: profile.momentumHistory
        )))
        set(\.weightHistoryData, try sdEncoder.encode(profile.weightHistory))
        set(\.labsData, try sdEncoder.encode(profile.labHistory))
        set(\.outcomesData, try sdEncoder.encode(profile.outcomeHistory))
        set(\.foodLibraryData, try sdEncoder.encode(FoodLibrarySlice(
            customFoods: profile.customFoods,
            favoriteFoodIDs: Array(profile.favoriteFoodIDs).sorted()
        )))
        set(\.summariesData, try sdEncoder.encode(profile.weeklySummaries))
    }

    /// Decodes an optional slice column, falling back to the legacy
    /// blob's value when the column is nil (a row written before the
    /// split) and logging — never silently wiping — on corruption.
    private func slice<T: Decodable>(_ data: Data?, legacy: @autoclosure () -> T) -> T {
        guard let data else { return legacy() }
        do {
            return try sdDecoder.decode(T.self, from: data)
        } catch {
            AppLog.swiftData.error(
                "Profile slice decode failed (\(String(describing: T.self), privacy: .public)); falling back to legacy blob: \(error.localizedDescription, privacy: .public)"
            )
            return legacy()
        }
    }

    func toUserProfile() throws -> UserProfile {
        let goals = try sdDecoder.decode([String].self, from: goalsData)
        let metrics: BodyMetrics
        if let data = bodyMetricsData {
            do {
                metrics = try sdDecoder.decode(BodyMetrics.self, from: data)
            } catch DecodingError.keyNotFound {
                // Legacy payload missing a field added since — expected
                // during migration, so fall back silently.
                metrics = .unspecified
            } catch {
                // Genuine corruption: log so it's diagnosable instead of a
                // silent reset (mirrors the ProfileExtension path below),
                // then fall back so the rest of the profile still loads.
                AppLog.swiftData.error(
                    "BodyMetrics decode failed; falling back to unspecified: \(error.localizedDescription, privacy: .public)"
                )
                metrics = .unspecified
            }
        } else {
            metrics = .unspecified
        }
        let ext: ProfileExtension
        if let data = extensionData {
            do {
                ext = try sdDecoder.decode(ProfileExtension.self, from: data)
            } catch {
                // ProfileExtension is the catch-all blob for everything
                // not in the @Model columns (biology config, meal
                // history, lab values, training prefs, …). A silent
                // fallback to `.empty` was disproportionately
                // destructive: any future schema addition that the
                // decoder couldn't tolerate would wipe the user's
                // visible Meals/Biology/Labs data for the session.
                // Log so the issue is diagnosable; the empty fallback
                // still preserves the rest of the profile load.
                AppLog.swiftData.error(
                    "ProfileExtension decode failed; falling back to empty: \(error.localizedDescription, privacy: .public)"
                )
                ext = .empty
            }
        } else {
            ext = .empty
        }
        // Split columns take precedence; a nil column means the row was
        // written before the split, so the legacy blob's value carries
        // through untouched.
        let meals = slice(mealsData, legacy: MealsSlice(
            mealHistory: ext.mealHistory, dailyConsumption: ext.dailyConsumption
        ))
        let habitsSlice = slice(habitsData, legacy: HabitsSlice(
            habits: ext.habits, habitEntries: ext.habitEntries
        ))
        let momentum = slice(momentumData, legacy: MomentumSlice(
            atlasScore: ext.atlasScore,
            atlasLevel: ext.atlasLevel,
            momentumAwardedToday: ext.momentumAwardedToday,
            lastMomentumAwardDay: ext.lastMomentumAwardDay,
            momentumHistory: ext.momentumHistory
        ))
        let foodLibrary = slice(foodLibraryData, legacy: FoodLibrarySlice(
            customFoods: ext.customFoods, favoriteFoodIDs: ext.favoriteFoodIDs
        ))
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
            affiliateApplication: ext.affiliateApplication,
            emailSubscription: ext.emailSubscription,
            weightHistory: slice(weightHistoryData, legacy: ext.weightHistory),
            progressPhotoFilenames: ext.progressPhotoFilenames,
            dailyConsumption: meals.dailyConsumption,
            workoutHistory: ext.workoutHistory,
            avatarImageData: avatarImageData,
            bio: bio ?? "",
            primaryGoal: primaryGoal,
            customFoods: foodLibrary.customFoods,
            favoriteFoodIDs: Set(foodLibrary.favoriteFoodIDs),
            mealHistory: meals.mealHistory,
            healthKitNutritionEnabled: ext.healthKitNutritionEnabled,
            outcomeHistory: slice(outcomesData, legacy: ext.outcomeHistory),
            labHistory: slice(labsData, legacy: ext.labHistory),
            lastKnownTimezoneIdentifier: ext.lastKnownTimezoneIdentifier,
            streakFreezeDays: Set(ext.streakFreezeDays),
            recipes: ext.recipes,
            protocolNotes: ext.protocolNotes,
            weeklySummaryEnabled: ext.weeklySummaryEnabled ?? true,
            weeklySummaries: slice(summariesData, legacy: ext.weeklySummaries ?? [:]),
            biologyConfig: ext.biologyConfig,
            trainingPreferences: ext.trainingPreferences,
            goalDate: ext.goalDate,
            habits: habitsSlice.habits,
            habitEntries: habitsSlice.habitEntries,
            atlasScore: momentum.atlasScore,
            atlasLevel: momentum.atlasLevel,
            momentumAwardedToday: momentum.momentumAwardedToday,
            lastMomentumAwardDay: momentum.lastMomentumAwardDay,
            momentumHistory: momentum.momentumHistory
        )
    }
}

// MARK: - Profile slices

/// Per-feature-area containers for the split `StoredProfile` columns.
/// Each groups only fields that are always edited together, so a
/// CloudKit field-level merge preserves unrelated features edited on
/// another device.
struct MealsSlice: Codable {
    var mealHistory: [MealEntry] = []
    var dailyConsumption: [String: DailyConsumption] = [:]
}

struct HabitsSlice: Codable {
    var habits: [Habit] = []
    var habitEntries: [HabitEntry] = []
}

struct MomentumSlice: Codable {
    var atlasScore: Int = 0
    var atlasLevel: Int = 1
    var momentumAwardedToday: Int = 0
    var lastMomentumAwardDay: Date? = nil
    var momentumHistory: [MomentumDayPoint] = []
}

struct FoodLibrarySlice: Codable {
    var customFoods: [CustomFood] = []
    /// `[String]` (sorted) for a deterministic on-disk shape; collapsed
    /// back to `Set<String>` on read.
    var favoriteFoodIDs: [String] = []
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
    var affiliateApplication: AffiliateApplication? = nil
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
    var labHistory: [LabValue] = []
    var lastKnownTimezoneIdentifier: String?
    /// Encoded as `[String]` so the on-disk JSON has a
    /// deterministic shape; `toUserProfile` collapses back to Set.
    var streakFreezeDays: [String] = []
    var recipes: [Recipe] = []
    var protocolNotes: [ProtocolNote] = []
    /// Biology tab preferences — defaults to `.default` so a
    /// profile encoded by an older build (no biologyConfig field)
    /// decodes against this struct's synthesized init(from:)
    /// without losing other fields.
    var biologyConfig: BiologyConfig = .default
    /// Training prefs from the redesigned onboarding. Optional so
    /// pre-pivot blobs decode cleanly and `toUserProfile` leaves the
    /// profile field nil for older accounts.
    var trainingPreferences: TrainingPreferences? = nil
    /// Pre-existing UserProfile fields that were missing from the
    /// sidecar — every prior save/load dropped these silently. Both
    /// optional so older blobs decode (default-true for the toggle,
    /// empty dict for the cache) without a migration.
    var weeklySummaryEnabled: Bool? = nil
    var weeklySummaries: [String: WeeklySummary]? = nil
    /// User-committed goal completion date from the onboarding "By
    /// when?" step. Optional so older sidecar blobs decode cleanly.
    var goalDate: Date? = nil
    /// User-defined habits surfaced on Home. Optional in encoded form
    /// (defaults to empty) so legacy sidecar blobs decode cleanly.
    var habits: [Habit] = []
    var habitEntries: [HabitEntry] = []
    /// Atlas Score / momentum state. Zero-defaulted (level 1) so older
    /// sidecar blobs decode cleanly — an existing user simply starts the
    /// score at 0 and earns from their next logged action.
    var atlasScore: Int = 0
    var atlasLevel: Int = 1
    var momentumAwardedToday: Int = 0
    var lastMomentumAwardDay: Date? = nil
    var momentumHistory: [MomentumDayPoint] = []

    static let empty = ProfileExtension()

    /// Snapshot of everything that still lives in the blob. The split
    /// areas (meals, habits, momentum, weight, labs, outcomes, food
    /// library, weekly summaries) are deliberately left at their
    /// defaults — their canonical home is the dedicated `StoredProfile`
    /// columns, and duplicating them here would resurrect the whole-
    /// blob conflict this split exists to remove. Reads still honour a
    /// legacy blob that carries them (rows written before the split).
    static func residual(of profile: UserProfile) -> ProfileExtension {
        ProfileExtension(
            nutritionTargets: profile.nutritionTargets,
            creatorAttribution: profile.creatorAttribution,
            affiliateApplication: profile.affiliateApplication,
            emailSubscription: profile.emailSubscription,
            progressPhotoFilenames: profile.progressPhotoFilenames,
            workoutHistory: profile.workoutHistory,
            healthKitNutritionEnabled: profile.healthKitNutritionEnabled,
            lastKnownTimezoneIdentifier: profile.lastKnownTimezoneIdentifier,
            streakFreezeDays: Array(profile.streakFreezeDays).sorted(),
            recipes: profile.recipes,
            protocolNotes: profile.protocolNotes,
            biologyConfig: profile.biologyConfig,
            trainingPreferences: profile.trainingPreferences,
            weeklySummaryEnabled: profile.weeklySummaryEnabled,
            goalDate: profile.goalDate
        )
    }
}
