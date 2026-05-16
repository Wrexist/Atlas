import Foundation

/// One-time migration from legacy JSON files to SwiftData.
///
/// Idempotent: renames source files to `.migrated` so subsequent launches skip it.
/// The `.migrated` files are kept as a safety net and can be deleted by the user
/// after confirming data integrity.
@MainActor
final class MigrationService {
    static let shared = MigrationService()

    private let persistence = PersistenceService.shared
    private let repo: SwiftDataRepository

    private init() {
        self.repo = SwiftDataRepository.shared
    }

    /// Runs the migration if legacy JSON files exist and SwiftData has no data yet.
    func migrateIfNeeded() {
        // Skip if SwiftData already has data (migration already ran)
        guard !repo.hasAnyData else { return }

        // Skip if there are no legacy JSON files to migrate
        guard persistence.hasPersistedData else { return }

        // Track per-file integrity. A file that exists on disk but fails to decode
        // is a hard failure — leave the source intact so the user can recover or
        // export it manually before the next launch retries.
        let hadProtocolsFile = persistence.protocolsFileExists
        let hadEntriesFile   = persistence.entriesFileExists
        let hadProfileFile   = persistence.profileFileExists

        let protocols = persistence.loadProtocols()
        let entries   = persistence.loadEntries()
        let profile   = persistence.loadProfile()

        let protocolsOK = !hadProtocolsFile || protocols != nil
        let entriesOK   = !hadEntriesFile   || entries   != nil
        let profileOK   = !hadProfileFile   || profile   != nil

        // All-or-nothing: if any source file existed and failed to decode,
        // bail BEFORE writing anything to SwiftData. The previous order
        // (save protocols → bail on profile decode failure) left protocols
        // in SwiftData while profile.json was still the canonical store,
        // so the next launch saw `hasAnyData == true`, skipped migration,
        // and the user's profile fields were permanently orphaned.
        guard protocolsOK, entriesOK, profileOK else {
            AppLog.persistence.error(
                "Migration aborted before write (protocols: \(protocolsOK, privacy: .public), entries: \(entriesOK, privacy: .public), profile: \(profileOK, privacy: .public)) — leaving JSON files in place for retry"
            )
            return
        }

        // Decode succeeded for everything we expected. Now import.
        if let protocols { repo.saveProtocols(protocols) }
        if let entries   { repo.saveEntries(entries)     }
        if let profile   { repo.saveProfile(profile)     }

        // Sanity check: if we expected data but SwiftData ended up empty, something
        // went wrong silently. Don't archive in that case.
        let expectedData = (protocols ?? []).isEmpty == false
            || (entries ?? []).isEmpty == false
            || profile != nil
        if expectedData && !repo.hasAnyData {
            AppLog.persistence.error("Migration imported nothing despite source files — leaving JSON files in place")
            return
        }

        persistence.archiveLegacyFiles()
    }
}
