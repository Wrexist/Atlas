import Foundation
import UIKit

/// Thin wrapper around the app's Documents directory for progress
/// photos. Filenames are timestamped UUIDs (so collisions never happen)
/// and stored as JPEGs at quality 0.85, downscaled to `maxDimension` on
/// the longest edge — a 48 MP pick used to be written byte-for-byte.
///
/// Reading is `ProgressPhotoCache`'s job: it decodes at draw size and
/// off the main actor, and keeps photos saved before the downscale
/// existed cheap to render.
///
/// Nothing here writes to iCloud or any backend; images stay strictly
/// on-device, matching the privacy line on the Today scroll's
/// progress-photos card.
enum ProgressPhotoStorage {

    enum Failure: LocalizedError {
        case missingDirectory
        case decoding
        case encoding
        case write(Error)

        var errorDescription: String? {
            switch self {
            case .missingDirectory: "Couldn't find the Documents directory."
            case .decoding:         "Couldn't read that photo. Try a different one."
            case .encoding:         "Couldn't encode the photo as a JPEG."
            case .write(let err):   "Couldn't save the photo: \(err.localizedDescription)"
            }
        }
    }

    private static let folderName = "ProgressPhotos"

    /// Longest-edge ceiling for a stored photo. A modern phone camera
    /// hands us 4000×3000 or larger; the biggest thing that ever draws
    /// one of these is the full-screen viewer, so anything past ~2000 px
    /// is storage and decode cost for pixels the user never sees.
    private static let maxDimension: CGFloat = 2000

    /// Persists the image to disk and returns a stable filename callers
    /// can hand to `dataStore.addProgressPhotoFilename(...)`. The
    /// filename is timestamped + UUID so ordering by name still reads
    /// chronologically without parsing the UUID portion.
    static func save(_ image: UIImage, compressionQuality: CGFloat = 0.85) throws -> String {
        guard let data = downscaled(image).jpegData(compressionQuality: compressionQuality) else {
            throw Failure.encoding
        }
        return try write(data)
    }

    /// Decodes, downscales and encodes off the main actor, then writes.
    /// Preferred over `save(_:)` from UI code: the picker hands back raw
    /// camera data, and decoding a 48 MP JPEG on the main thread is a
    /// visible stall on its own, before any resize.
    static func save(imageData: Data, compressionQuality: CGFloat = 0.85) async throws -> String {
        let encoded = await Task.detached(priority: .userInitiated) { () -> Data? in
            guard let image = UIImage(data: imageData) else { return nil }
            return downscaled(image).jpegData(compressionQuality: compressionQuality)
        }.value
        guard let encoded else { throw Failure.decoding }
        return try write(encoded)
    }

    private static func write(_ data: Data) throws -> String {
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

    /// Aspect-preserving downscale so the longest edge is at most
    /// `maxDimension` **pixels**. Returns the original untouched when
    /// it's already smaller — re-rendering a small photo would only cost
    /// quality.
    ///
    /// Measured in pixels, not points: `UIImage.size` is points, and an
    /// image carrying a 2× or 3× scale holds correspondingly more pixels
    /// than its size suggests.
    nonisolated static func downscaled(_ image: UIImage) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        guard longest > maxDimension, longest > 0 else { return image }
        let ratio = maxDimension / longest
        let target = CGSize(
            width: (pixelWidth * ratio).rounded(),
            height: (pixelHeight * ratio).rounded()
        )
        // Scale 1 explicitly: the renderer otherwise inherits the
        // screen's scale, so a "2000" ceiling would mean 2000 *points* —
        // 6000 pixels on a 3× device, larger than the photo we set out
        // to shrink. Opaque because the output is JPEG, which has no
        // alpha channel to preserve.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Removes the on-disk file. Caller still has to drop the filename
    /// from `profile.progressPhotoFilenames` — kept separate so
    /// half-completed deletes (file gone but profile still references
    /// it) self-heal on next read: `ProgressPhotoCache` returns nothing
    /// for the missing file and the surface falls back to a placeholder.
    static func delete(filename: String) {
        ProgressPhotoCache.shared.invalidate(filename)
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
        ProgressPhotoCache.shared.removeAll()
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
