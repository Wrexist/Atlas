import XCTest
import CoreGraphics
import ImageIO
@testable import Peptide

final class ReconstitutionEngineTests: XCTestCase {

    private let accuracy = 1e-9

    // MARK: - Unit conversions

    func test_milligramsFromMicrograms_dividesByThousand() {
        XCTAssertEqual(ReconstitutionEngine.milligrams(fromMicrograms: 250), 0.25, accuracy: accuracy)
        XCTAssertEqual(ReconstitutionEngine.milligrams(fromMicrograms: 1), 0.001, accuracy: accuracy)
    }

    func test_microgramsFromMilligrams_multipliesByThousand() {
        XCTAssertEqual(ReconstitutionEngine.micrograms(fromMilligrams: 5), 5000, accuracy: accuracy)
        XCTAssertEqual(ReconstitutionEngine.micrograms(fromMilligrams: 0.5), 500, accuracy: accuracy)
    }

    func test_mgMcgConversions_roundTrip() {
        let original = 1234.5
        let roundTripped = ReconstitutionEngine.micrograms(
            fromMilligrams: ReconstitutionEngine.milligrams(fromMicrograms: original)
        )
        XCTAssertEqual(roundTripped, original, accuracy: accuracy)
    }

    // MARK: - Concentration

    func test_concentration_fiveMgInTwoMl_isTwoPointFive() {
        XCTAssertEqual(ReconstitutionEngine.concentrationMgPerMl(vialMg: 5, waterMl: 2) ?? -1, 2.5, accuracy: accuracy)
    }

    func test_concentration_zeroWater_returnsNil() {
        XCTAssertNil(ReconstitutionEngine.concentrationMgPerMl(vialMg: 5, waterMl: 0))
    }

    func test_concentration_zeroVial_returnsNil() {
        XCTAssertNil(ReconstitutionEngine.concentrationMgPerMl(vialMg: 0, waterMl: 2))
    }

    func test_concentration_negativeInputs_returnNil() {
        XCTAssertNil(ReconstitutionEngine.concentrationMgPerMl(vialMg: -5, waterMl: 2))
        XCTAssertNil(ReconstitutionEngine.concentrationMgPerMl(vialMg: 5, waterMl: -2))
    }

    func test_concentration_nonFiniteInputs_returnNil() {
        XCTAssertNil(ReconstitutionEngine.concentrationMgPerMl(vialMg: .infinity, waterMl: 2))
        XCTAssertNil(ReconstitutionEngine.concentrationMgPerMl(vialMg: 5, waterMl: .nan))
    }

    // MARK: - Syringe units

    func test_syringeUnits_twoFiftyMcgAtTwoPointFiveMgPerMl_isTen() {
        // 0.25 mg ÷ 2.5 mg/mL = 0.1 mL = 10 units.
        let units = ReconstitutionEngine.syringeUnits(amountMcg: 250, vialMg: 5, waterMl: 2)
        XCTAssertEqual(units ?? -1, 10, accuracy: accuracy)
    }

    func test_syringeUnits_wholeVial_isFullWaterVolume() {
        // The entire 5 mg sits in 2 mL = 200 units.
        let units = ReconstitutionEngine.syringeUnits(amountMcg: 5000, vialMg: 5, waterMl: 2)
        XCTAssertEqual(units ?? -1, 200, accuracy: accuracy)
    }

    func test_syringeUnits_zeroWater_returnsNil() {
        XCTAssertNil(ReconstitutionEngine.syringeUnits(amountMcg: 250, vialMg: 5, waterMl: 0))
    }

    func test_syringeUnits_zeroVial_returnsNil() {
        XCTAssertNil(ReconstitutionEngine.syringeUnits(amountMcg: 250, vialMg: 0, waterMl: 2))
    }

    func test_syringeUnits_zeroAmount_returnsNil() {
        XCTAssertNil(ReconstitutionEngine.syringeUnits(amountMcg: 0, vialMg: 5, waterMl: 2))
    }

    func test_syringeUnits_negativeAmount_returnsNil() {
        XCTAssertNil(ReconstitutionEngine.syringeUnits(amountMcg: -250, vialMg: 5, waterMl: 2))
    }

    func test_syringeUnits_fractionalResult_isKeptPrecise() {
        // 0.1 mg ÷ (3 mg / 1 mL) = 0.0333… mL = 3.333… units.
        let units = ReconstitutionEngine.syringeUnits(amountMcg: 100, vialMg: 3, waterMl: 1)
        XCTAssertEqual(units ?? -1, 10.0 / 3.0, accuracy: accuracy)
    }

