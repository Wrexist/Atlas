import XCTest
@testable import Peptide

/// The camera was never the limitation — `DataScanner` is configured
/// with a bare `.barcode()` and reads every symbology iOS supports. What
/// followed was: hand the payload to a digits-only validator and tell
/// the user their scan looked wrong. These cover the layer that fixes
/// that, and the GS1 arithmetic it leans on.
final class BarcodePayloadTests: XCTestCase {

    // MARK: - Check digits

    /// Real codes, verified against the printed check digit.
    func test_checkDigit_matchesPublishedCodes() {
        // Coca-Cola 330 ml, EAN-13.
        XCTAssertEqual(BarcodePayload.checkDigit(for: "544900000099"), 6)
        // A standard UPC-A textbook code.
        XCTAssertEqual(BarcodePayload.checkDigit(for: "03600029145"), 2)
        // EAN-8.
        XCTAssertEqual(BarcodePayload.checkDigit(for: "9638507"), 4)
    }

    func test_checkDigit_rejectsNonNumericInput() {
        XCTAssertNil(BarcodePayload.checkDigit(for: "12A45"))
        XCTAssertNil(BarcodePayload.checkDigit(for: ""))
    }

    func test_isValidGTIN_acceptsEveryStandardLength() {
        XCTAssertTrue(BarcodePayload.isValidGTIN("5449000000996"))   // EAN-13
        XCTAssertTrue(BarcodePayload.isValidGTIN("036000291452"))    // UPC-A
        XCTAssertTrue(BarcodePayload.isValidGTIN("96385074"))        // EAN-8
    }

    func test_isValidGTIN_rejectsABadCheckDigit() {
        XCTAssertFalse(BarcodePayload.isValidGTIN("5449000000995"))
    }

    func test_isValidGTIN_rejectsNonStandardLengths() {
        XCTAssertFalse(BarcodePayload.isValidGTIN("544900000099"))   // 12 of a 13
        XCTAssertFalse(BarcodePayload.isValidGTIN("1234567890"))
    }

    // MARK: - Alternate GTIN forms

    func test_candidates_offersTheThirteenDigitFormOfAUPC() {
        // The single most common real miss: a US carton prints 12
        // digits and the database holds the zero-padded 13.
        XCTAssertEqual(
            BarcodePayload.candidates(for: "036000291452"),
            ["036000291452", "0036000291452"]
        )
    }

    func test_candidates_offersTheTwelveDigitFormOfAZeroPaddedEAN() {
        XCTAssertEqual(
            BarcodePayload.candidates(for: "0036000291452"),
            ["0036000291452", "036000291452"]
        )
    }

    func test_candidates_unwrapsAnITF14CaseCodeToItsProduct() {
        // A GTIN-14 carries an indicator digit at the front and its own
        // check digit at the back; neither belongs to the product, so
        // the inner GTIN-13 has to be re-derived rather than sliced out.
        let inner = BarcodePayload.gtin13(insideGTIN14: "15449000000993")
        XCTAssertEqual(inner, "5449000000996")
        XCTAssertEqual(
            BarcodePayload.candidates(for: "15449000000993"),
            ["15449000000993", "5449000000996"]
        )
    }

    func test_candidates_leavesAPlainEAN13Alone() {
        XCTAssertEqual(BarcodePayload.candidates(for: "5449000000996"), ["5449000000996"])
    }

    func test_candidates_neverRepeatsAForm() {
        for code in ["5449000000996", "036000291452", "96385074", "15449000000993"] {
            let candidates = BarcodePayload.candidates(for: code)
            XCTAssertEqual(
                candidates.count, Set(candidates).count,
                "\(code) produced a duplicate candidate"
            )
        }
    }

    func test_candidates_alwaysLeadsWithWhatWasScanned() {
        // The scanned form is the strongest signal we have; a retry is a
        // fallback, never a replacement.
        XCTAssertEqual(BarcodePayload.candidates(for: "036000291452").first, "036000291452")
    }

