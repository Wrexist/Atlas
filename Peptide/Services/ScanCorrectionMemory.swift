import Foundation

/// One time the user fixed what the scanner guessed: it saw "spaghetti,
/// 250 g", they logged "Fullkornspasta, 180 g".
struct ScanCorrection: Codable, Hashable, Sendable {
    let seen: String
    let seenGrams: Double
    var loggedAs: String
    var grams: Double
    var brand: String?
    var date: Date

    /// The wire shape `food-scan` reads into its prompt.
    var payload: [String: Any] {
        var fields: [String: Any] = ["seen": seen, "seen_grams": seenGrams, "logged_as": loggedAs, "grams": grams]
        if let brand { fields["brand"] = brand }
        return fields
    }
}

/// Remembers how the user corrects scans and hands the most recent fixes
/// back to the scanner, so the second photo of their usual oatmeal comes
/// back with their name for it and their portion, not a generic guess.
///
/// Kept in UserDefaults on this device only, like `BarcodeScanHistory`:
/// it's scanner tuning, not part of the user's synced record.
@MainActor
final class ScanCorrectionMemory {

    static let shared = ScanCorrectionMemory()

    /// Enough distinct foods to cover a person's regular meals.
    static let maxStored = 60
    /// What one scan carries; the proxy reads no more than this.
    static let maxSent = 15
    /// A portion change smaller than this is the stepper's granularity,
    /// not a correction worth teaching.
    static let gramsTolerance = 0.15

    private static let storeKey = "com.peptidesai.app.scan-corrections.v1"
    private let defaults: UserDefaults

    /// Newest first.
    private(set) var corrections: [ScanCorrection]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        corrections = defaults.data(forKey: Self.storeKey)
            .flatMap { try? JSONDecoder().decode([ScanCorrection].self, from: $0) } ?? []
    }

    var recent: [ScanCorrection] { Array(corrections.prefix(Self.maxSent)) }

    /// Records the item if the user renamed it or moved the portion well
    /// away from the estimate; replaces any older fix of the same food.
    func record(seen: String, seenGrams: Double, loggedAs: String, grams: Double, brand: String?, now: Date = Date()) {
        let seenKey = Self.key(seen)
        guard !seenKey.isEmpty, !Self.key(loggedAs).isEmpty, grams.isFinite, grams > 0 else { return }
        let renamed = seenKey != Self.key(loggedAs)
        let resized = seenGrams > 0 && abs(grams - seenGrams) / seenGrams > Self.gramsTolerance
        guard renamed || resized else { return }

        corrections.removeAll { Self.key($0.seen) == seenKey }
        corrections.insert(ScanCorrection(seen: seen, seenGrams: seenGrams, loggedAs: loggedAs,
                                          grams: grams, brand: brand?.nilIfEmpty, date: now), at: 0)
        corrections = Array(corrections.prefix(Self.maxStored))
        save()
    }

    func eraseAll() {
        corrections = []
        defaults.removeObject(forKey: Self.storeKey)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(corrections) else { return }
        defaults.set(data, forKey: Self.storeKey)
    }

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
