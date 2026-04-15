import Foundation

/// One-time migration from legacy JSON files to SwiftData.
///
/// Idempotent: renames source files to `.migrated` so subsequent launches skip it.
/// The `.migrated` files are kept as a safety net and can be deleted by the user
/// after confirming data integrity.
@MainActor
final class MigrationService {
    static let shared = MigrationService()
    private init() {}

    private let persistence = PersistenceService.shared
    private let repo = SwiftDataRepository.shared

    /// Runs the migration if legacy JSON files exist and SwiftData has no data yet.
    func migrateIfNeeded() {
        // Skip if SwiftData already has data (migration already ran)
        guard !repo.hasAnyData else { return }

        // Skip if there are no legacy JSON files to migrate
        guard persistence.hasPersistedData else { return }

        let protocols = persistence.loadProtocols() ?? []
        let entries   = persistence.loadEntries() ?? []
        let profile   = persistence.loadProfile()

        // Import into SwiftData
        repo.saveProtocols(protocols)
        repo.saveEntries(entries)
        if let profile { repo.saveProfile(profile) }

        // Only archive if data landed in SwiftData (guards against silent save failures)
        let nothingToImport = protocols.isEmpty && entries.isEmpty && profile == nil
        guard repo.hasAnyData || nothingToImport else { return }

        // Rename source files to mark migration complete
        persistence.archiveLegacyFiles()
    }
}
