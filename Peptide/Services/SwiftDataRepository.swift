import Foundation
import SwiftData

/// SwiftData-backed persistence for protocols, entries, and profile.
/// Widget data stays in PersistenceService (requires App Groups / shared container).
@MainActor
final class SwiftDataRepository {
    static let shared = SwiftDataRepository()

    private var container: ModelContainer?

    /// True when the on-disk store could not be opened and we fell back to an
    /// in-memory container. The app remains usable, but mutations won't persist
    /// across launches. DataStore surfaces this to the user via `lastError`.
    private(set) var isUsingFallbackStore = false

    /// True when neither on-disk nor in-memory containers could be created.
    /// All reads return empty and writes are no-ops. DataStore surfaces this
    /// to the user via `lastError`.
    private(set) var isInoperable = false

    private var context: ModelContext? {
        container?.mainContext
    }

    private init() {
        let iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        if iCloudAvailable, let ck = Self.makeCloudContainer() {
            container = ck
            isCloudSyncEnabled = true
        } else if let local = Self.makeLocalContainer() {
            container = local
        } else if let inMemory = Self.makeInMemoryContainer() {
            container = inMemory
            isUsingFallbackStore = true
        } else {
            container = nil
            isInoperable = true
            assertionFailure("SwiftDataRepository: both on-disk and in-memory ModelContainer creation failed")
        }
    }

    private(set) var isCloudSyncEnabled = false

