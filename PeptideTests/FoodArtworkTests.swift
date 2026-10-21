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

    func test_unknownFood_getsPlate() {
        XCTAssertEqual(FoodArtwork.match("Xyz 123"), .fallback)
    }
}
