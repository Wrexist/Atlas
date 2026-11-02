import XCTest
@testable import Peptide

final class FoodArtworkTests: XCTestCase {
    func test_candyBrand_getsCandy() {
        XCTAssertEqual(FoodArtwork.match("Ferrari Hallon").image, "candy")
    }

    func test_swedishCompound_matchesByWordStart() {
        XCTAssertEqual(FoodArtwork.match("Kycklingfilé").image, "chicken")
        XCTAssertEqual(FoodArtwork.match("Jordgubbsylt").image, "berries")
    }

    func test_shortKeyword_needsWholeWord() {
        XCTAssertEqual(FoodArtwork.match("Toast").image, "bread", "\"ost\" must not fire inside \"toast\"")
        XCTAssertEqual(FoodArtwork.match("Grön te").image, "tea")
    }

    func test_specificBeatsGeneral() {
        XCTAssertEqual(FoodArtwork.match("Chocolate milk").image, "chocolate")
        XCTAssertEqual(FoodArtwork.match("Iced matcha latte").image, "tea")
    }

    func test_skimMilk_isMilk() {
        XCTAssertEqual(FoodArtwork.match("Skummjölk").image, "milk")
    }

    func test_glassAsServingOrNoodle_isNotIceCream() {
        XCTAssertEqual(FoodArtwork.match("Glass of milk").image, "milk")
        XCTAssertEqual(FoodArtwork.match("Glass noodles").image, "noodle-soup")
        XCTAssertEqual(FoodArtwork.match("Glassnudlar").image, "noodle-soup")
        XCTAssertEqual(FoodArtwork.match("Glass").image, "ice-cream")
    }

    func test_jasmineTea_isTea() {
        XCTAssertEqual(FoodArtwork.match("Jasmine tea").image, "tea")
        XCTAssertEqual(FoodArtwork.match("Jasminris").image, "rice")
    }

    func test_watermelon_isFruit() {
        XCTAssertEqual(FoodArtwork.match("Vattenmelon").image, "tropical-fruit")
        XCTAssertEqual(FoodArtwork.match("Kolsyrat vatten").image, "water")
    }

    func test_englishWatermelon_isFruit_whileWaterStaysWater() {
        XCTAssertEqual(FoodArtwork.match("Watermelon").image, "tropical-fruit")
        XCTAssertEqual(FoodArtwork.match("watermelon slices").image, "tropical-fruit")
        XCTAssertEqual(FoodArtwork.match("Sparkling water").image, "water")
    }

    func test_unknownFood_getsPlate() {
        XCTAssertEqual(FoodArtwork.match("Xyz 123"), .fallback)
    }
}
