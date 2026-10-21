import XCTest
@testable import Peptide

final class FoodArtworkTests: XCTestCase {
    func test_candyBrand_getsCandy() {
        XCTAssertEqual(FoodArtwork.match("Ferrari Hallon").emoji, "🍬")
    }

    func test_swedishCompound_matchesByWordStart() {
        XCTAssertEqual(FoodArtwork.match("Kycklingfilé").emoji, "🍗")
        XCTAssertEqual(FoodArtwork.match("Jordgubbsylt").emoji, "🍓")
    }

    func test_shortKeyword_needsWholeWord() {
        XCTAssertEqual(FoodArtwork.match("Toast").emoji, "🍞", "\"ost\" must not fire inside \"toast\"")
        XCTAssertEqual(FoodArtwork.match("Grön te").emoji, "🍵")
    }

    func test_specificBeatsGeneral() {
        XCTAssertEqual(FoodArtwork.match("Chocolate milk").emoji, "🍫")
        XCTAssertEqual(FoodArtwork.match("Iced matcha latte").emoji, "🍵")
    }

    func test_skimMilk_isMilk() {
        XCTAssertEqual(FoodArtwork.match("Skummjölk").emoji, "🥛")
    }

    func test_glassAsServingOrNoodle_isNotIceCream() {
        XCTAssertEqual(FoodArtwork.match("Glass of milk").emoji, "🥛")
        XCTAssertEqual(FoodArtwork.match("Glass noodles").emoji, "🍜")
        XCTAssertEqual(FoodArtwork.match("Glassnudlar").emoji, "🍜")
        XCTAssertEqual(FoodArtwork.match("Glass").emoji, "🍦")
    }

    func test_jasmineTea_isTea() {
        XCTAssertEqual(FoodArtwork.match("Jasmine tea").emoji, "🍵")
        XCTAssertEqual(FoodArtwork.match("Jasminris").emoji, "🍚")
    }

    func test_watermelon_isFruit() {
        XCTAssertEqual(FoodArtwork.match("Vattenmelon").emoji, "🍍")
        XCTAssertEqual(FoodArtwork.match("Kolsyrat vatten").emoji, "💧")
    }

    func test_unknownFood_getsPlate() {
        XCTAssertEqual(FoodArtwork.match("Xyz 123"), .fallback)
    }
}
