import CryptoKit
import UIKit

/// A food's product photo, lifted off its background when Vision could.
struct ProductPhoto: Sendable {
    let image: UIImage
    /// The background is gone, so the thumbnail sets the product on the
    /// food's own tint instead of a white card.
    let isCutout: Bool
}

/// Downloads each packshot once, cuts the product out on-device, and keeps
/// the result in `Caches/` so a library row never pays for Vision twice.
///
/// Cut-outs run one at a time at utility priority: a page of search
/// results would otherwise start two dozen Vision requests at once.
actor ProductPhotoStore {

    static let shared = ProductPhotoStore()

    /// Files kept on disk, newest first. A cut-out is ~30-80 KB, so this
    /// holds a well-used library in a few tens of MB.
    static let defaultMaxFiles = 400

    typealias CutOut = @Sendable (UIImage) throws -> UIImage?

    private final class Entry {
        let photo: ProductPhoto
        init(_ photo: ProductPhoto) { self.photo = photo }
    }

    /// Read synchronously by `FoodThumbnail` so a scrolled-back row draws
    /// its photo on the first frame. NSCache is thread-safe.
    nonisolated(unsafe) private let memory: NSCache<NSURL, Entry> = {
        let cache = NSCache<NSURL, Entry>()
        cache.totalCostLimit = 40 * 1024 * 1024
        return cache
    }()

    private let directory: URL
    private let session: URLSession
    private let cutOut: CutOut
    private let maxFiles: Int
    private var inFlight: [URL: Task<ProductPhoto?, Never>] = [:]
    private var visionTail: Task<Void, Never>?

    init(
        directory: URL = URL.cachesDirectory.appending(path: "product-cutouts", directoryHint: .isDirectory),
        session: URLSession = .shared,
        maxFiles: Int = ProductPhotoStore.defaultMaxFiles,
        cutOut: @escaping CutOut = ProductCutoutEngine.cutOut
    ) {
        self.directory = directory
        self.session = session
        self.maxFiles = maxFiles
        self.cutOut = cutOut
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    nonisolated func cached(_ url: URL) -> ProductPhoto? {
        memory.object(forKey: url as NSURL)?.photo
    }

    func photo(for url: URL) async -> ProductPhoto? {
        if let cached = cached(url) { return cached }
        if let running = inFlight[url] { return await running.value }
        let task = Task { await load(url) }
        inFlight[url] = task
        let photo = await task.value
        inFlight[url] = nil
        if let photo {
            let pixels = photo.image.size.width * photo.image.scale * photo.image.size.height * photo.image.scale
            memory.setObject(Entry(photo), forKey: url as NSURL, cost: Int(pixels) * 4)
        }
        return photo
    }

    private func load(_ url: URL) async -> ProductPhoto? {
        if let stored = stored(url) { return stored }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data)
        else { return nil }

        switch await cutOutSerially(image) {
        case .success(let cutout?):
            guard let png = cutout.pngData() else { return ProductPhoto(image: cutout, isCutout: true) }
            store(png, at: file(for: url, cutout: true))
            return ProductPhoto(image: cutout, isCutout: true)
        case .success(nil):
            store(data, at: file(for: url, cutout: false))
            return ProductPhoto(image: image, isCutout: false)
        case .failure:
            // Vision couldn't run (Simulator, memory pressure). Show the
            // photo now and leave the cut for a later launch.
            return ProductPhoto(image: image, isCutout: false)
        }
    }

    private func cutOutSerially(_ image: UIImage) async -> Result<UIImage?, Error> {
        let previous = visionTail
        let cutOut = self.cutOut
        let job = Task.detached(priority: .utility) { () -> Result<UIImage?, Error> in
            await previous?.value
            return Result { try cutOut(image) }
        }
        visionTail = Task { _ = await job.value }
        return await job.value
    }

    private func store(_ data: Data, at file: URL) {
        try? data.write(to: file, options: .atomic)
        pruneIfNeeded()
    }

    /// Drops the oldest files once the directory passes `maxFiles`.
    private func pruneIfNeeded() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys
        ), files.count > maxFiles else { return }
        let modified = { (file: URL) in
            (try? file.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
        }
        for file in files.sorted(by: { modified($0) > modified($1) }).dropFirst(maxFiles) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func stored(_ url: URL) -> ProductPhoto? {
        if let image = UIImage(contentsOfFile: file(for: url, cutout: true).path) {
            return ProductPhoto(image: image, isCutout: true)
        }
        if let image = UIImage(contentsOfFile: file(for: url, cutout: false).path) {
            return ProductPhoto(image: image, isCutout: false)
        }
        return nil
    }

    private func file(for url: URL, cutout: Bool) -> URL {
        let key = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appending(path: key + (cutout ? ".png" : ".photo"))
    }
}
