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

/// Assigns only a value that differs. Every assignment marks the CloudKit
/// field dirty and re-exports it on the next sync, so rewriting unchanged
/// rows on each save would re-upload the whole table.
private func assignIfChanged<Root: AnyObject, Value: Equatable>(
    _ root: Root, _ keyPath: ReferenceWritableKeyPath<Root, Value>, _ value: Value
) {
    if root[keyPath: keyPath] != value { root[keyPath: keyPath] = value }
}

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
        assignIfChanged(self, \.name, proto.name)
        assignIfChanged(self, \.cycleLengthWeeks, proto.cycleLengthWeeks)
        assignIfChanged(self, \.startDate, proto.startDate)
        assignIfChanged(self, \.statusRaw, proto.status.rawValue)
        assignIfChanged(self, \.notes, proto.notes)
        try assignIfChanged(self, \.peptideData, sdEncoder.encode(proto.peptides))
        try assignIfChanged(self, \.scheduleData, sdEncoder.encode(EncodedSchedule(from: proto)))
        assignIfChanged(self, \.authorName, proto.authorName)
        assignIfChanged(self, \.authorHandle, proto.authorHandle)
        assignIfChanged(self, \.forkedFromStackIdString, proto.forkedFromStackId?.uuidString)
        assignIfChanged(self, \.createdAt, Optional(proto.createdAt))
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
            // Legacy rows predate `createdAt`; `startDate` is the same on
            // every device, so the backfill written by `update` agrees.
            createdAt: createdAt ?? startDate
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

