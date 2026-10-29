import XCTest
@testable import Peptide

@MainActor
final class PantryStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "PantryStoreTests")
        defaults.removePersistentDomain(forName: "PantryStoreTests")
    }

    func test_deleteAll_forgetsAtHomeIngredientsAcrossLaunches() {
        let store = PantryStore(defaults: defaults, fridgeKeys: { [] })
        store.toggle("chicken")
        store.toggle("rice")

        store.deleteAll()

        XCTAssertFalse(store.has("chicken"))
        XCTAssertTrue(PantryStore(defaults: defaults, fridgeKeys: { [] }).keys.isEmpty)
    }
}
