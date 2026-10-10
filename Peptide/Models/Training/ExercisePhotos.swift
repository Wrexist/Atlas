import ImageIO
import UIKit

/// Start and finish photos for every catalog exercise, bundled as
/// `<id>_0.jpg` / `<id>_1.jpg` from free-exercise-db (Unlicense) by
/// `scripts/exercise-photos.py`. Custom exercises have none and keep the
/// muscle map.
///
/// Both caches are bounded rather than UIKit's named-image cache: decoding
/// every row's full photo while scrolling 873 exercises would hold hundreds
/// of megabytes. NSCache is thread-safe, hence `nonisolated(unsafe)`.
enum ExercisePhotos {
    struct Pair {
        let start: UIImage
        let finish: UIImage
    }

    /// The 56 pt list tile at 3x.
    private static let thumbnailPixels = 168

    nonisolated(unsafe) private static let photos: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 8
        return cache
    }()

    nonisolated(unsafe) private static let thumbnails: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 150
        return cache
    }()

    /// Cached so the focus screen's timer-driven redraws don't reread disk.
    static func pair(for exerciseID: String) -> Pair? {
        guard let start = photo(exerciseID, index: 0),
              let finish = photo(exerciseID, index: 1) else { return nil }
        return Pair(start: start, finish: finish)
    }

    static func thumbnail(for exerciseID: String) -> UIImage? {
        let key = exerciseID as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let url = url(exerciseID, index: 0),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: thumbnailPixels,
              ] as CFDictionary) else { return nil }
        let thumbnail = UIImage(cgImage: image)
        thumbnails.setObject(thumbnail, forKey: key)
        return thumbnail
    }

    private static func photo(_ exerciseID: String, index: Int) -> UIImage? {
        let key = "\(exerciseID)_\(index)" as NSString
        if let cached = photos.object(forKey: key) { return cached }
        guard let url = url(exerciseID, index: index),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        photos.setObject(image, forKey: key)
        return image
    }

    private static func url(_ exerciseID: String, index: Int) -> URL? {
        Bundle.main.url(forResource: "\(exerciseID)_\(index)", withExtension: "jpg")
    }
}