/// Reads only a stored peptide's id, to tell whether a row's blob
/// still matches the entry being saved.
private struct PeptideIDProbe: Decodable {
    let id: UUID
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
    /// JSON-encoded `Peptide`: an `EntryPeptideSnapshot` for rows
    /// written since A379, the full record for older ones. Same column
    /// and format either way, so no schema change and older builds
    /// syncing through CloudKit still decode it.
    var peptideData: Data = Data()

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
        let peptideData = try sdEncoder.encode(EntryPeptideSnapshot.snapshot(of: entry.peptide))
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
        assignIfChanged(self, \.completed, entry.completed)
        assignIfChanged(self, \.actualDose, entry.actualDose)
        assignIfChanged(self, \.actualTime, entry.actualTime)
        assignIfChanged(self, \.injectionSite, entry.injectionSite)
        assignIfChanged(self, \.notes, entry.notes)
        assignIfChanged(self, \.dose, entry.dose)
        // A dose's peptide is part of its identity and never changes in
        // practice, so an existing blob — legacy full record or
        // snapshot — is left alone rather than re-exported to CloudKit.
        if storedPeptideID != entry.peptide.id {
            peptideData = try sdEncoder.encode(EntryPeptideSnapshot.snapshot(of: entry.peptide))
        }
    }

    private var storedPeptideID: UUID? {
        try? sdDecoder.decode(PeptideIDProbe.self, from: peptideData).id
    }

    /// `known` maps peptide ids to full records; a row whose id isn't in
    /// it keeps the copy it stored.
    func toProtocolEntry(resolvingFrom known: [UUID: Peptide] = [:]) throws -> ProtocolEntry {
        let stored = try sdDecoder.decode(Peptide.self, from: peptideData)
        return ProtocolEntry(
            id: id,
            protocolId: protocolId,
            peptide: EntryPeptideSnapshot.resolve(stored, in: known),
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
    /// Legacy JSON `[String: WeeklySummary]` — weekly recap cache.
    /// Retired: recaps carry health data (HRV), which Guideline
    /// 5.1.3(ii) keeps out of iCloud, so the cache now lives in
    /// `WeeklySummaryLocalStore` and this column is only ever written as
    /// nil. Kept (CloudKit can't drop a field) and still read, so
    /// `SwiftDataRepository.loadProfile` can move old values on-device.
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

    /// Writes `profile` into this row. `baseline` is the profile as this
    /// device last read or wrote it: a field whose new value still
    /// matches it wasn't edited here, so its column keeps whatever another
    /// device synced into it meanwhile instead of being reverted by
    /// stale in-memory state. Comparing values rather than encoded bytes
    /// also skips encoding the slices a save didn't touch. Without a
    /// baseline every column is written.
    func update(from profile: UserProfile, since baseline: UserProfile? = nil) throws {
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
        func edited<V: Equatable>(_ field: (UserProfile) -> V) -> Bool {
            guard let baseline else { return true }
            return field(baseline) != field(profile)
        }
        if edited(\.name) { assign(\.name, profile.name) }
        if edited(\.memberSince) { assign(\.memberSince, profile.memberSince) }
        if edited(\.healthConnected) { assign(\.healthConnected, profile.healthConnected) }
        if edited(\.hapticFeedbackEnabled) { assign(\.hapticFeedbackEnabled, profile.hapticFeedbackEnabled) }
        if edited(\.doseRemindersEnabled) { assign(\.doseRemindersEnabled, profile.doseRemindersEnabled) }
        if edited(\.biometricLockEnabled) { assign(\.biometricLockEnabled, profile.biometricLockEnabled) }
        if edited(\.goals) { assign(\.goalsData, try sdEncoder.encode(profile.goals)) }
        if edited(\.bodyMetrics) { assign(\.bodyMetricsData, try sdEncoder.encode(profile.bodyMetrics)) }
        if edited(\.avatarImageData) { assign(\.avatarImageData, profile.avatarImageData) }
        if edited(\.bio) { assign(\.bio, profile.bio.isEmpty ? nil : profile.bio) }
        if edited(\.primaryGoal) { assign(\.primaryGoal, profile.primaryGoal) }
        let residual = try sdEncoder.encode(ProfileExtension.residual(of: profile))
        let residualEdited = try baseline.map {
            try sdEncoder.encode(ProfileExtension.residual(of: $0)) != residual
        } ?? true
        if residualEdited, !holdsUnreadable(ProfileExtension.self, at: \.extensionData, replacingWith: residual) {
            assign(\.extensionData, residual)
        }
        try writeSlices(from: profile, since: baseline, assign: { keyPath, value in
            assign(keyPath, value)
        })
        assign(\.singletonKey, Self.canonicalSingletonKey)
        if contentChanged { updatedAt = Date() }
    }

    /// Encodes each split feature area into its own column. A slice equal
    /// to `baseline`'s wasn't edited here and is neither encoded nor
    /// written. On the update path a column this build can't read is left
    /// untouched.
    private func writeSlices(
        from profile: UserProfile,
        since baseline: UserProfile? = nil,
        assign: ((ReferenceWritableKeyPath<StoredProfile, Data?>, Data?) -> Void)? = nil
    ) throws {
        let set: (ReferenceWritableKeyPath<StoredProfile, Data?>, Data?) -> Void =
            assign ?? { self[keyPath: $0] = $1 }
        func write<T: Codable & Equatable>(
            _ keyPath: ReferenceWritableKeyPath<StoredProfile, Data?>,
            _ slice: (UserProfile) -> T
        ) throws {
            let value = slice(profile)
            if let baseline, slice(baseline) == value { return }
            let data = try sdEncoder.encode(value)
            if assign != nil, holdsUnreadable(T.self, at: keyPath, replacingWith: data) { return }
            set(keyPath, data)
        }
        try write(\.mealsData) {
            MealsSlice(mealHistory: $0.mealHistory, dailyConsumption: $0.dailyConsumption)
        }
        try write(\.habitsData) {
            HabitsSlice(habits: $0.habits, habitEntries: $0.habitEntries)
        }
        try write(\.momentumData) {
            MomentumSlice(
                atlasScore: $0.atlasScore,
                atlasLevel: $0.atlasLevel,
                momentumAwardedToday: $0.momentumAwardedToday,
                lastMomentumAwardDay: $0.lastMomentumAwardDay,
                momentumHistory: $0.momentumHistory
            )
        }
        try write(\.weightHistoryData) { $0.weightHistory }
        try write(\.labsData) { $0.labHistory }
        try write(\.outcomesData) { $0.outcomeHistory }
        try write(\.foodLibraryData) {
            FoodLibrarySlice(customFoods: $0.customFoods, favoriteFoodIDs: Array($0.favoriteFoodIDs).sorted())
        }
        // Never synced — see `summariesData`.
        set(\.summariesData, nil)
    }

    /// Takes each slice column of `other` that this build can't decode,
    /// where this row holds nothing readable there. Reads treat such a
    /// column as empty, so deleting `other` would destroy it on every
    /// device. False when a column can't move because this row holds
    /// data there too; the caller then keeps `other`.
    func adoptUnreadableColumns(of other: StoredProfile) -> Bool {
        visitUnreadableColumns(of: other, adopting: true)
    }

    /// Whether `adoptUnreadableColumns(of:)` would succeed, without
    /// moving anything.
    func canAdoptUnreadableColumns(of other: StoredProfile) -> Bool {
        visitUnreadableColumns(of: other, adopting: false)
    }

    private func visitUnreadableColumns(of other: StoredProfile, adopting: Bool) -> Bool {
        var adoptedAll = true
        func adopt<T: Decodable & Equatable>(_ keyPath: ReferenceWritableKeyPath<StoredProfile, Data?>, empty: T) {
            guard let theirs = other[keyPath: keyPath],
                  (try? sdDecoder.decode(T.self, from: theirs)) == nil
            else { return }
            let mine = self[keyPath: keyPath]
            if mine == nil || mine.flatMap({ try? sdDecoder.decode(T.self, from: $0) }) == empty {
                if adopting { self[keyPath: keyPath] = theirs }
            } else {
                adoptedAll = false
            }
        }
        adopt(\.mealsData, empty: MealsSlice())
        adopt(\.habitsData, empty: HabitsSlice())
        adopt(\.momentumData, empty: MomentumSlice())
        adopt(\.weightHistoryData, empty: [WeightEntry]())
        adopt(\.labsData, empty: [LabValue]())
        adopt(\.outcomesData, empty: [OutcomeEntry]())
        adopt(\.foodLibraryData, empty: FoodLibrarySlice())
        return adoptedAll
    }

    /// True when the column holds bytes this build can't decode as `T` —
    /// corrupt, or written by a newer build with a case this one doesn't
    /// know. Reads fall back to empty for such a column, so writing that
    /// empty value back would wipe the data on every device; the column
    /// stays as it is until a build that can read it saves.
    private func holdsUnreadable<T: Decodable>(
        _ type: T.Type,
        at keyPath: KeyPath<StoredProfile, Data?>,
        replacingWith data: Data
    ) -> Bool {
        guard let stored = self[keyPath: keyPath], stored != data,
              (try? sdDecoder.decode(T.self, from: stored)) == nil
        else { return false }
        AppLog.swiftData.error(
            "Profile column \(String(describing: T.self), privacy: .public) is unreadable by this build; leaving it untouched"
        )
        return true
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
            workoutLegacyMigrationCompleted: ext.workoutLegacyMigrationCompleted,
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
            weeklySummaryEnabled: ext.weeklySummaryEnabled ?? false,
            weeklySummaryOptInConfirmed: ext.weeklySummaryOptInConfirmed,
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
struct MealsSlice: Codable, Equatable {
    var mealHistory: [MealEntry] = []
    var dailyConsumption: [String: DailyConsumption] = [:]
}

struct HabitsSlice: Codable, Equatable {
    var habits: [Habit] = []
    var habitEntries: [HabitEntry] = []
}

struct MomentumSlice: Codable, Equatable {
    var atlasScore: Int = 0
    var atlasLevel: Int = 1
    var momentumAwardedToday: Int = 0
    var lastMomentumAwardDay: Date? = nil
    var momentumHistory: [MomentumDayPoint] = []
}

struct FoodLibrarySlice: Codable, Equatable {
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
    var workoutLegacyMigrationCompleted: Bool = false
    var customFoods: [CustomFood] = []
    /// Encoded as `[String]` so the round-trip JSON has a deterministic
    /// shape (Set has no ordering guarantee). The accessor on
    /// `toUserProfile()` collapses back to `Set<String>`.
    var favoriteFoodIDs: [String] = []
    var mealHistory: [MealEntry] = []
    /// Read-only legacy: the toggle is device-local now
    /// (`HealthSyncSettings.nutritionEnabledKey`), since Health
    /// permission is granted per device. Still carried through
    /// `residual(of:)` so a later-upgrading device seeds from the
    /// value the user chose before the split.
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
    /// optional so older blobs decode (default-off for the toggle,
    /// empty dict for the cache) without a migration. `weeklySummaries`
    /// is read-only legacy: the cache lives in `WeeklySummaryLocalStore`.
    var weeklySummaryEnabled: Bool? = nil
    var weeklySummaryOptInConfirmed: Bool = false
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

    init() {}

    /// Missing-key-tolerant decoding. The synthesized `init(from:)`
    /// throws on any absent non-optional key, so a blob written by an
    /// older build (or one that predates a newly added field) failed
    /// wholesale and fell back to `.empty` — wiping every blob-backed
    /// surface for the session. Each field decodes independently and
    /// falls back to its default; a present-but-corrupt value still
    /// throws, so genuine corruption stays detectable upstream.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nutritionTargets = try c.decodeIfPresent(NutritionTargets.self, forKey: .nutritionTargets)
        creatorAttribution = try c.decodeIfPresent(CreatorAttribution.self, forKey: .creatorAttribution)
        affiliateApplication = try c.decodeIfPresent(AffiliateApplication.self, forKey: .affiliateApplication)
        emailSubscription = try c.decodeIfPresent(EmailSubscription.self, forKey: .emailSubscription)
        weightHistory = try c.decodeIfPresent([WeightEntry].self, forKey: .weightHistory) ?? []
        progressPhotoFilenames = try c.decodeIfPresent([String].self, forKey: .progressPhotoFilenames) ?? []
        dailyConsumption = try c.decodeIfPresent([String: DailyConsumption].self, forKey: .dailyConsumption) ?? [:]
        workoutHistory = try c.decodeIfPresent([WorkoutEntry].self, forKey: .workoutHistory) ?? []
        workoutLegacyMigrationCompleted = try c.decodeIfPresent(Bool.self, forKey: .workoutLegacyMigrationCompleted) ?? false
        customFoods = try c.decodeIfPresent([CustomFood].self, forKey: .customFoods) ?? []
        favoriteFoodIDs = try c.decodeIfPresent([String].self, forKey: .favoriteFoodIDs) ?? []
        mealHistory = try c.decodeIfPresent([MealEntry].self, forKey: .mealHistory) ?? []
        healthKitNutritionEnabled = try c.decodeIfPresent(Bool.self, forKey: .healthKitNutritionEnabled) ?? false
        outcomeHistory = try c.decodeIfPresent([OutcomeEntry].self, forKey: .outcomeHistory) ?? []
        labHistory = try c.decodeIfPresent([LabValue].self, forKey: .labHistory) ?? []
        lastKnownTimezoneIdentifier = try c.decodeIfPresent(String.self, forKey: .lastKnownTimezoneIdentifier)
        streakFreezeDays = try c.decodeIfPresent([String].self, forKey: .streakFreezeDays) ?? []
        recipes = try c.decodeIfPresent([Recipe].self, forKey: .recipes) ?? []
        protocolNotes = try c.decodeIfPresent([ProtocolNote].self, forKey: .protocolNotes) ?? []
        biologyConfig = try c.decodeIfPresent(BiologyConfig.self, forKey: .biologyConfig) ?? .default
        trainingPreferences = try c.decodeIfPresent(TrainingPreferences.self, forKey: .trainingPreferences)
        weeklySummaryEnabled = try c.decodeIfPresent(Bool.self, forKey: .weeklySummaryEnabled)
        weeklySummaryOptInConfirmed = try c.decodeIfPresent(Bool.self, forKey: .weeklySummaryOptInConfirmed) ?? false
        weeklySummaries = try c.decodeIfPresent([String: WeeklySummary].self, forKey: .weeklySummaries)
        goalDate = try c.decodeIfPresent(Date.self, forKey: .goalDate)
        habits = try c.decodeIfPresent([Habit].self, forKey: .habits) ?? []
        habitEntries = try c.decodeIfPresent([HabitEntry].self, forKey: .habitEntries) ?? []
        atlasScore = try c.decodeIfPresent(Int.self, forKey: .atlasScore) ?? 0
        atlasLevel = try c.decodeIfPresent(Int.self, forKey: .atlasLevel) ?? 1
        momentumAwardedToday = try c.decodeIfPresent(Int.self, forKey: .momentumAwardedToday) ?? 0
        lastMomentumAwardDay = try c.decodeIfPresent(Date.self, forKey: .lastMomentumAwardDay)
        momentumHistory = try c.decodeIfPresent([MomentumDayPoint].self, forKey: .momentumHistory) ?? []
    }

    /// Snapshot of everything that still lives in the blob. The split
    /// areas (meals, habits, momentum, weight, labs, outcomes, food
    /// library, weekly summaries) are deliberately left at their
    /// defaults — their canonical home is the dedicated `StoredProfile`
    /// columns, and duplicating them here would resurrect the whole-
    /// blob conflict this split exists to remove. Reads still honour a
    /// legacy blob that carries them (rows written before the split).
    static func residual(of profile: UserProfile) -> ProfileExtension {
        var ext = ProfileExtension()
        ext.nutritionTargets = profile.nutritionTargets
        ext.creatorAttribution = profile.creatorAttribution
        ext.affiliateApplication = profile.affiliateApplication
        ext.emailSubscription = profile.emailSubscription
        ext.progressPhotoFilenames = profile.progressPhotoFilenames
        ext.workoutHistory = profile.workoutHistory
        ext.healthKitNutritionEnabled = profile.healthKitNutritionEnabled
        ext.workoutLegacyMigrationCompleted = profile.workoutLegacyMigrationCompleted
        ext.lastKnownTimezoneIdentifier = profile.lastKnownTimezoneIdentifier
        ext.streakFreezeDays = Array(profile.streakFreezeDays).sorted()
        ext.recipes = profile.recipes
        ext.protocolNotes = profile.protocolNotes
        ext.biologyConfig = profile.biologyConfig
        ext.trainingPreferences = profile.trainingPreferences
        ext.weeklySummaryEnabled = profile.weeklySummaryEnabled
        ext.weeklySummaryOptInConfirmed = profile.weeklySummaryOptInConfirmed
        ext.goalDate = profile.goalDate
        return ext
    }
}
