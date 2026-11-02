import Foundation

/// Which shopping-list rows are ticked off, and which ones "Clear checked"
/// put away, keyed by `GroceryListEngine.Item.key`. Device-local in
/// UserDefaults: it's a trip to the store, not something to sync.
@MainActor @Observable
final class GroceryChecklistStore {
    static let shared = GroceryChecklistStore(defaults: .standard)

    private(set) var checked: Set<String>
    private(set) var cleared: Set<String>

    private let defaults: UserDefaults
    private static let checkedKey = "com.peptidesai.app.grocery-list.checked.v1"
    private static let clearedKey = "com.peptidesai.app.grocery-list.cleared.v1"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        checked = Set(defaults.stringArray(forKey: Self.checkedKey) ?? [])
        cleared = Set(defaults.stringArray(forKey: Self.clearedKey) ?? [])
    }

    func toggle(_ key: String) {
        if checked.remove(key) == nil { checked.insert(key) }
        save()
    }

    /// Puts the checked rows away until the list is started over.
    func clearChecked() {
        cleared.formUnion(checked)
        checked = []
        save()
    }

    func startOver() {
        checked = []
        cleared = []
        save()
    }

    /// Forgets rows that are no longer on the list, so a new plan
    /// starts unticked instead of inheriting an old trip's state.
    func retain(_ keys: Set<String>) {
        let keptChecked = checked.intersection(keys)
        let keptCleared = cleared.intersection(keys)
        guard keptChecked != checked || keptCleared != cleared else { return }
        checked = keptChecked
        cleared = keptCleared
        save()
    }

    private func save() {
        defaults.set(checked.sorted(), forKey: Self.checkedKey)
        defaults.set(cleared.sorted(), forKey: Self.clearedKey)
    }
}
