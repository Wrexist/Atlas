import Foundation

/// Device-local home for weigh-ins Atlas took in from Apple Health.
///
/// Apple Guideline 5.1.3(ii): personal health data read from HealthKit
/// must not be stored in iCloud, and the profile's weight column is
/// mirrored to CloudKit. So `SwiftDataRepository` strips these entries
/// from every profile it writes and merges them back in on load, the
/// same split `WeeklySummaryLocalStore` gives the weekly recaps.
///
/// Each entry's id is its HealthKit sample's UUID. Deleting one in Atlas
/// records that id as dismissed, so the next import pass doesn't bring a
/// wrong scale reading back. The file sits in Application Support,
/// excluded from device backup, readable after first unlock like the
/// SwiftData store itself.
@MainActor
final class HealthWeightLocalStore {
    static let shared = HealthWeightLocalStore(fileURL: defaultFileURL)

    static let defaultFileURL = URL.applicationSupportDirectory
        .appending(path: "HealthWeights", directoryHint: .isDirectory)
        .appending(path: "imported.json", directoryHint: .notDirectory)

    private struct Contents: Codable, Equatable {
        var entries: [WeightEntry] = []
        var dismissedIDs: Set<UUID> = []
    }

    private let fileURL: URL
    private var loaded: Contents?
    /// False while the file exists but couldn't be read. Writes are
    /// refused so a transient failure can't replace it with the empty
    /// contents the read fell back to.
    private var isReadable = true

    /// The file's contents, read on first use. A failed read is retried
    /// on the next access instead of hiding imported weigh-ins, and
    /// refusing every write, for the rest of the process.
    private var contents: Contents {
        get {
            if let loaded { return loaded }
            let read = load()
            if isReadable { loaded = read }
            return read
        }
        set { loaded = newValue }
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Imported weigh-ins still in the diary.
    var entries: [WeightEntry] { contents.entries }

    /// Samples the user deleted; never imported again.
    var dismissedIDs: Set<UUID> { contents.dismissedIDs }

    func isImported(_ id: UUID) -> Bool {
        contents.entries.contains { $0.id == id }
    }

    /// False when the file couldn't be written, so the caller must not
    /// put `additions` anywhere they'd reach iCloud.
    func record(_ additions: [WeightEntry]) -> Bool {
        update { $0.entries += additions }
    }

    /// Drops an imported entry from the diary for good. A no-op for a
    /// weight the user logged in Atlas.
    func dismiss(id: UUID) {
        guard isImported(id) else { return }
        update {
            $0.entries.removeAll { $0.id == id }
            $0.dismissedIDs.insert(id)
        }
    }

    /// Keeps samples that were never recorded here — imported by an
    /// earlier build under another id — from being imported again.
    func dismiss(ids: Set<UUID>) {
        update { $0.dismissedIDs.formUnion(ids) }
    }

    /// Forgets entries the diary no longer holds — replaced by a weight
    /// the user logged for that day.
    func retain(only ids: Set<UUID>) {
        update { $0.entries.removeAll { !ids.contains($0.id) } }
    }

    /// Account deletion and iCloud identity switches.
    func deleteAll() {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch CocoaError.fileNoSuchFile {
            // Nothing imported yet.
        } catch {
            AppLog.persistence.error(
                "Health weight store delete failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        contents = Contents()
        isReadable = true
    }

    /// True once `contents` matches the file, whether or not it changed.
    @discardableResult
    private func update(_ change: (inout Contents) -> Void) -> Bool {
        var next = contents
        change(&next)
        guard isReadable else { return false }
        guard next != contents else { return true }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(next).write(
                to: fileURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            // `.atomic` replaces the file, and the exclusion flag lives
            // on the file, not the path.
            var url = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            contents = next
            return true
        } catch {
            AppLog.persistence.error(
                "Health weight store write failed: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    private func load() -> Contents {
        isReadable = true
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Contents() }
        do {
            return try JSONDecoder().decode(Contents.self, from: Data(contentsOf: fileURL))
        } catch {
            isReadable = false
            AppLog.persistence.error(
                "Health weight store unreadable: \(error.localizedDescription, privacy: .public)"
            )
            return Contents()
        }
    }
}
