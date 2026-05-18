import Foundation

/// File-backed cache of resolved barcode products. Lives in the system
/// `Caches/` directory so the OS can evict it under storage pressure
/// without touching user data, and is kept off the CloudKit-backed
/// SwiftData container — these entries are infrastructure, not user
/// records, so they shouldn't burn iCloud quota or sync across devices.
///
/// One JSON file per barcode keeps the implementation trivial: no
/// schema migrations, no index, and a "clear" is a single directory
/// removal. The TTL is enforced on read by comparing file modification
/// dates rather than baking timestamps into the payload.
actor BarcodeProductCache {

    static let shared = BarcodeProductCache()

    /// 30 days. Open Food Facts data changes slowly (a product's
    /// nutrition panel almost never moves), so a long TTL trades a
    /// negligible accuracy risk for a meaningful offline-experience win.
    static let defaultTTL: TimeInterval = 60 * 60 * 24 * 30

    /// Soft cap. The cache prunes the oldest entries on the next write
    /// once it crosses this threshold. Set generously — each entry is
    /// ~3 KB, so 500 entries is ~1.5 MB on disk.
    static let defaultMaxEntries: Int = 500

    private let directory: URL
    private let ttl: TimeInterval
    private let maxEntries: Int
    private let fileManager: FileManager

    init(
        directory: URL? = nil,
        ttl: TimeInterval = BarcodeProductCache.defaultTTL,
        maxEntries: Int = BarcodeProductCache.defaultMaxEntries,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.ttl = ttl
        self.maxEntries = maxEntries
        self.directory = directory ?? Self.defaultDirectory(using: fileManager)
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// Returns the cached product when present and within TTL. Treats
    /// any I/O or decoding error as a cache miss — the caller refetches.
    func read(barcode: String) -> ScannedProduct? {
        let url = fileURL(for: barcode)
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) <= ttl,
              let data = try? Data(contentsOf: url),
              let product = try? Self.decoder.decode(ScannedProduct.self, from: data)
        else {
            return nil
        }
        return product
    }

    /// Writes atomically so a partial write can't corrupt a later read.
    /// Best-effort: encoding/I/O failures are swallowed because a cache
    /// miss on the next call is the worst that can happen.
    /// Runs LRU eviction after writes to keep the cache from growing
    /// without bound.
    func write(_ product: ScannedProduct) {
        guard let data = try? Self.encoder.encode(product) else { return }
        try? data.write(to: fileURL(for: product.barcode), options: .atomic)
        pruneIfNeeded()
    }

    /// Returns the `limit` most-recently-scanned products, ordered by
    /// last-fetched-first. Used by the scanner UI to surface a "recently
    /// scanned" row above the live viewfinder so users can re-log
    /// without re-aiming the camera.
    ///
    /// Pre-filters candidates by TTL using only the directory listing's
    /// modification dates so stale entries are skipped without opening
    /// the file. Cuts a sweep of N `Data(contentsOf:)` reads down to
    /// only the live entries actually returned.
    func recent(limit: Int) -> [ScannedProduct] {
        guard limit > 0 else { return [] }
        let now = Date()
        let ttl = self.ttl
        let liveEntries = entriesByDescendingModifiedDate()
            .filter { now.timeIntervalSince($0.modified) <= ttl }

        var out: [ScannedProduct] = []
        out.reserveCapacity(min(limit, liveEntries.count))
        for entry in liveEntries {
            guard out.count < limit else { break }
            guard
                let data = try? Data(contentsOf: entry.url),
                let product = try? Self.decoder.decode(ScannedProduct.self, from: data)
            else { continue }
            out.append(product)
        }
        return out
    }

    /// Removes every cached entry. Used by tests and by a future
    /// "clear cache" affordance in settings.
    func clear() {
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Eviction

    /// LRU prune to `maxEntries`. Called from `write` so the cache
    /// self-trims as the user scans more products. Cheap when under cap.
    private func pruneIfNeeded() {
        let entries = entriesByDescendingModifiedDate()
        guard entries.count > maxEntries else { return }
        for entry in entries.dropFirst(maxEntries) {
            try? fileManager.removeItem(at: entry.url)
        }
    }

    private struct DirectoryEntry {
        let url: URL
        let modified: Date
    }

    private func entriesByDescendingModifiedDate() -> [DirectoryEntry] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []
        return contents
            .compactMap { url -> DirectoryEntry? in
                guard url.pathExtension == "json" else { return nil }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                return DirectoryEntry(url: url, modified: modified)
            }
            .sorted { $0.modified > $1.modified }
    }

    // MARK: - Internals

    /// Builds the on-disk URL for a cache entry. Barcodes from the OFF
    /// lookup path are normalised to 8-14 digits, and the OCR fallback
    /// builds `ocr:<uuid>` keys — both are safe filenames. Future
    /// callers might not be; the precondition keeps a malformed key
    /// (slashes, `..`) from escaping the cache directory and writing
    /// outside the sandbox-allowed Caches folder.
    private func fileURL(for barcode: String) -> URL {
        precondition(
            barcode.allSatisfy { $0.isLetter || $0.isNumber || $0 == ":" || $0 == "-" || $0 == "_" },
            "BarcodeProductCache key must be filename-safe: got \(barcode)"
        )
        return directory.appendingPathComponent("\(barcode).json")
    }

    private static func defaultDirectory(using fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("PeptideBarcode", isDirectory: true)
    }

    // Non-Sendable but thread-safe for read-only use after config.
    nonisolated(unsafe) private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    nonisolated(unsafe) private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
