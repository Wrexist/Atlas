import Foundation

/// Ingredients the user has at home ("Har hemma"), keyed by a recipe
/// ingredient's `pantryKey`: the ones ticked by hand plus whatever the
/// fridge holds. Device-local: what is in this kitchen's cupboard is not
/// worth a CloudKit schema change.
@MainActor @Observable
final class PantryStore {
    static let shared = PantryStore()

    private static let storageKey = "recipes.pantryKeys"
    private let defaults: UserDefaults
    private let fridgeKeys: @MainActor () -> Set<String>

    /// Ticked by hand on a recipe or the shopping list.
    private(set) var manualKeys: Set<String>

    init(defaults: UserDefaults = .standard, fridgeKeys: @escaping @MainActor () -> Set<String> = { FridgeStore.shared.pantryKeys }) {
        self.defaults = defaults
        self.fridgeKeys = fridgeKeys
        manualKeys = Set(defaults.stringArray(forKey: Self.storageKey) ?? [])
    }

    var keys: Set<String> {
        manualKeys.union(fridgeKeys())
    }

    func has(_ key: String) -> Bool {
        keys.contains(key)
    }

    /// True when the fridge holds it, so a tick can't take it away.
    func isInFridge(_ key: String) -> Bool {
        fridgeKeys().contains(key)
    }

    func toggle(_ key: String) {
        if manualKeys.contains(key) {
            manualKeys.remove(key)
        } else if !isInFridge(key) {
            manualKeys.insert(key)
        }
        defaults.set(manualKeys.sorted(), forKey: Self.storageKey)
    }

    func deleteAll() {
        manualKeys = []
        defaults.removeObject(forKey: Self.storageKey)
    }
}