    func test_syringeUnits_largeValues_stayFinite() {
        let units = ReconstitutionEngine.syringeUnits(amountMcg: 1e9, vialMg: 0.5, waterMl: 10)
        // 1e6 mg ÷ 0.05 mg/mL = 2e7 mL = 2e9 units.
        XCTAssertEqual(units ?? -1, 2e9, accuracy: 1)
    }

    func test_syringeUnits_overflowingValues_returnNil() {
        XCTAssertNil(ReconstitutionEngine.syringeUnits(amountMcg: .greatestFiniteMagnitude, vialMg: 1e-300, waterMl: 1))
    }

    // MARK: - Rounding

    func test_roundedUnits_roundsHalfAwayFromZero() {
        XCTAssertEqual(ReconstitutionEngine.roundedUnits(12.5), 13)
        XCTAssertEqual(ReconstitutionEngine.roundedUnits(12.49), 12)
        XCTAssertEqual(ReconstitutionEngine.roundedUnits(12.6), 13)
    }

    func test_roundedUnits_nonFiniteOrHuge_returnsNil() {
        XCTAssertNil(ReconstitutionEngine.roundedUnits(.infinity))
        XCTAssertNil(ReconstitutionEngine.roundedUnits(.nan))
        XCTAssertNil(ReconstitutionEngine.roundedUnits(1e300))
    }

    func test_hasFractionalUnits_wholeNumber_isFalse() {
        XCTAssertFalse(ReconstitutionEngine.hasFractionalUnits(10))
    }

    func test_hasFractionalUnits_withinTolerance_isFalse() {
        XCTAssertFalse(ReconstitutionEngine.hasFractionalUnits(10.04))
    }

    func test_hasFractionalUnits_beyondTolerance_isTrue() {
        XCTAssertTrue(ReconstitutionEngine.hasFractionalUnits(12.6))
        XCTAssertTrue(ReconstitutionEngine.hasFractionalUnits(10.0 / 3.0))
    }

    func test_hasFractionalUnits_nonFinite_isFalse() {
        XCTAssertFalse(ReconstitutionEngine.hasFractionalUnits(.nan))
    }

    // MARK: - Amounts per vial

    func test_amountsPerVial_evenDivision_returnsExactCount() {
        XCTAssertEqual(ReconstitutionEngine.amountsPerVial(amountMcg: 250, vialMg: 5), 20)
    }

    func test_amountsPerVial_partialRemainder_roundsDown() {
        XCTAssertEqual(ReconstitutionEngine.amountsPerVial(amountMcg: 300, vialMg: 5), 16)
    }

    func test_amountsPerVial_amountLargerThanVial_isZero() {
        XCTAssertEqual(ReconstitutionEngine.amountsPerVial(amountMcg: 10_000, vialMg: 5), 0)
    }

    func test_amountsPerVial_zeroAmount_returnsNil() {
        XCTAssertNil(ReconstitutionEngine.amountsPerVial(amountMcg: 0, vialMg: 5))
    }

    func test_amountsPerVial_zeroVial_returnsNil() {
        XCTAssertNil(ReconstitutionEngine.amountsPerVial(amountMcg: 250, vialMg: 0))
    }

    func test_amountsPerVial_uncountablyLarge_returnsNil() {
        XCTAssertNil(ReconstitutionEngine.amountsPerVial(amountMcg: 1e-300, vialMg: 50))
    }

    // MARK: - Parsing

    func test_parseAmount_empty_returnsNil() {
        XCTAssertNil(ReconstitutionEngine.parseAmount(""))
        XCTAssertNil(ReconstitutionEngine.parseAmount("   "))
    }

    func test_parseAmount_plainNumber_parses() {
        XCTAssertEqual(ReconstitutionEngine.parseAmount("250"), 250)
        XCTAssertEqual(ReconstitutionEngine.parseAmount(" 12.5 "), 12.5)
    }

    func test_parseAmount_commaDecimal_parses() {
        XCTAssertEqual(ReconstitutionEngine.parseAmount("12,5"), 12.5)
    }

    func test_parseAmount_zeroOrNegative_returnsNil() {
        XCTAssertNil(ReconstitutionEngine.parseAmount("0"))
        XCTAssertNil(ReconstitutionEngine.parseAmount("-5"))
    }

    func test_parseAmount_interiorJunk_returnsNil() {
        XCTAssertNil(ReconstitutionEngine.parseAmount("2 50"))
        XCTAssertNil(ReconstitutionEngine.parseAmount("250mcg"))
    }

    func test_parseAmount_nonFiniteLiteral_returnsNil() {
        XCTAssertNil(ReconstitutionEngine.parseAmount("inf"))
        XCTAssertNil(ReconstitutionEngine.parseAmount("nan"))
    }
}

