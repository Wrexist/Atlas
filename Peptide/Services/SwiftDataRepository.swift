import Foundation
import SwiftData

/// SwiftData-backed persistence for protocols, entries, and profile.
/// Widget data stays in PersistenceService (requires App Groups / shared container).
@MainActor
final class SwiftDataRepository {
    static let shared = SwiftDataRepository()

    private var container: ModelContainer

    /// True when the on-disk store could not be opened and we fell back to an
    /// in-memory container. The app remains usable, but mutations won't persist
    /// across launches. DataStore surfaces this to the user via `lastError`.
    private(set) var isUsingFallbackStore = false

    private var context: ModelContext {
        container.mainContext
    }

    private init() {
        if let onDisk = Self.makePersistentContainer() {
            container = onDisk
        } else {
            container = Self.makeInMemoryContainer()
            isUsingFallbackStore = true
        }
    }

    private static func makePersistentContainer() -> ModelContainer? {
        do {
            return try ModelContainer(
                for: StoredProtocol.self, StoredEntry.self, StoredProfile.self
            )
        } catch {
            AppLog.swiftData.error("Failed to create persistent ModelContainer: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func makeInMemoryContainer() -> ModelContainer {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(
                for: StoredProtocol.self, StoredEntry.self, StoredProfile.self,
                configurations: config
            )
        } catch {
            // In-memory container creation failing means the schema itself is
            // unusable — there's no recovery path. This only fires in catastrophic
            // misconfiguration, never on a real device.
            fatalError("SwiftDataRepository: in-memory fallback also failed — \(error)")
        }
    }

    // MARK: - Test Support

    /// Replaces the container with an in-memory store. Call in test setUp only.
    func configureForTesting() {
        container = Self.makeInMemoryContainer()
        isUsingFallbackStore = false
    }

    /// Removes all records. Call in test tearDown only.
    func deleteAll() {
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
        let descriptors: [() throws -> Int] = [
            { try self.context.fetchCount(FetchDescriptor<StoredProtocol>()) },
            { try self.context.fetchCount(FetchDescriptor<StoredEntry>()) },
            { try self.context.fetchCount(FetchDescriptor<StoredProfile>()) },
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
        do {
            try context.save()
        } catch {
            AppLog.swiftData.error("context.save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
