import Foundation

/// Ingredients the user has at home ("Har hemma"), keyed by a recipe
/// ingredient's `pantryKey`. Device-local: what is in this kitchen's
/// cupboard is not worth a CloudKit schema change.
@MainActor @Observable
final class PantryStore {
    static let shared = PantryStore()

    private static let storageKey = "recipes.pantryKeys"
    private let defaults: UserDefaults

    private(set) var keys: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        keys = Set(defaults.stringArray(forKey: Self.storageKey) ?? [])
    }

    func has(_ key: String) -> Bool {
        keys.contains(key)
    }

    func toggle(_ key: String) {
        if keys.contains(key) {
            keys.remove(key)
        } else {
            keys.insert(key)
        }
        defaults.set(keys.sorted(), forKey: Self.storageKey)
    }
}