final class PhotoCaptureDateTests: XCTestCase {

    private let utc = TimeZone(secondsFromGMT: 0)!

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        ))!
    }

    /// A 4×4 JPEG carrying the given EXIF dictionary, written by ImageIO.
    private func jpeg(exif: [CFString: Any]?) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try XCTUnwrap(context.makeImage())

        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(output as CFMutableData, "public.jpeg" as CFString, 1, nil)
        )
        var properties: [CFString: Any] = [:]
        if let exif { properties[kCGImagePropertyExifDictionary] = exif }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    // MARK: - Image data

    func test_captureDate_jpegWithOriginalAndOffset_usesOffset() throws {
        let data = try jpeg(exif: [
            kCGImagePropertyExifDateTimeOriginal: "2026:03:14 19:30:00",
            kCGImagePropertyExifOffsetTimeOriginal: "+02:00",
        ])
        XCTAssertEqual(
            PhotoCaptureDate.captureDate(fromImageData: data, fallbackTimeZone: utc),
            utcDate(2026, 3, 14, 17, 30, 0)
        )
    }

    func test_captureDate_jpegWithoutOffset_usesFallbackTimeZone() throws {
        let data = try jpeg(exif: [kCGImagePropertyExifDateTimeOriginal: "2026:03:14 19:30:00"])
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        // 14 March 2026 is after the US DST switch: EDT, UTC-4.
        XCTAssertEqual(
            PhotoCaptureDate.captureDate(fromImageData: data, fallbackTimeZone: newYork),
            utcDate(2026, 3, 14, 23, 30, 0)
        )
    }

    func test_captureDate_jpegWithoutExif_returnsNil() throws {
        let data = try jpeg(exif: nil)
        XCTAssertNil(PhotoCaptureDate.captureDate(fromImageData: data, fallbackTimeZone: utc))
    }

    func test_captureDate_notAnImage_returnsNil() {
        XCTAssertNil(PhotoCaptureDate.captureDate(fromImageData: Data("not an image".utf8), fallbackTimeZone: utc))
    }

    // MARK: - Date string

    func test_dateFromExif_negativeOffset_shiftsForward() {
        XCTAssertEqual(
            PhotoCaptureDate.date(fromExifDateTime: "2025:12:31 22:15:05", offset: "-05:00", fallbackTimeZone: utc),
            utcDate(2026, 1, 1, 3, 15, 5)
        )
    }

    func test_dateFromExif_trailingNul_isTolerated() {
        XCTAssertEqual(
            PhotoCaptureDate.date(fromExifDateTime: "2026:03:14 19:30:00\0", offset: nil, fallbackTimeZone: utc),
            utcDate(2026, 3, 14, 19, 30, 0)
        )
    }

    func test_dateFromExif_zeroPlaceholder_returnsNil() {
        XCTAssertNil(PhotoCaptureDate.date(fromExifDateTime: "0000:00:00 00:00:00", offset: nil, fallbackTimeZone: utc))
    }

    func test_dateFromExif_isoFormat_returnsNil() {
        XCTAssertNil(PhotoCaptureDate.date(fromExifDateTime: "2026-03-14T19:30:00", offset: nil, fallbackTimeZone: utc))
    }

    func test_dateFromExif_malformedOffset_fallsBackToFallbackZone() {
        XCTAssertEqual(
            PhotoCaptureDate.date(fromExifDateTime: "2026:03:14 19:30:00", offset: "garbage", fallbackTimeZone: utc),
            utcDate(2026, 3, 14, 19, 30, 0)
        )
    }

    // MARK: - Offset

    func test_timeZoneFromExifOffset_halfHourOffset_parses() {
        XCTAssertEqual(PhotoCaptureDate.timeZone(fromExifOffset: "+05:30")?.secondsFromGMT(), 19_800)
    }

    func test_timeZoneFromExifOffset_negativeOffset_parses() {
        XCTAssertEqual(PhotoCaptureDate.timeZone(fromExifOffset: "-08:00")?.secondsFromGMT(), -28_800)
    }

    func test_timeZoneFromExifOffset_missingSignOrOutOfRange_returnsNil() {
        XCTAssertNil(PhotoCaptureDate.timeZone(fromExifOffset: "05:30"))
        XCTAssertNil(PhotoCaptureDate.timeZone(fromExifOffset: "+15:00"))
        XCTAssertNil(PhotoCaptureDate.timeZone(fromExifOffset: "+05:60"))
        XCTAssertNil(PhotoCaptureDate.timeZone(fromExifOffset: "+5:30"))
    }
}