    func test_gtin13_rejectsInputThatIsNotFourteenDigits() {
        XCTAssertNil(BarcodePayload.gtin13(insideGTIN14: "5449000000996"))
        XCTAssertNil(BarcodePayload.gtin13(insideGTIN14: "1544900000099X"))
    }

    // MARK: - GS1 element strings

    func test_gs1_extractsTheGTINFromALeadingAI01() {
        // (01) followed by a 14-digit GTIN, then a (17) expiry.
        let payload = "010154490000009217250228"
        XCTAssertEqual(BarcodePayload.gs1GTIN(in: payload), "01544900000092")
    }

    func test_gs1_stripsASymbologyIdentifier() {
        XCTAssertEqual(
            BarcodePayload.gs1GTIN(in: "]C1010154490000009217250228"),
            "01544900000092"
        )
    }

    func test_gs1_findsTheGTINAfterAGroupSeparator() {
        let payload = "10BATCH42\u{1D}0101544900000092"
        XCTAssertEqual(BarcodePayload.gs1GTIN(in: payload), "01544900000092")
    }

    func test_gs1_ignoresASegmentWhoseCheckDigitFails() {
        // Without this, a batch number that happens to start "01" would
        // be looked up as if it were a product.
        XCTAssertNil(BarcodePayload.gs1GTIN(in: "010154490000009417250228"))
    }

    func test_gs1_doesNotMisreadPlainProductCodesBeginningWithZeroOne() {
        // AI 01 needs 14 digits behind it, and no ordinary 8–14 digit
        // code is long enough to supply them — this is what makes it
        // safe to try GS1 parsing first.
        XCTAssertNil(BarcodePayload.gs1GTIN(in: "012345678905"))
        XCTAssertNil(BarcodePayload.gs1GTIN(in: "0123456789012"))
        XCTAssertNil(BarcodePayload.gs1GTIN(in: "01234567890128"))
    }

    // MARK: - Classification

    func test_classify_readsAPlainEAN13AsAProductCode() {
        XCTAssertEqual(BarcodePayload.classify("5449000000996"), .gtin(["5449000000996"]))
    }

    func test_classify_toleratesSurroundingWhitespace() {
        XCTAssertEqual(BarcodePayload.classify("  5449000000996\n"), .gtin(["5449000000996"]))
    }

    func test_classify_readsAGS1PayloadAsItsProductCode() {
        guard case .gtin(let candidates) = BarcodePayload.classify("]C1010154490000009217250228") else {
            return XCTFail("GS1 payload should classify as a product code")
        }
        XCTAssertEqual(candidates.first, "01544900000092")
    }

    func test_classify_readsAQRCodeAsALink() {
        guard case .link(let url) = BarcodePayload.classify("https://example.com/promo") else {
            return XCTFail("an https payload should classify as a link")
        }
        XCTAssertEqual(url.host, "example.com")
    }

    func test_classify_treatsANonWebSchemeAsText() {
        // Only http(s) becomes a link — a mailto: or a custom scheme has
        // nothing to say about a product and shouldn't be described as
        // a web address.
        XCTAssertEqual(
            BarcodePayload.classify("mailto:hi@example.com"),
            .text("mailto:hi@example.com")
        )
    }

    func test_classify_readsAShippingLabelAsText() {
        XCTAssertEqual(BarcodePayload.classify("SSCC-00123456789"), .text("SSCC-00123456789"))
    }

    func test_classify_rejectsCodesShorterThanEAN8() {
        // Seven digits is not a product code in any GS1 symbology, so
        // it must not reach the lookup as one.
        XCTAssertEqual(BarcodePayload.classify("1234567"), .text("1234567"))
    }

    func test_classify_rejectsOverlongDigitStrings() {
        let long = String(repeating: "7", count: 15)
        XCTAssertEqual(BarcodePayload.classify(long), .text(long))
    }
}
