import Foundation
import SwiftData

/// SwiftData-backed persistence for protocols, entries, and profile.
/// Widget data stays in PersistenceService (requires App Groups / shared container).
@MainActor
final class SwiftDataRepository {
    static let shared = SwiftDataRepository()

    private var container: ModelContainer

    private var context: ModelContext {
        container.mainContext
    }

    private init() {
        do {
            container = try ModelContainer(
                for: StoredProtocol.self, StoredEntry.self, StoredProfile.self
            )
        } catch {
            fatalError("SwiftDataRepository: failed to create ModelContainer — \(error)")
        }
    }

    // MARK: - Test Support

    /// Replaces the container with an in-memory store. Call in test setUp only.
    func configureForTesting() {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try ModelContainer(
                for: StoredProtocol.self, StoredEntry.self, StoredProfile.self,
                configurations: config
            )
        } catch {
            fatalError("SwiftDataRepository: failed to create in-memory container — \(error)")
        }
    }

    /// Removes all records. Call in test tearDown only.
    func deleteAll() {
        try? context.delete(model: StoredProtocol.self)
        try? context.delete(model: StoredEntry.self)
        try? context.delete(model: StoredProfile.self)
        try? context.save()
    }

    // MARK: - Protocols

    func saveProtocols(_ protocols: [PeptideProtocol]) {
        let existing = (try? context.fetch(FetchDescriptor<StoredProtocol>())) ?? []
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let inputIds = Set(protocols.map(\.id))

        // Remove deleted protocols
        for stored in existing where !inputIds.contains(stored.id) {
            context.delete(stored)
        }

        // Update existing / insert new
        for proto in protocols {
            if let stored = existingById[proto.id] {
                stored.update(from: proto)
            } else if let stored = try? StoredProtocol.make(from: proto) {
                context.insert(stored)
            }
        }

        try? context.save()
    }

    func loadProtocols() -> [PeptideProtocol] {
        let descriptor = FetchDescriptor<StoredProtocol>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let stored = (try? context.fetch(descriptor)) ?? []
        return stored.compactMap { try? $0.toPeptideProtocol() }
    }

    // MARK: - Entries

    func saveEntries(_ entries: [ProtocolEntry]) {
        let existing = (try? context.fetch(FetchDescriptor<StoredEntry>())) ?? []
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let inputIds = Set(entries.map(\.id))

        // Remove deleted entries
        for stored in existing where !inputIds.contains(stored.id) {
            context.delete(stored)
        }

        // Update existing / insert new
        for entry in entries {
            if let stored = existingById[entry.id] {
                stored.update(from: entry)
            } else if let stored = try? StoredEntry.make(from: entry) {
                context.insert(stored)
            }
        }

        try? context.save()
    }

    func loadEntries() -> [ProtocolEntry] {
        let stored = (try? context.fetch(FetchDescriptor<StoredEntry>())) ?? []
        return stored.compactMap { try? $0.toProtocolEntry() }
    }

    // MARK: - Profile

    func saveProfile(_ profile: UserProfile) {
        let existing = (try? context.fetch(FetchDescriptor<StoredProfile>()))?.first
        if let existing {
            existing.update(from: profile)
        } else if let stored = try? StoredProfile.make(from: profile) {
            context.insert(stored)
        }
        try? context.save()
    }

    func loadProfile() -> UserProfile? {
        let stored = (try? context.fetch(FetchDescriptor<StoredProfile>()))?.first
        return try? stored?.toUserProfile()
    }

    // MARK: - State

    var hasAnyData: Bool {
        let protocolCount = (try? context.fetchCount(FetchDescriptor<StoredProtocol>())) ?? 0
        let profileCount  = (try? context.fetchCount(FetchDescriptor<StoredProfile>())) ?? 0
        return protocolCount > 0 || profileCount > 0
    }
}
