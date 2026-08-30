import Foundation
import ImageIO
import UIKit

/// Bounded in-memory cache of decoded progress photos, decoded at the
/// size the caller will actually draw.
///
/// Progress photos are full-frame camera shots. Decoding one to a
/// `UIImage` allocates width × height × 4 bytes — a 12 MP photo is ~48 MB
/// resident — and the grid, the compare sheet and the viewer each used to
/// do that synchronously inside `body`, per slot, on every render pass.
///
/// Two fixes, both here: `CGImageSourceCreateThumbnailAtIndex` decodes
/// straight to the target pixel size instead of allocating the full
/// bitmap and scaling down, and the result is cached so a re-render, a
/// sheet dismissal or a tab switch is a dictionary lookup. Photos saved
/// before the on-save downscale existed are still full-resolution on
/// disk, and this path is what keeps them cheap to show.
///
/// `@unchecked Sendable` for the same reason as `AvatarImageCache`:
/// `NSCache` is internally thread-safe and nothing here mutates instance
/// state after `init`.
final class ProgressPhotoCache: @unchecked Sendable {

    static let shared = ProgressPhotoCache()

    /// Target pixel sizes, one per surface. Decoding a 2×2 grid tile at
    /// viewer resolution would waste ~10× the memory for pixels nobody
    /// can see.
    enum Size: CGFloat {
        /// 56×70pt filmstrip thumbnails in the compare sheet.
        case thumbnail = 240
        /// Grid tiles and compare columns — roughly half-screen.
        case card = 800
        /// Full-screen viewer. Matches the on-save ceiling, so a photo
        /// saved today is decoded at its native size.
        case viewer = 2000
    }

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        // Bounded by bytes rather than count: the same photo can be
        // resident at two sizes, and a viewer-sized decode is worth
        // several tiles.
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    // MARK: - Reading

    /// Already-decoded image, or nil. Safe to call from `body` — it never
    /// touches the disk.
    func cached(_ filename: String, size: Size) -> UIImage? {
        cache.object(forKey: key(filename, size) as NSString)
    }

    /// Decodes any of `filenames` not already resident, off the main
    /// actor, and returns everything that resolved. Missing or corrupt
    /// files are simply absent from the result — callers render their
    /// own placeholder.
    func images(for filenames: [String], size: Size) async -> [String: UIImage] {
        var resolved: [String: UIImage] = [:]
        var missing: [String] = []

        for filename in filenames {
            if let hit = cached(filename, size: size) {
                resolved[filename] = hit
            } else {
                missing.append(filename)
            }
        }
        guard !missing.isEmpty else { return resolved }

        let urls: [(filename: String, url: URL)] = missing.compactMap { filename in
            guard let url = try? ProgressPhotoStorage.url(for: filename) else { return nil }
            return (filename, url)
        }

        let decoded = await Task.detached(priority: .userInitiated) {
            var out: [String: UIImage] = [:]
            for entry in urls {
                if let image = Self.downsample(url: entry.url, maxPixelSize: size.rawValue) {
                    out[entry.filename] = image
                }
            }
            return out
        }.value

        for (filename, image) in decoded {
            cache.setObject(image, forKey: key(filename, size) as NSString, cost: cost(of: image))
            resolved[filename] = image
        }
        return resolved
    }

    // MARK: - Invalidation

    /// Drops every size of one photo. Called when the file is deleted —
    /// filenames embed a UUID, so a stale entry could never be hit by a
    /// later photo, but holding tens of megabytes for a deleted image is
    /// its own problem.
    func invalidate(_ filename: String) {
        for size in [Size.thumbnail, .card, .viewer] {
            cache.removeObject(forKey: key(filename, size) as NSString)
        }
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    // MARK: - Internals

    private func key(_ filename: String, _ size: Size) -> String {
        "\(filename)@\(Int(size.rawValue))"
    }

    private func cost(of image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 0 }
        return cg.bytesPerRow * cg.height
    }

    /// Decodes at most `maxPixelSize` on the longest edge, straight from
    /// the file. `WithTransform` applies the EXIF orientation so a
    /// portrait shot isn't drawn on its side; `ShouldCacheImmediately`
    /// forces the pixel work to happen here, on this background thread,
    /// rather than lazily on the main thread at first draw.
    private static func downsample(url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source, 0, thumbnailOptions as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
}
