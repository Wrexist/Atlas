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

    private let directory: URL
    private let ttl: TimeInterval
    private let fileManager: FileManager

    init(
        directory: URL? = nil,
        ttl: TimeInterval = BarcodeProductCache.defaultTTL,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.ttl = ttl
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
    func write(_ product: ScannedProduct) {
        guard let data = try? Self.encoder.encode(product) else { return }
        try? data.write(to: fileURL(for: product.barcode), options: .atomic)
    }

    /// Removes every cached entry. Used by tests and by a future
    /// "clear cache" affordance in settings.
    func clear() {
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Internals

    private func fileURL(for barcode: String) -> URL {
        directory.appendingPathComponent("\(barcode).json")
    }

    private static func defaultDirectory(using fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("PeptideBarcode", isDirectory: true)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
