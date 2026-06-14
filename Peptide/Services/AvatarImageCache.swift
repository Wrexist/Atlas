import Foundation
import UIKit

/// Tiny in-memory cache for decoded avatar `UIImage`s. The avatar is shown on
/// the WelcomeHeader (every HomeView render) and the ProfileHeader (every
/// ProfileView render). Decoding the JPEG every time costs 5–20ms and runs
/// synchronously on the main thread, so we keep the last few decoded images
/// around keyed by the source `Data` itself.
///
/// The key is the `Data` (bridged to `NSData`), not its `hashValue`:
/// `Data.hashValue` is per-process randomized and not collision-resistant,
/// so two different avatars could collide and the cache would hand back the
/// wrong image. `NSData` keys compare by full content, so a hash collision
/// just shares a bucket — it never returns the wrong avatar.
///
/// This is `final class @unchecked Sendable` because `NSCache` is internally
/// thread-safe and we never mutate `Cache` instance properties after init.
final class AvatarImageCache: @unchecked Sendable {
    static let shared = AvatarImageCache()

    private let cache = NSCache<NSData, UIImage>()

    private init() {
        cache.countLimit = 6
    }

    /// Returns the decoded `UIImage` for `data`, decoding off-cache only the
    /// first time. Returns `nil` if the data isn't a valid image.
    func image(for data: Data?) -> UIImage? {
        guard let data, !data.isEmpty else { return nil }
        let key = data as NSData
        if let cached = cache.object(forKey: key) { return cached }
        guard let decoded = UIImage(data: data) else { return nil }
        cache.setObject(decoded, forKey: key)
        return decoded
    }
}
