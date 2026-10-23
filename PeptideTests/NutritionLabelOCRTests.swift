import XCTest
@testable import Peptide

/// Tests for the pure parser inside `NutritionLabelOCR`. The Vision
/// pipeline that produces the input strings isn't exercised here —
/// it's an I/O wrapper with no decisions of its own. The parser is
/// where every interesting branch lives.
///
/// Each test case feeds a list of label-line strings (the same shape
/// `VNRecognizeTextRequest` returns, top to bottom) and asserts what
/// the parser extracted.
final class NutritionLabelOCRTests: XCTestCase {

    // MARK: - Standard US label

    func test_parse_extractsCaloriesAndMacros_fromStandardUSLabel() {
        let lines = [
            "Nutrition Facts",
            "Serving size 1 cup (240g)",
            "Calories 250",
            "Total Fat 12g",
            "Saturated Fat 4g",
            "Trans Fat 0g",
            "Cholesterol 30mg",
            "Sodium 470mg",
            "Total Carbohydrate 31g",
            "Dietary Fiber 4g",
            "Total Sugars 5g",
            "Protein 5g",
        ]
        let parsed = NutritionLabelParser.parse(lines: lines)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.nutriments.calories, 250)
        XCTAssertEqual(parsed?.nutriments.fatG, 12)
        XCTAssertEqual(parsed?.nutriments.carbsG, 31)
        XCTAssertEqual(parsed?.nutriments.proteinG, 5)
        XCTAssertEqual(parsed?.nutriments.fiberG, 4)
        XCTAssertEqual(parsed?.nutriments.sugarsG, 5)
        XCTAssertEqual(parsed?.servingGrams, 240)
    }

    // MARK: - Total Fat vs Saturated Fat row

    func test_parse_picksTotalFat_notSaturated() {
        // The bare keyword "fat" appears in "Saturated Fat 4g" too,
        // so the parser must prefer the row starting with
        // "total fat" / "fat content" / etc.
        let lines = [
            "Total Fat 12g",
            "Saturated Fat 4g",
        ]
        let parsed = NutritionLabelParser.parse(lines: lines)
        XCTAssertEqual(parsed?.nutriments.fatG, 12)
    }

    func test_parse_picksFat_whenOnlyBareFatRowExists() {
        // Some EU labels write "Fat 12g" without the "Total" prefix.
        let lines = [
            "Energy 1050 kJ / 250 kcal",
            "Fat 12g",
            "Carbohydrate 30g",
            "Protein 5g",
        ]
        let parsed = NutritionLabelParser.parse(lines: lines)
        XCTAssertEqual(parsed?.nutriments.fatG, 12)
    }

    // MARK: - EU energy formats

    func test_parse_prefersKcal_whenBothKjAndKcalPresent() {
        let lines = [
            "Energy 1050 kJ / 250 kcal",
            "Protein 5g",
        ]
        let parsed = NutritionLabelParser.parse(lines: lines)
        XCTAssertEqual(parsed?.nutriments.calories, 250)
    }

    func test_parse_convertsKjToKcal_whenOnlyKjPresent() throws {
        let lines = [
            "Energy 1050 kJ",
            "Protein 5g",
        ]
        let parsed = NutritionLabelParser.parse(lines: lines)
        // 1050 kJ / 4.184 ≈ 250.96 kcal
        XCTAssertEqual(try XCTUnwrap(parsed?.nutriments.calories), 251, accuracy: 1)
    }

    // MARK: - Percent daily value column

    func test_parse_ignoresPercentDailyValueColumn() {
        // "Total Fat 12g  18%" — without DV-skipping, the parser
        // would pick up 18 as the fat value.
        let lines = [
            "Total Fat 12g 18%",
            "Total Carbohydrate 31g 11%",
            "Protein 5g 10%",
        ]
        let parsed = NutritionLabelParser.parse(lines: lines)
        XCTAssertEqual(parsed?.nutriments.fatG, 12)
        XCTAssertEqual(parsed?.nutriments.carbsG, 31)
        XCTAssertEqual(parsed?.nutriments.proteinG, 5)
    }

    // MARK: - Decimal handling (European comma)

    func test_parse_acceptsCommaAsDecimalSeparator() throws {
        // Many EU labels write "12,5g" instead of "12.5g".
        let lines = [
            "Energy 1050 kJ / 250 kcal",
            "Fat 12,5g",
            "Carbohydrate 31,2g",
            "Protein 5,8g",
        ]
        let parsed = NutritionLabelParser.parse(lines: lines)
        XCTAssertEqual(try XCTUnwrap(parsed?.nutriments.fatG), 12.5, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(parsed?.nutriments.carbsG), 31.2, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(parsed?.nutriments.proteinG), 5.8, accuracy: 0.01)
    }

    // MARK: - Serving size parsing

    func test_parse_extractsServingGrams_fromUSFormat() {
        let lines = [
            "Serving size 1 cookie (30g)",
            "Calories 150",
        ]
        let parsed = NutritionLabelParser.parse(lines: lines)
        XCTAssertEqual(parsed?.servingGrams, 30)
        XCTAssertEqual(parsed?.servingSizeText, "Serving size 1 cookie (30g)")
    }

    func test_parse_extractsServingSizeText_evenWhenGramsMissing() {
        let lines = [
            "Serving size 1 muffin",
            "Calories 200",
        ]
        let parsed = NutritionLabelParser.parse(lines: lines)
        XCTAssertEqual(parsed?.servingSizeText, "Serving size 1 muffin")
        // Nil, not 1. This asserted a 1g serving, which was the same
        // first-number-on-the-line bug that read "1 cup (240g)" as one gram —
        // and it contradicted the test's own name. The grams are genuinely
        // missing here, and the field is optional so it can say so.
        XCTAssertNil(parsed?.servingGrams)
    }

    // MARK: - Per-100g normalisation

    func test_per100g_perServingPanelWithGrams_scalesToPer100g() throws {
        let lines = [
            "Serving size 1 cup (240g)",
            "Calories 250",
            "Total Fat 12g",
            "Protein 6g",
        ]
        let parsed = try XCTUnwrap(NutritionLabelParser.parse(lines: lines))
        XCTAssertEqual(parsed.per100g.calories, 250 * 100 / 240, accuracy: 0.001)
        XCTAssertEqual(parsed.per100g.fatG, 5, accuracy: 0.001)
        XCTAssertEqual(parsed.per100g.proteinG, 2.5, accuracy: 0.001)
    }

    func test_loggable_oneServingOfPerServingPanel_logsPrintedValues() throws {
        let lines = [
            "Serving size 1 cup (240g)",
            "Calories 250",
            "Total Fat 12g",
        ]
        let parsed = try XCTUnwrap(NutritionLabelParser.parse(lines: lines))
        let product = ScannedProduct(
            barcode: "ocr:test", name: "Label", brand: nil, imageURL: nil,
            servingSizeText: parsed.servingSizeText, servingGrams: parsed.servingGrams,
            packageGrams: nil, per100g: parsed.per100g, nutriScore: nil, novaGroup: nil,
            fetchedAt: Date()
        )
        let meal = try XCTUnwrap(product.loggable(for: product.defaultPortion))
        XCTAssertEqual(meal.calories, 250)
        XCTAssertEqual(meal.fatG, 12)
    }

    func test_per100g_per100gPanel_keepsPrintedValues() throws {
        let lines = [
            "Nutrition per 100g",
            "Serving size 30g",
            "Energy 1050 kJ / 250 kcal",
            "Fat 12g",
        ]
        let parsed = try XCTUnwrap(NutritionLabelParser.parse(lines: lines))
        XCTAssertEqual(parsed.per100g.calories, 250)
        XCTAssertEqual(parsed.per100g.fatG, 12)
    }

    func test_per100g_unknownServingGrams_keepsPrintedValues() throws {
        let parsed = try XCTUnwrap(NutritionLabelParser.parse(lines: ["Serving size 1 muffin", "Calories 200"]))
        XCTAssertEqual(parsed.per100g.calories, 200)
    }

    // MARK: - Returns nil on non-nutrition-label text

    func test_parse_returnsNil_whenNoMacroKeywordsFound() {
        let lines = [
            "Ingredients: water, sugar, citric acid",
            "Best before: see top of can",
            "Made in Sweden",
        ]
        let parsed = NutritionLabelParser.parse(lines: lines)
        XCTAssertNil(parsed)
    }

    func test_parse_returnsNil_forEmptyInput() {
        XCTAssertNil(NutritionLabelParser.parse(lines: []))
    }

    // MARK: - Partial extraction

    func test_parse_returnsZerosForMissingMacros_whenAtLeastOneIsPresent() {
        // A label with only calories should still parse (better than
        // nothing) — the user can fill in macros via Edit on the
        // review card.
        let lines = ["Calories 150"]
        let parsed = NutritionLabelParser.parse(lines: lines)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.nutriments.calories, 150)
        XCTAssertEqual(parsed?.nutriments.proteinG, 0)
        XCTAssertEqual(parsed?.nutriments.carbsG, 0)
        XCTAssertEqual(parsed?.nutriments.fatG, 0)
    }

    // MARK: - firstNumber utility

    func test_firstNumber_skipsPercentValues() {
        XCTAssertEqual(NutritionLabelParser.firstNumber(in: "12% 30g"), 30)
    }

    func test_firstNumber_handlesCommaDecimal() {
        XCTAssertEqual(NutritionLabelParser.firstNumber(in: "12,5g protein"), 12.5)
    }

    func test_firstNumber_preferringLast_takesRightmost() {
        XCTAssertEqual(
            NutritionLabelParser.firstNumber(in: "1050 / 250", preferringLast: true),
            250
        )
    }

    func test_firstNumber_returnsNil_forNonNumericText() {
        XCTAssertNil(NutritionLabelParser.firstNumber(in: "calories per serving"))
    }

    // MARK: - Calories split from its value

    func test_parse_caloriesValueOnNextLine_ignoresDailyValueFootnote() {
        let lines = [
            "Nutrition Facts",
            "Calories",
            "230",
            "Total Fat 8g",
            "Protein 3g",
            "* The % Daily Value (DV) tells you how much a nutrient in a serving of food contributes to a daily diet.",
            "2,000 calories a day is used for general nutrition advice.",
        ]
        XCTAssertEqual(NutritionLabelParser.parse(lines: lines)?.nutriments.calories, 230)
    }

    func test_parse_caloriesHeaderWithoutValue_doesNotReadNextMacroRow() {
        let lines = ["Calories", "Total Fat 8g", "Energy 1046 kJ / 250 kcal"]
        XCTAssertEqual(NutritionLabelParser.parse(lines: lines)?.nutriments.calories, 250)
    }

    func test_parse_kilojoulesWithThousandsComma_convertsToKcal() throws {
        let calories = try XCTUnwrap(NutritionLabelParser.parse(lines: ["Energy 1,050 kJ"])?.nutriments.calories)
        XCTAssertEqual(calories, 1050 / 4.184, accuracy: 0.01)
    }

    func test_parse_referenceIntakeLine_isNotTheProductEnergy() {
        let lines = [
            "Reference intake of an average adult (8400 kJ / 2000 kcal)",
            "Energy 420 kJ / 100 kcal",
        ]
        XCTAssertEqual(NutritionLabelParser.parse(lines: lines)?.nutriments.calories, 100)
    }

    func test_firstNumber_commaDecimal_staysDecimalWithoutThousandsGrouping() {
        XCTAssertEqual(NutritionLabelParser.firstNumber(in: "salt 0,125 g", commaGroupsThousands: true), 0.125)
        XCTAssertEqual(NutritionLabelParser.firstNumber(in: "1,050"), 1.05)
    }
}
