import Foundation

/// Pre-import snapshot store. Plan E's rollback layer — before
/// `BackupImportService.apply` mutates anything, the current state
/// is serialised to a timestamped JSON file under the system Caches
/// directory. If the import goes wrong, the user can pick that
/// snapshot from a recovery affordance in Settings and restore it
/// just like a regular backup.
///
/// Snapshots live in `Caches/` so the OS can evict under storage
/// pressure without losing user data — these are recovery
/// artifacts, not the canonical store. They're also excluded from
/// iCloud Backup (same pattern as widget/watch caches) so they
/// don't waste user quota.
///
/// Retention: oldest snapshots are pruned to `maxSnapshots` on every
/// write. 5 days is enough for a user to realise an import was a
/// mistake without letting the snapshot pile grow indefinitely.
@MainActor
enum BackupSnapshotService {

    static let maxSnapshots: Int = 5
    private static let fileNamePrefix = "atlas-pre-restore-"
    private static let fileExtension = "json"

    struct Info: Identifiable, Equatable, Sendable {
        let id: String
        let url: URL
        let createdAt: Date
        let sizeBytes: Int
    }

    // MARK: - Write

    /// Serialises the current state and writes to a new snapshot
    /// file. Returns the URL on success, nil on failure (no-op for
    /// the import path — a failed snapshot shouldn't block the
    /// import, just remove the safety net).
    @discardableResult
    static func snapshotCurrentState(dataStore: DataStore) -> URL? {
        guard let directory = snapshotDirectory() else { return nil }

        let timestamp = Int(Date().timeIntervalSince1970)
        let url = directory.appendingPathComponent(
            "\(fileNamePrefix)\(timestamp).\(fileExtension)"
        )

        let backup = AppBackup(
            exportDate: Date(),
            version: "1.0",
            protocols: dataStore.protocols,
            entries: dataStore.entries,
            profile: dataStore.profile
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(backup)
            try data.write(to: url, options: .atomic)
            PersistenceService.excludeFromBackup(url)
            prune()
            return url
        } catch {
            AppLog.persistence.error(
                "BackupSnapshot write failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    // MARK: - List + read

    static func availableSnapshots() -> [Info] {
        guard let directory = snapshotDirectory() else { return [] }
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []
        return contents
            .filter { $0.lastPathComponent.hasPrefix(fileNamePrefix) }
            .compactMap { url -> Info? in
                let values = try? url.resourceValues(forKeys: [
                    .contentModificationDateKey, .fileSizeKey,
                ])
                let date = values?.contentModificationDate ?? .distantPast
                let size = values?.fileSize ?? 0
                return Info(
                    id: url.lastPathComponent,
                    url: url,
                    createdAt: date,
                    sizeBytes: size
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Reads the snapshot bytes for re-import. Used by the Settings
    /// "Restore from snapshot" affordance — the rollback path just
    /// feeds these bytes back through `BackupImportService.apply`.
    static func read(_ info: Info) throws -> Data {
        try Data(contentsOf: info.url)
    }

    // MARK: - Prune

    private static func prune() {
        let infos = availableSnapshots()
        guard infos.count > maxSnapshots else { return }
        let fm = FileManager.default
        for info in infos.dropFirst(maxSnapshots) {
            try? fm.removeItem(at: info.url)
        }
    }

    // MARK: - Paths

    private static func snapshotDirectory() -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("PeptideBackupSnapshots", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
