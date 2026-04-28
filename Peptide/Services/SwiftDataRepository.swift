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
                for: StoredProtocol.self, StoredEntry.self, StoredProfile.self
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

    // MARK: - State

    var hasAnyData: Bool {
        guard let context else { return false }
        let descriptors: [() throws -> Int] = [
            { try context.fetchCount(FetchDescriptor<StoredProtocol>()) },
            { try context.fetchCount(FetchDescriptor<StoredEntry>()) },
            { try context.fetchCount(FetchDescriptor<StoredProfile>()) },
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
