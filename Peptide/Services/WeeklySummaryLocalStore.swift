import Foundation

/// Device-local home for the weekly recap cache
/// (`UserProfile.weeklySummaries`).
///
/// Apple Guideline 5.1.3(ii): health data must not be stored in iCloud.
/// A cached recap carries `KeyStats.hrvDelta`, and its AI text can quote
/// HRV or resting heart rate — while the SwiftData store is mirrored to
/// CloudKit. So `SwiftDataRepository` keeps the cache out of that store:
/// it reads this file into the profile on load and writes it on save,
/// and the synced `StoredProfile.summariesData` column (which CloudKit's
/// schema can't safely drop) is only ever written as nil.
///
/// The file sits in Application Support, excluded from device backup and
/// encrypted at rest with the same protection class as the SwiftData
/// store itself, so it's readable wherever the rest of the profile is.
/// The cache is regenerable — losing it (new device, iCloud account
/// switch) costs at most one re-generation of the current week.
@MainActor
final class WeeklySummaryLocalStore {
    static let shared = WeeklySummaryLocalStore(fileURL: defaultFileURL)

    static let defaultFileURL = URL.applicationSupportDirectory
        .appending(path: "WeeklySummaries", directoryHint: .isDirectory)
        .appending(path: "summaries.json", directoryHint: .notDirectory)

    private let fileURL: URL
    /// What the file currently holds, so the repository's frequent
    /// profile saves only touch disk when the cache actually changed.
    private var persisted: [String: WeeklySummary] = [:]
    /// False while the file exists but couldn't be read. Writes are
    /// refused until a later read succeeds, so a transient failure can
    /// never overwrite the cache with the empty one the load fell back to.
    private var isReadable = true

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The cached summaries, or nil when no file exists yet — the
    /// caller's cue to seed it from the legacy synced column.
    func load() -> [String: WeeklySummary]? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            isReadable = true
            persisted = [:]
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            isReadable = false
            AppLog.persistence.error(
                "Weekly summary cache unreadable: \(error.localizedDescription, privacy: .public)"
            )
            return [:]
        }
        isReadable = true
        do {
            persisted = try JSONDecoder().decode([String: WeeklySummary].self, from: data)
        } catch {
            // Corrupt, not unreadable: start over, the next save rewrites it.
            AppLog.persistence.error(
                "Weekly summary cache decode failed; starting empty: \(error.localizedDescription, privacy: .public)"
            )
            persisted = [:]
        }
        return persisted
    }

    func save(_ summaries: [String: WeeklySummary]) {
        guard isReadable, summaries != persisted else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(summaries).write(
                to: fileURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            // Set after every write: `.atomic` replaces the file, and
            // the exclusion flag lives on the file, not the path.
            var url = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            persisted = summaries
        } catch {
            AppLog.persistence.error(
                "Weekly summary cache write failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Account deletion and iCloud identity switches — the cache belongs
    /// to the previous owner and must not surface for the next one.
    func deleteAll() {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch CocoaError.fileNoSuchFile {
            // Nothing cached yet.
        } catch {
            AppLog.persistence.error(
                "Weekly summary cache delete failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        persisted = [:]
        isReadable = true
    }
}
