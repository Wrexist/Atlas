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
        // Skip if SwiftData already has data (migration already ran).
        // This is also the safe moment to expire old `.migrated` safety
        // nets — cleanup only ever touches archives, which by definition
        // exist only after a verified migration, never source files.
        guard !repo.hasAnyData else {
            persistence.cleanUpExpiredArchivedLegacyFiles()
            return
        }

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
        repo.beginSaveBatch()
        if let protocols { repo.saveProtocols(protocols) }
        if let entries   { repo.saveEntries(entries)     }
        if let profile   { repo.saveProfile(profile)     }

        // Verify the import by reading it back — counts and identities,
        // not just "some data exists". A partial import (a swallowed
        // repo save error, a failed commit) previously passed the old
        // `hasAnyData` check and archived the only remaining copy of
        // the user's data.
        if let failure = verificationFailure(
            protocols: protocols, entries: entries, profile: profile
        ) {
            AppLog.persistence.error(
                "Migration verification failed (\(failure, privacy: .public)) — rolling back partial import, leaving JSON files in place for retry"
            )
            // Return to the empty pre-migration state (`hasAnyData` was
            // false on entry, so nothing but this import is deleted) so
            // the next launch retries instead of orphaning the JSON.
            // Pending (uncommitted) inserts are discarded first — the
            // bulk delete only reaches the store, and deleteAll's save
            // would otherwise persist the very rows being rolled back.
            repo.discardPendingChanges()
            repo.deleteAll()
            return
        }

        persistence.archiveLegacyFiles()
    }

    /// Read-back verification of an import that just ran. Returns a
    /// diagnostic string on the first mismatch, nil when everything the
    /// source files carried is present in SwiftData with matching IDs.
    /// Internal (not private) so the mismatch branches are unit-testable
    /// without forcing a real partial import.
    func verificationFailure(
        protocols: [PeptideProtocol]?,
        entries: [ProtocolEntry]?,
        profile: UserProfile?
    ) -> String? {
        if repo.commitDidFail { return "commit failed" }
        if let protocols {
            let stored = Set(repo.loadProtocols().map(\.id))
            let expected = Set(protocols.map(\.id))
            if stored != expected {
                return "protocol IDs mismatch (\(stored.count)/\(expected.count))"
            }
        }
        if let entries {
            let stored = Set(repo.loadEntries().map(\.id))
            let expected = Set(entries.map(\.id))
            if stored != expected {
                return "entry IDs mismatch (\(stored.count)/\(expected.count))"
            }
        }
        if let profile {
            guard let stored = repo.loadProfile() else { return "profile missing after import" }
            if stored.name != profile.name { return "profile name mismatch" }
        }
        return nil
    }
}
