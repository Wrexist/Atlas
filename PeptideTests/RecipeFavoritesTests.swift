import XCTest
@testable import Peptide

@MainActor
final class RecipeFavoritesTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SwiftDataRepository.shared.configureForTesting()
    }

    override func tearDown() {
        SwiftDataRepository.shared.deleteAll()
        super.tearDown()
    }

    func test_toggleFavoriteRecipe_twice_returnsToUnsaved() {
        let store = DataStore(seedSampleData: false)

        store.toggleFavoriteRecipe(id: "beef-taco-bowl")
        XCTAssertTrue(store.isFavoriteRecipe(id: "beef-taco-bowl"))

        store.toggleFavoriteRecipe(id: "beef-taco-bowl")
        XCTAssertFalse(store.isFavoriteRecipe(id: "beef-taco-bowl"))
    }

    func test_storedProfile_roundTrip_keepsFavoriteRecipes() throws {
        let profile = UserProfile(
            name: "Casey",
            goals: [],
            memberSince: Date(),
            healthConnected: false,
            favoriteFoodIDs: ["5449000000996"],
            favoriteRecipeIDs: ["beef-taco-bowl", "tofu-coconut-curry"]
        )

        let roundTripped = try StoredProfile.make(from: profile).toUserProfile()

        XCTAssertEqual(roundTripped.favoriteRecipeIDs, ["beef-taco-bowl", "tofu-coconut-curry"])
        XCTAssertEqual(roundTripped.favoriteFoodIDs, ["5449000000996"])
    }

    func test_foodLibraryColumn_writtenBeforeRecipeFavorites_stillReadsFoodFavorites() throws {
        // The legacy blob holds no favourites, so a strict decode that
        // failed on the missing key would fall back to it and lose "123".
        let stored = try StoredProfile.make(from: .fresh)
        stored.foodLibraryData = Data(#"{"customFoods":[],"favoriteFoodIDs":["123"]}"#.utf8)

        let profile = try stored.toUserProfile()

        XCTAssertEqual(profile.favoriteFoodIDs, ["123"])
        XCTAssertTrue(profile.favoriteRecipeIDs.isEmpty)
    }

    func test_reconcile_duplicateRows_keepsFavoriteRecipesFromBoth() {
        var newer = UserProfile.fresh
        newer.favoriteRecipeIDs = ["beef-taco-bowl"]
        var older = UserProfile.fresh
        older.favoriteRecipeIDs = ["tofu-coconut-curry"]

        let merged = ProfileMergeEngine.reconcile(newer, with: older)

        XCTAssertEqual(merged.favoriteRecipeIDs, ["beef-taco-bowl", "tofu-coconut-curry"])
    }

    func test_rebasing_twoDevicesHeartDifferentRecipes_keepsBoth() {
        var baseline = UserProfile.fresh
        baseline.favoriteRecipeIDs = ["salmon-potatoes-broccoli"]
        var local = baseline
        local.favoriteRecipeIDs.insert("beef-taco-bowl")
        local.favoriteRecipeIDs.remove("salmon-potatoes-broccoli")
        var remote = baseline
        remote.favoriteRecipeIDs.insert("tofu-coconut-curry")

        let merged = ProfileMergeEngine.rebasing(local: local, baseline: baseline, remote: remote)

        XCTAssertEqual(merged.favoriteRecipeIDs, ["beef-taco-bowl", "tofu-coconut-curry"])
    }
}
