import Foundation
import UIKit

/// Thin wrapper around the app's Documents directory for progress
/// photos. Filenames are timestamped UUIDs (so collisions never happen)
/// and stored as JPEGs at quality 0.85 — good enough for the 2×2 grid
/// thumbnails without inflating the on-device footprint past a few MB
/// per photo.
///
/// Nothing here writes to iCloud or any backend; images stay strictly
/// on-device, matching the privacy line on the Lifestyle tab card.
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
        guard let url = try? url(for: filename) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// Removes the on-disk file. Caller still has to drop the filename
    /// from `profile.progressPhotoFilenames` — kept separate so
    /// half-completed deletes (file gone but profile still references
    /// it) self-heal on next read via `loadImage(for:) == nil`.
    static func delete(filename: String) {
        guard let url = try? url(for: filename) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func url(for filename: String) throws -> URL {
        try ensureDirectory().appendingPathComponent(filename)
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
