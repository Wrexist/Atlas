import Foundation

/// Lightweight UserDefaults-backed record of how the user has scanned
/// each barcode in the past. Two pieces of state, both keyed by
/// normalized barcode:
///
/// 1. **Last portion used** — restores the user's previous portion
///    choice (servings stepper count, whole-pack, or grams) when they
///    re-scan a product. Eliminates the most-repeated tap in the
///    scanner flow for users who log the same products daily.
///
/// 2. **Scan count + last-scanned date** — drives the recents-row
///    ordering. Pure last-fetched ordering buries a daily product
///    behind a one-off scan from yesterday; a recency × frequency
///    score keeps the protein bar you scan every morning at the top.
///
/// Stored in UserDefaults rather than SwiftData because the data is
/// pure infrastructure — never user-visible as a list, never edited
/// directly, evicted alongside the file cache when it expires. Also
/// keeps it off the CloudKit-backed SwiftData container for the same
/// reason `BarcodeProductCache` does: no point burning iCloud quota
/// on scan-count metadata.
///
/// Thread-safety: wrapped in an actor so concurrent writes from the
/// scan flow + a background stale-revalidation can't race.
actor BarcodeScanHistory {

    static let shared = BarcodeScanHistory()

    private let defaults: UserDefaults
    private static let storeKey = "com.peptidesai.app.barcode-scan-history.v1"

    /// Cap on how many barcodes we keep history for. Same order of
    /// magnitude as `BarcodeProductCache.defaultMaxEntries` so the two
    /// stay roughly in sync. Each entry is ~80 bytes serialized —
    /// 500 entries is well under any UserDefaults practical limit.
    private static let maxEntries = 500

    /// Half-life for the recency component of the recency × frequency
    /// score. A product scanned 14 days ago contributes half its
    /// frequency weight; one scanned 28 days ago, a quarter. Tuned so
    /// "the protein bar you scanned every morning for 3 weeks" stays
    /// ahead of "the one-off jar you scanned yesterday" without
    /// suppressing brand-new products forever.
    private static let recencyHalfLife: TimeInterval = 14 * 24 * 60 * 60

    /// One record per barcode the user has scanned + logged. Codable
    /// so the whole map serialises to UserDefaults as a single Data
    /// blob — atomic writes, no key-namespace bookkeeping.
    struct Entry: Codable, Equatable, Sendable {
        var scanCount: Int
        var lastScanned: Date
        var lastPortion: PortionRecord?
    }

    /// Codable mirror of `ScannedProduct.Portion`. The enum's
    /// associated values are Doubles and only one case (`.wholePackage`)
    /// has no payload, so a flat record with an optional double is
    /// cleaner than a custom Codable on the enum.
    struct PortionRecord: Codable, Equatable, Sendable {
        enum Mode: String, Codable, Sendable {
            case grams, servings, wholePackage
        }
        var mode: Mode
        var amount: Double?           // nil for .wholePackage

        init(_ portion: ScannedProduct.Portion) {
            switch portion {
            case .grams(let g):
                self.mode = .grams
                self.amount = g
            case .servings(let s):
                self.mode = .servings
                self.amount = s
            case .wholePackage:
                self.mode = .wholePackage
                self.amount = nil
            }
        }

        func toPortion() -> ScannedProduct.Portion {
            switch mode {
            case .grams:        return .grams(amount ?? 100)
            case .servings:     return .servings(amount ?? 1)
            case .wholePackage: return .wholePackage
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Reads

    /// Returns the user's previous portion choice for a barcode, or
    /// nil if they've never logged it before. Callers use this to
    /// override the product's `defaultPortion` so a re-scan lands on
    /// "1 serving" (or whatever the user previously picked).
    func lastPortion(for barcode: String) -> ScannedProduct.Portion? {
        load()[barcode]?.lastPortion?.toPortion()
    }

    /// Frequency-weighted score for ordering the recents row. Higher
    /// = should appear earlier. Computed as
    /// `scanCount × exp(-age/halfLife)` so a daily product steadily
    /// outranks a one-off no matter how recent the one-off is.
    /// Returns 0 for unknown barcodes, which sinks them to the end
    /// of any sort.
    func score(for barcode: String, now: Date = Date()) -> Double {
        guard let entry = load()[barcode] else { return 0 }
        let age = now.timeIntervalSince(entry.lastScanned)
        guard age >= 0 else { return Double(entry.scanCount) }
        let decay = exp(-age / Self.recencyHalfLife)
        return Double(entry.scanCount) * decay
    }

    /// Bulk-score a list of barcodes in one read so the recents row
    /// avoids N UserDefaults round-trips.
    func scores(for barcodes: [String], now: Date = Date()) -> [String: Double] {
        let store = load()
        var out: [String: Double] = [:]
        for barcode in barcodes {
            guard let entry = store[barcode] else {
                out[barcode] = 0
                continue
            }
            let age = max(0, now.timeIntervalSince(entry.lastScanned))
            out[barcode] = Double(entry.scanCount) * exp(-age / Self.recencyHalfLife)
        }
        return out
    }

    // MARK: - Writes

    /// Record that the user logged a meal from this barcode with a
    /// specific portion. Called from `BarcodeScanFlow.confirm` so the
    /// recents ordering and the next-scan portion default both
    /// reflect the user's actual log behaviour, not just whatever
    /// they previewed.
    func recordLog(barcode: String, portion: ScannedProduct.Portion, at date: Date = Date()) {
        var store = load()
        var entry = store[barcode] ?? Entry(scanCount: 0, lastScanned: date, lastPortion: nil)
        entry.scanCount += 1
        entry.lastScanned = date
        entry.lastPortion = PortionRecord(portion)
        store[barcode] = entry
        save(prune(store))
    }

    /// Reverse a `recordLog` call when the user hits Undo. Decrements
    /// the scan count and removes the entry entirely when the count
    /// hits zero, so an immediately-undone first scan leaves no trace
    /// in the recents row or in the next-scan portion default.
    func undoLog(barcode: String) {
        var store = load()
        guard var entry = store[barcode] else { return }
        entry.scanCount -= 1
        if entry.scanCount <= 0 {
            store.removeValue(forKey: barcode)
        } else {
            // Keep lastPortion populated — the user has logged this
            // product before the undone one. Don't clobber that.
            store[barcode] = entry
        }
        save(store)
    }

    /// Wipe everything. Used by tests + a future "clear history"
    /// settings affordance.
    func clear() {
        defaults.removeObject(forKey: Self.storeKey)
    }

    // MARK: - Internals

    private func load() -> [String: Entry] {
        guard let data = defaults.data(forKey: Self.storeKey),
              let decoded = try? Self.decoder.decode([String: Entry].self, from: data)
        else { return [:] }
        return decoded
    }

    private func save(_ store: [String: Entry]) {
        guard let data = try? Self.encoder.encode(store) else { return }
        defaults.set(data, forKey: Self.storeKey)
    }

    /// LRU prune to `maxEntries`. Same shape as BarcodeProductCache —
    /// drop the oldest entries by `lastScanned` once we cross the cap.
    /// The product cache evicts on its own; this just keeps the
    /// history dict from growing without bound for very heavy users.
    private func prune(_ store: [String: Entry]) -> [String: Entry] {
        guard store.count > Self.maxEntries else { return store }
        let sorted = store.sorted { $0.value.lastScanned > $1.value.lastScanned }
        return Dictionary(uniqueKeysWithValues: sorted.prefix(Self.maxEntries).map { ($0.key, $0.value) })
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
