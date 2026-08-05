import XCTest
@testable import Peptide

final class BarcodeScanHistoryTests: XCTestCase {

    private var defaults: UserDefaults!
    private var history: BarcodeScanHistory!
    private let suiteName = "com.peptidesai.app.tests.history.\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        history = BarcodeScanHistory(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        history = nil
        super.tearDown()
    }

    // MARK: - lastPortion

    func test_lastPortion_returnsNil_forUnknownBarcode() async {
        let result = await history.lastPortion(for: "0000000000001")
        XCTAssertNil(result)
    }

    func test_recordLog_thenLastPortion_returnsSamePortion() async {
        await history.recordLog(barcode: "5449000000996", portion: .servings(2))
        let result = await history.lastPortion(for: "5449000000996")
        XCTAssertEqual(result, .servings(2))
    }

    func test_recordLog_overwritesPreviousPortion() async {
        await history.recordLog(barcode: "5449000000996", portion: .servings(1))
        await history.recordLog(barcode: "5449000000996", portion: .grams(250))
        let result = await history.lastPortion(for: "5449000000996")
        XCTAssertEqual(result, .grams(250))
    }

    func test_recordLog_preservesWholePackageMode() async {
        await history.recordLog(barcode: "5449000000996", portion: .wholePackage)
        let result = await history.lastPortion(for: "5449000000996")
        XCTAssertEqual(result, .wholePackage)
    }

    // MARK: - score

    func test_score_returnsZero_forUnknownBarcode() async {
        let result = await history.score(for: "0000000000001")
        XCTAssertEqual(result, 0)
    }

    func test_score_approximatesScanCount_forFreshlyRecordedBarcode() async {
        let now = Date()
        await history.recordLog(barcode: "1111111111111", portion: .grams(100), at: now)
        await history.recordLog(barcode: "1111111111111", portion: .grams(100), at: now)
        await history.recordLog(barcode: "1111111111111", portion: .grams(100), at: now)
        // Same-instant scan: age = 0, decay = 1.0 → score == scanCount.
        let result = await history.score(for: "1111111111111", now: now)
        XCTAssertEqual(result, 3, accuracy: 0.001)
    }

    func test_score_decays_withAge() async {
        let twoWeeksAgo = Date(timeIntervalSinceNow: -14 * 24 * 60 * 60)
        await history.recordLog(barcode: "1111111111111", portion: .grams(100), at: twoWeeksAgo)
        await history.recordLog(barcode: "1111111111111", portion: .grams(100), at: twoWeeksAgo)
        let result = await history.score(for: "1111111111111")
        // 2 scans, exactly one half-life ago → score ≈ 2 * 0.5 = 1.0
        XCTAssertEqual(result, 1.0, accuracy: 0.05)
    }

    func test_score_dailyHabit_beatsOneOff() async {
        let now = Date()
        let oneWeekAgo = Date(timeIntervalSince1970: now.timeIntervalSince1970 - 7 * 24 * 60 * 60)

        // A: daily product scanned 5 times over the past week
        for _ in 0..<5 {
            await history.recordLog(barcode: "DAILY", portion: .servings(1), at: oneWeekAgo)
        }

        // B: one-off scanned today
        await history.recordLog(barcode: "ONEOFF", portion: .grams(100), at: now)

        let dailyScore = await history.score(for: "DAILY", now: now)
        let oneOffScore = await history.score(for: "ONEOFF", now: now)
        XCTAssertGreaterThan(
            dailyScore, oneOffScore,
            "5 weekly scans should outrank 1 same-day scan after recency decay"
        )
    }

    func test_scores_bulkRead_matchesIndividualReads() async throws {
        let now = Date()
        await history.recordLog(barcode: "A", portion: .grams(100), at: now)
        await history.recordLog(barcode: "A", portion: .grams(100), at: now)
        await history.recordLog(barcode: "B", portion: .grams(100), at: now)

        let bulk = await history.scores(for: ["A", "B", "MISSING"], now: now)
        XCTAssertEqual(try XCTUnwrap(bulk["A"]), 2, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(bulk["B"]), 1, accuracy: 0.001)
        XCTAssertEqual(bulk["MISSING"] ?? -1, 0, accuracy: 0.001)
    }

    // MARK: - undoLog

    func test_undoLog_decrementsScanCount() async {
        await history.recordLog(barcode: "5449000000996", portion: .servings(1))
        await history.recordLog(barcode: "5449000000996", portion: .servings(2))
        await history.undoLog(barcode: "5449000000996")
        let score = await history.score(for: "5449000000996")
        XCTAssertEqual(score, 1, accuracy: 0.05)
    }

    func test_undoLog_removesEntry_whenCountHitsZero() async {
        await history.recordLog(barcode: "5449000000996", portion: .servings(1))
        await history.undoLog(barcode: "5449000000996")
        let portion = await history.lastPortion(for: "5449000000996")
        let score = await history.score(for: "5449000000996")
        XCTAssertNil(portion, "Undoing the only scan should leave no trace")
        XCTAssertEqual(score, 0)
    }

    func test_undoLog_preservesLastPortion_whenStillReferenced() async {
        await history.recordLog(barcode: "5449000000996", portion: .servings(1))
        await history.recordLog(barcode: "5449000000996", portion: .grams(330))
        await history.undoLog(barcode: "5449000000996")
        // scanCount went 1 → 2 → 1; lastPortion stays at the most
        // recent recordLog value.
        let portion = await history.lastPortion(for: "5449000000996")
        XCTAssertEqual(portion, .grams(330))
    }

    func test_undoLog_isNoOp_forUnknownBarcode() async {
        await history.undoLog(barcode: "DEFINITELY_NEVER_RECORDED")
        let score = await history.score(for: "DEFINITELY_NEVER_RECORDED")
        XCTAssertEqual(score, 0)
    }

    // MARK: - clear

    func test_clear_removesAllRecords() async {
        await history.recordLog(barcode: "A", portion: .grams(100))
        await history.recordLog(barcode: "B", portion: .grams(200))
        await history.clear()
        let a = await history.lastPortion(for: "A")
        let b = await history.lastPortion(for: "B")
        XCTAssertNil(a)
        XCTAssertNil(b)
    }

    // MARK: - PortionRecord round-trip

    func test_portionRecord_roundTrips_grams() {
        let original: ScannedProduct.Portion = .grams(330)
        let restored = BarcodeScanHistory.PortionRecord(original).toPortion()
        XCTAssertEqual(restored, original)
    }

    func test_portionRecord_roundTrips_servings() {
        let original: ScannedProduct.Portion = .servings(1.5)
        let restored = BarcodeScanHistory.PortionRecord(original).toPortion()
        XCTAssertEqual(restored, original)
    }

    func test_portionRecord_roundTrips_wholePackage() {
        let original: ScannedProduct.Portion = .wholePackage
        let restored = BarcodeScanHistory.PortionRecord(original).toPortion()
        XCTAssertEqual(restored, original)
    }
}