    private static func makeCloudContainer() -> ModelContainer? {
        do {
            let config = ModelConfiguration(cloudKitDatabase: .private("iCloud.com.peptidesai.app"))
            let container = try ModelContainer(
                for: StoredProtocol.self, StoredEntry.self, StoredProfile.self,
                StoredWorkoutSession.self, StoredCustomExercise.self,
                StoredRoutine.self, StoredPersonalRecord.self,
                configurations: config
            )
            AppLog.swiftData.info("Using CloudKit-backed store")
            return container
        } catch {
            AppLog.swiftData.error("CloudKit store failed, falling back to local: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func makeLocalContainer() -> ModelContainer? {
        do {
            return try ModelContainer(
                for: StoredProtocol.self, StoredEntry.self, StoredProfile.self,
                StoredWorkoutSession.self, StoredCustomExercise.self,
                StoredRoutine.self, StoredPersonalRecord.self
            )
        } catch {
            AppLog.swiftData.error("Failed to create persistent ModelContainer: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func makeInMemoryContainer() -> ModelContainer? {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(
                for: StoredProtocol.self, StoredEntry.self, StoredProfile.self,
                StoredWorkoutSession.self, StoredCustomExercise.self,
                StoredRoutine.self, StoredPersonalRecord.self,
                configurations: config
            )
        } catch {
            AppLog.swiftData.error("Failed to create in-memory ModelContainer: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Test Support

    /// Replaces the container with an in-memory store. Call in test setUp only.
    func configureForTesting() {
        container = Self.makeInMemoryContainer()
        isUsingFallbackStore = false
        isInoperable = container == nil
    }

    /// Removes all records. Call in test tearDown only.
    func deleteAll() {
        guard let context else { return }
        do {
            try context.delete(model: StoredProtocol.self)
            try context.delete(model: StoredEntry.self)
            try context.delete(model: StoredProfile.self)
            try context.delete(model: StoredWorkoutSession.self)
            try context.delete(model: StoredCustomExercise.self)
            try context.delete(model: StoredRoutine.self)
            try context.delete(model: StoredPersonalRecord.self)
            try context.save()
        } catch {
            AppLog.swiftData.error("deleteAll failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Protocols

    func saveProtocols(_ protocols: [PeptideProtocol]) {
        guard let context else { return }
        let existing: [StoredProtocol]
        do {
            existing = try context.fetch(FetchDescriptor<StoredProtocol>())
        } catch {
            AppLog.swiftData.error("Fetch protocols failed: \(error.localizedDescription, privacy: .public)")
            existing = []
        }
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let inputIds = Set(protocols.map(\.id))

        for stored in existing where !inputIds.contains(stored.id) {
            context.delete(stored)
        }

        for proto in protocols {
            if let stored = existingById[proto.id] {
                do {
                    try stored.update(from: proto)
                } catch {
                    AppLog.swiftData.error("Update StoredProtocol failed: \(error.localizedDescription, privacy: .public)")
                }
            } else {
                do {
                    let stored = try StoredProtocol.make(from: proto)
                    context.insert(stored)
                } catch {
                    AppLog.swiftData.error("Insert StoredProtocol failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        commit()
    }

    func loadProtocols() -> [PeptideProtocol] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<StoredProtocol>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let stored: [StoredProtocol]
        do {
            stored = try context.fetch(descriptor)
        } catch {
            AppLog.swiftData.error("Load protocols failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        return stored.compactMap {
            do {
                return try $0.toPeptideProtocol()
            } catch {
                AppLog.swiftData.error("Decode StoredProtocol failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    // MARK: - Entries

    func saveEntries(_ entries: [ProtocolEntry]) {
        guard let context else { return }
        let existing: [StoredEntry]
        do {
            existing = try context.fetch(FetchDescriptor<StoredEntry>())
        } catch {
            AppLog.swiftData.error("Fetch entries failed: \(error.localizedDescription, privacy: .public)")
            existing = []
        }
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let inputIds = Set(entries.map(\.id))

        for stored in existing where !inputIds.contains(stored.id) {
            context.delete(stored)
        }

        for entry in entries {
            if let stored = existingById[entry.id] {
                do {
                    try stored.update(from: entry)
                } catch {
                    AppLog.swiftData.error("Update StoredEntry failed: \(error.localizedDescription, privacy: .public)")
                }
            } else {
                do {
                    let stored = try StoredEntry.make(from: entry)
                    context.insert(stored)
                } catch {
                    AppLog.swiftData.error("Insert StoredEntry failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        commit()
    }

    func loadEntries() -> [ProtocolEntry] {
        guard let context else { return [] }
        let stored: [StoredEntry]
        do {
            stored = try context.fetch(FetchDescriptor<StoredEntry>())
        } catch {
            AppLog.swiftData.error("Load entries failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        return stored.compactMap {
            do {
                return try $0.toProtocolEntry()
            } catch {
                AppLog.swiftData.error("Decode StoredEntry failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    // MARK: - Profile

    func saveProfile(_ profile: UserProfile) {
        guard let context else { return }
        let existing: StoredProfile?
        do {
            existing = try context.fetch(FetchDescriptor<StoredProfile>()).first
        } catch {
            AppLog.swiftData.error("Fetch profile failed: \(error.localizedDescription, privacy: .public)")
            existing = nil
        }

        if let existing {
            do {
                try existing.update(from: profile)
            } catch {
                AppLog.swiftData.error("Update StoredProfile failed: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            do {
                let stored = try StoredProfile.make(from: profile)
                context.insert(stored)
            } catch {
                AppLog.swiftData.error("Insert StoredProfile failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        commit()
    }

    func loadProfile() -> UserProfile? {
        guard let context else { return nil }
        let stored: StoredProfile?
        do {
            stored = try context.fetch(FetchDescriptor<StoredProfile>()).first
        } catch {
            AppLog.swiftData.error("Load profile failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard let stored else { return nil }
        do {
            return try stored.toUserProfile()
        } catch {
            AppLog.swiftData.error("Decode StoredProfile failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Workout sessions

    /// Upserts a single workout session. Used by the live workout
    /// screen as the user checks sets — one call per save event. The
    /// `commit()` call inside flushes the SwiftData context so widgets
    /// and the watch see the change without an extra round-trip.
    func upsertWorkoutSession(_ session: WorkoutSession) {
        guard let context else { return }
        let sessionID = session.id
        let descriptor = FetchDescriptor<StoredWorkoutSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        do {
            if let existing = try context.fetch(descriptor).first {
                try existing.update(from: session)
            } else {
                let stored = try StoredWorkoutSession.make(from: session)
                context.insert(stored)
            }
            commit()
        } catch {
            AppLog.swiftData.error("upsert workout session failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteWorkoutSession(id: UUID) {
        guard let context else { return }
        let targetID = id
        let descriptor = FetchDescriptor<StoredWorkoutSession>(
            predicate: #Predicate { $0.id == targetID }
        )
        do {
            for stored in try context.fetch(descriptor) {
                context.delete(stored)
            }
            commit()
        } catch {
            AppLog.swiftData.error("delete workout session failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadWorkoutSessions() -> [WorkoutSession] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<StoredWorkoutSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        do {
            let stored = try context.fetch(descriptor)
            return stored.compactMap {
                do {
                    return try $0.toWorkoutSession()
                } catch {
                    AppLog.swiftData.error("Decode StoredWorkoutSession failed: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
        } catch {
            AppLog.swiftData.error("Load workout sessions failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Fetches the single in-progress session if one exists.
    /// `WorkoutSessionService` invariant: at most one session has
    /// `finishedAt == nil` at any time.
    func loadActiveWorkoutSession() -> WorkoutSession? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<StoredWorkoutSession>(
            predicate: #Predicate { $0.finishedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor).first.flatMap {
                try? $0.toWorkoutSession()
            }
        } catch {
            AppLog.swiftData.error("Load active workout failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Custom exercises

    func upsertCustomExercise(_ exercise: CustomExercise) {
        guard let context else { return }
        let id = exercise.id
        let descriptor = FetchDescriptor<StoredCustomExercise>(
            predicate: #Predicate { $0.id == id }
        )
        do {
            if let existing = try context.fetch(descriptor).first {
                try existing.update(from: exercise)
            } else {
                let stored = try StoredCustomExercise.make(from: exercise)
                context.insert(stored)
            }
            commit()
        } catch {
            AppLog.swiftData.error("upsert custom exercise failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteCustomExercise(id: String) {
        guard let context else { return }
        let exerciseID = id
        let descriptor = FetchDescriptor<StoredCustomExercise>(
            predicate: #Predicate { $0.id == exerciseID }
        )
        do {
            for stored in try context.fetch(descriptor) {
                context.delete(stored)
            }
            commit()
        } catch {
            AppLog.swiftData.error("delete custom exercise failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadCustomExercises() -> [CustomExercise] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<StoredCustomExercise>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        do {
            return try context.fetch(descriptor).compactMap {
                do {
                    return try $0.toCustomExercise()
                } catch {
                    AppLog.swiftData.error("Decode StoredCustomExercise failed: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
        } catch {
            AppLog.swiftData.error("Load custom exercises failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Routines

    func upsertRoutine(_ routine: Routine) {
        guard let context else { return }
        let routineID = routine.id
        let descriptor = FetchDescriptor<StoredRoutine>(
            predicate: #Predicate { $0.id == routineID }
        )
        do {
            if let existing = try context.fetch(descriptor).first {
                try existing.update(from: routine)
            } else {
                let stored = try StoredRoutine.make(from: routine)
                context.insert(stored)
            }
            commit()
        } catch {
            AppLog.swiftData.error("upsert routine failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteRoutine(id: UUID) {
        guard let context else { return }
        let targetID = id
        let descriptor = FetchDescriptor<StoredRoutine>(
            predicate: #Predicate { $0.id == targetID }
        )
        do {
            for stored in try context.fetch(descriptor) {
                context.delete(stored)
            }
            commit()
        } catch {
            AppLog.swiftData.error("delete routine failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadRoutines() -> [Routine] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<StoredRoutine>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor).compactMap {
                do {
                    return try $0.toRoutine()
                } catch {
                    AppLog.swiftData.error("Decode StoredRoutine failed: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
        } catch {
            AppLog.swiftData.error("Load routines failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Personal records

    func upsertPersonalRecord(_ record: PersonalRecord) {
        guard let context else { return }
        let id = record.exerciseID
        let descriptor = FetchDescriptor<StoredPersonalRecord>(
            predicate: #Predicate { $0.exerciseID == id }
        )
        do {
            if let existing = try context.fetch(descriptor).first {
                existing.update(from: record)
            } else {
                context.insert(StoredPersonalRecord.make(from: record))
            }
            commit()
        } catch {
            AppLog.swiftData.error("upsert PR failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadPersonalRecords() -> [PersonalRecord] {
        guard let context else { return [] }
        do {
            return try context.fetch(FetchDescriptor<StoredPersonalRecord>())
                .map { $0.toPersonalRecord() }
        } catch {
            AppLog.swiftData.error("Load PRs failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Removes the PR row for a given exercise. Used by tests to
    /// scrub state and (eventually) by a "reset this exercise"
    /// affordance the user might surface if their PR data gets
    /// corrupted. No-op when the row doesn't exist.
    func deletePersonalRecord(exerciseID: String) {
        guard let context else { return }
        let id = exerciseID
        let descriptor = FetchDescriptor<StoredPersonalRecord>(
            predicate: #Predicate { $0.exerciseID == id }
        )
        do {
            for row in try context.fetch(descriptor) {
                context.delete(row)
            }
            commit()
        } catch {
            AppLog.swiftData.error("delete PR failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - State

    var hasAnyData: Bool {
        guard let context else { return false }
        let descriptors: [() throws -> Int] = [
            { try context.fetchCount(FetchDescriptor<StoredProtocol>()) },
            { try context.fetchCount(FetchDescriptor<StoredEntry>()) },
            { try context.fetchCount(FetchDescriptor<StoredProfile>()) },
            { try context.fetchCount(FetchDescriptor<StoredWorkoutSession>()) },
            { try context.fetchCount(FetchDescriptor<StoredCustomExercise>()) },
            { try context.fetchCount(FetchDescriptor<StoredRoutine>()) },
        ]
        for descriptor in descriptors {
            do {
                if try descriptor() > 0 { return true }
            } catch {
                AppLog.swiftData.error("hasAnyData fetchCount failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return false
    }

    // MARK: - Private

    private func commit() {
        guard let context else { return }
        do {
            try context.save()
        } catch {
            AppLog.swiftData.error("context.save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
