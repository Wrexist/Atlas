import Foundation

/// JSON-file persistence for the surfaces SwiftData doesn't own: custom
/// peptides and the widget/watch snapshot in the App Group container.
///
/// **Concurrency invariant.** The `@unchecked Sendable` here is earned by
/// `queue`: every encode, decode, and file write funnels through one serial
/// queue, so the shared `JSONEncoder`/`JSONDecoder` — which are *not* safe to
/// use concurrently — are only ever touched by one thread at a time. The
/// reachable callers (the app, the widget extension, the App Intents
/// extension) are separate processes, and cross-process interleaving is
/// handled by `.atomic` writes, which publish via rename rather than in place.
///
/// Don't reach around `queue` by adding a new encode/decode path; add it
/// inside `save`/`load` instead.
final class PersistenceService: @unchecked Sendable {
    static let shared = PersistenceService()

    private let fileManager = FileManager.default

    private let queue = DispatchQueue(label: "com.peptidesai.persistence")

    /// Documents directory. `nil` only on the rare devices/sandboxes where the
    /// container is unavailable; callers must handle nil by skipping IO.
    private var documentsDirectory: URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private var sharedContainerURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
    }

    private var protocolsURL: URL? { documentsDirectory?.appendingPathComponent("protocols.json") }
    private var entriesURL: URL? { documentsDirectory?.appendingPathComponent("entries.json") }
    private var profileURL: URL? { documentsDirectory?.appendingPathComponent("profile.json") }
    private var customPeptidesURL: URL? { documentsDirectory?.appendingPathComponent("custom-peptides.json") }
    private var widgetDataURL: URL? { sharedContainerURL?.appendingPathComponent("widget-data.json") }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init() {}

    // MARK: - Save

    func saveProtocols(_ protocols: [PeptideProtocol]) {
        guard let url = protocolsURL else { return }
        save(protocols, to: url)
    }

    func saveEntries(_ entries: [ProtocolEntry]) {
        guard let url = entriesURL else { return }
        save(entries, to: url)
    }

    func saveProfile(_ profile: UserProfile) {
        guard let url = profileURL else { return }
        save(profile, to: url)
    }

    func saveCustomPeptides(_ peptides: [Peptide]) {
        guard let url = customPeptidesURL else { return }
        save(peptides, to: url)
    }

    // MARK: - Load

    func loadProtocols() -> [PeptideProtocol]? {
        guard let url = protocolsURL else { return nil }
        return load([PeptideProtocol].self, from: url)
    }

    func loadEntries() -> [ProtocolEntry]? {
        guard let url = entriesURL else { return nil }
        return load([ProtocolEntry].self, from: url)
    }

    func loadProfile() -> UserProfile? {
        guard let url = profileURL else { return nil }
        return load(UserProfile.self, from: url)
    }

    func loadCustomPeptides() -> [Peptide]? {
        guard let url = customPeptidesURL else { return nil }
        return load([Peptide].self, from: url)
    }

    // MARK: - Widget Data (Shared Container)

    func updateWidgetData(_ data: WidgetData) {
        guard let url = widgetDataURL else { return }
        save(data, to: url)
        Self.excludeFromBackup(url)
    }

    /// Marks regenerated-cache files (widget / watch payloads) so
    /// they don't end up in iCloud Backup. These are reconstructed
    /// from the canonical store on every launch; persisting them
    /// across restore wastes quota and slows backups for power
    /// users with multi-hundred-KB serialized state.
    static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    // MARK: - State

    var hasPersistedData: Bool {
        [protocolsURL, entriesURL, profileURL]
            .compactMap { $0 }
            .contains { fileManager.fileExists(atPath: $0.path) }
    }

    var protocolsFileExists: Bool { protocolsURL.map { fileManager.fileExists(atPath: $0.path) } ?? false }
    var entriesFileExists: Bool { entriesURL.map { fileManager.fileExists(atPath: $0.path) } ?? false }
    var profileFileExists: Bool { profileURL.map { fileManager.fileExists(atPath: $0.path) } ?? false }

    func clearAll() {
        // Archived `.migrated` files are included: they carry the same
        // personal data (name, email, body metrics, weight history) as
        // the live files, so "erase my data" must reach them too.
        for url in ([protocolsURL, entriesURL, profileURL, customPeptidesURL, widgetDataURL].compactMap { $0 } + archivedLegacyURLs) {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                AppLog.persistence.error("Failed to remove \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Archived legacy files

    /// How long a `.migrated` safety-net file is retained after a
    /// verified migration. Long enough that a data problem would have
    /// surfaced (and a backup/export made) across many launches; short
    /// enough that personal data doesn't sit on disk indefinitely.
    static let archivedLegacyRetentionDays = 90

    private var archivedLegacyURLs: [URL] {
        [protocolsURL, entriesURL, profileURL].compactMap {
            $0?.deletingPathExtension().appendingPathExtension("migrated")
        }
    }

    /// Deletes `.migrated` archives older than the retention window.
    /// Touches archive names only — never a live `.json` — and archives
    /// exist only after migration verification passed, so this can never
    /// destroy the sole copy of user data.
    func cleanUpExpiredArchivedLegacyFiles(now: Date = Date()) {
        let cutoff = TimeInterval(Self.archivedLegacyRetentionDays) * 86_400
        for url in archivedLegacyURLs {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let modified = (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
            guard let modified, now.timeIntervalSince(modified) > cutoff else { continue }
            do {
                try fileManager.removeItem(at: url)
                AppLog.persistence.info("Expired legacy archive \(url.lastPathComponent, privacy: .public) removed")
            } catch {
                AppLog.persistence.error("Failed to expire \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// True when any `.migrated` archive is still on disk. Test +
    /// diagnostics hook.
    var hasArchivedLegacyFiles: Bool {
        archivedLegacyURLs.contains { fileManager.fileExists(atPath: $0.path) }
    }

    /// Renames legacy JSON files to `.migrated` so MigrationService knows not to re-run.
    /// Logs (but does not propagate) move failures.
    func archiveLegacyFiles() {
        for url in [protocolsURL, entriesURL, profileURL].compactMap({ $0 }) {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let archived = url.deletingPathExtension().appendingPathExtension("migrated")
            do {
                try fileManager.moveItem(at: url, to: archived)
            } catch {
                AppLog.persistence.error("Failed to archive \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Private

    /// Returns true on a successful write. Callers can use the result
    /// to surface a "couldn't save your changes" toast / reload from
    /// disk to keep the in-memory state coherent with the on-disk
    /// truth. The error is also logged for diagnostics.
    @discardableResult
    private func save<T: Encodable>(_ value: T, to url: URL) -> Bool {
        queue.sync {
            do {
                let data = try encoder.encode(value)
                // .completeFileProtection encrypts the file at rest while
                // the device is locked. The profile JSON carries the
                // user's captured email and creator-attribution data and
                // shouldn't be readable from a locked-device filesystem
                // dump (audit security H-1). Backups still include the
                // profile — that's intentional, the user expects a phone
                // restore to recover their name / metrics / weight
                // history; the email and attribution survive too. The
                // protection only blocks the off-device-attacker case.
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                return true
            } catch {
                AppLog.persistence.error("Failed to save \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
    }

    /// Returns `nil` for both "file absent" and "decode failed". Callers needing to
    /// distinguish the two cases should check `fileManager.fileExists(atPath:)` first.
    /// Decode failures (data corruption) are logged; absence is silent.
    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        queue.sync {
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            do {
                let data = try Data(contentsOf: url)
                return try decoder.decode(type, from: data)
            } catch {
                AppLog.persistence.error("Failed to load \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }
}
