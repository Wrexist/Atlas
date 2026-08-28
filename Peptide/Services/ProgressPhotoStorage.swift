import Foundation
import UIKit

/// Thin wrapper around the app's Documents directory for progress
/// photos. Filenames are timestamped UUIDs (so collisions never happen)
/// and stored as JPEGs at quality 0.85 — good enough for the 2×2 grid
/// thumbnails without inflating the on-device footprint past a few MB
/// per photo.
///
/// Nothing here writes to iCloud or any backend; images stay strictly
/// on-device, matching the privacy line on the Today scroll's
/// progress-photos card.
enum ProgressPhotoStorage {

    enum Failure: LocalizedError {
        case missingDirectory
        case encoding
        case write(Error)

        var errorDescription: String? {
            switch self {
            case .missingDirectory: "Couldn't find the Documents directory."
            case .encoding:         "Couldn't encode the photo as a JPEG."
            case .write(let err):   "Couldn't save the photo: \(err.localizedDescription)"
            }
        }
    }

    private static let folderName = "ProgressPhotos"

    /// Persists the image to disk and returns a stable filename callers
    /// can hand to `dataStore.addProgressPhotoFilename(...)`. The
    /// filename is timestamped + UUID so ordering by name still reads
    /// chronologically without parsing the UUID portion.
    static func save(_ image: UIImage, compressionQuality: CGFloat = 0.85) throws -> String {
        guard let data = image.jpegData(compressionQuality: compressionQuality) else {
            throw Failure.encoding
        }
        let directory = try ensureDirectory()
        let filename = generateFilename()
        let url = directory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw Failure.write(error)
        }
        return filename
    }

    static func loadImage(for filename: String) -> UIImage? {
        do {
            let url = try url(for: filename)
            return UIImage(contentsOfFile: url.path)
        } catch {
            AppLog.persistence.error(
                "ProgressPhotoStorage.loadImage URL failed for \(filename, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// Removes the on-disk file. Caller still has to drop the filename
    /// from `profile.progressPhotoFilenames` — kept separate so
    /// half-completed deletes (file gone but profile still references
    /// it) self-heal on next read via `loadImage(for:) == nil`.
    static func delete(filename: String) {
        let url: URL
        do {
            url = try self.url(for: filename)
        } catch {
            AppLog.persistence.error(
                "ProgressPhotoStorage.delete URL failed for \(filename, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            // Already gone — half-completed delete self-healing path.
            // Not an error; the caller still drops the profile entry.
        } catch {
            AppLog.persistence.error(
                "ProgressPhotoStorage.delete failed for \(filename, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    static func url(for filename: String) throws -> URL {
        try ensureDirectory().appendingPathComponent(filename)
    }

    /// Removes the entire ProgressPhotos folder. Account-deletion path —
    /// photos are user-generated content and must not survive an erase.
    static func deleteAll() {
        guard let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return }
        let folder = documents.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Internals

    private static func ensureDirectory() throws -> URL {
        guard let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw Failure.missingDirectory
        }
        let folder = documents.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )
        }
        return folder
    }

    private static func generateFilename() -> String {
        let stamp = Int(Date().timeIntervalSince1970)
        let suffix = UUID().uuidString.prefix(6)
        return "progress-\(stamp)-\(suffix).jpg"
    }
}
