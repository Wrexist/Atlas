import Foundation

/// Automatic restore points: a full backup written about once a day
/// when the app goes to the background, kept by `RestorePointEngine`'s
/// daily + weekly rules.
///
/// They exist for bugs inside the app — a bad migration, a sync that
/// overwrites, an iCloud account switch. The iPhone's own backup can't
/// undo those, because it holds the same broken data.
///
/// Files live in Application Support, which the system never purges
/// and which the iPhone's iCloud backup includes, so the points leave
/// the phone with it. They are not in Documents: exposing Documents in
/// the Files app would also expose the live data files there (journal,
/// fridge, photos) to accidental deletion. A point can be shared from
/// the restore sheet instead.
@MainActor
enum RestorePointService {
    private static let folderName = "RestorePoints"
    nonisolated private static let fileNamePrefix = "atlas-restore-point-"
    nonisolated private static let fileExtension = "json"

    /// Writes a restore point if the newest one is at least a day old.
    /// Waits for the launch backfill first, so a point taken right after
    /// a cold launch still holds the full dose history.
    static func writeIfDue(dataStore: DataStore, now: Date = Date()) async {
        guard !dataStore.isEphemeral, let directory = directory() else { return }
        guard RestorePointEngine.isDue(latest: restorePoints().first?.createdAt, now: now) else { return }

        await dataStore.awaitEntryBackfill()
        let service = ExportService.shared
        let protocols = dataStore.protocols
        let entries = dataStore.entries
        let profile = dataStore.profile
        let workoutSessions = dataStore.allWorkoutSessionsForBackup()
        let routines = dataStore.routinesForBackup()
        let customExercises = dataStore.customExercisesForBackup()
        let personalRecords = dataStore.personalRecordsForBackup()
        let customPeptides = dataStore.customPeptides
        let fasts = SwiftDataRepository.shared.loadFasts()
        let healthWeightIDs = SwiftDataRepository.shared.healthWeightImportIDs(in: profile)
        let deviceLocal = DeviceLocalBackup.current()
        let url = directory.appendingPathComponent(
            "\(fileNamePrefix)\(Int(now.timeIntervalSince1970)).\(fileExtension)"
        )

        let written = await Task.detached(priority: .utility) {
            guard let data = service.exportFullBackup(
                protocols: protocols,
                entries: entries,
                profile: profile,
                workoutSessions: workoutSessions,
                routines: routines,
                customExercises: customExercises,
                personalRecords: personalRecords,
                customPeptides: customPeptides,
                fasts: fasts,
                healthWeightIDs: healthWeightIDs,
                deviceLocal: deviceLocal
            ) else { return false }
            return write(data, to: url)
        }.value
        if written { prune() }
    }

    /// Restore points, newest first.
    static func restorePoints() -> [BackupSnapshotService.Info] {
        guard let directory = directory() else { return [] }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []
        return contents
            .compactMap { url -> BackupSnapshotService.Info? in
                guard let createdAt = createdAt(fromFileName: url.lastPathComponent) else { return nil }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return BackupSnapshotService.Info(
                    id: url.lastPathComponent,
                    url: url,
                    createdAt: createdAt,
                    sizeBytes: size
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// "Delete all data" path: a restore point is a full copy of the
    /// user's data and must not outlive an erase.
    static func deleteAll() {
        guard let directory = directory() else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Files

    /// The point's time is in its name rather than its modification
    /// date, which a copy or a restore from an iPhone backup can change.
    nonisolated static func createdAt(fromFileName name: String) -> Date? {
        guard name.hasPrefix(fileNamePrefix), name.hasSuffix(".\(fileExtension)") else { return nil }
        let stamp = name.dropFirst(fileNamePrefix.count).dropLast(fileExtension.count + 1)
        guard let seconds = TimeInterval(stamp) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Readable until first unlock after a reboot, not only while
    /// unlocked: the write runs as the app leaves the screen, often
    /// just as the phone locks.
    nonisolated private static func write(_ data: Data, to url: URL) -> Bool {
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            AppLog.persistence.error("Restore point write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static func prune() {
        let points = restorePoints()
        let keep = RestorePointEngine.datesToKeep(points.map(\.createdAt), calendar: .current)
        for point in points where !keep.contains(point.createdAt) {
            try? FileManager.default.removeItem(at: point.url)
        }
    }

    /// Tests point this at a temporary folder.
    static var directoryOverrideForTesting: URL?

    private static func directory() -> URL? {
        let fm = FileManager.default
        let directory: URL
        if let directoryOverrideForTesting {
            directory = directoryOverrideForTesting
        } else {
            guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return nil
            }
            directory = base.appendingPathComponent(folderName, isDirectory: true)
        }
        if !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}
