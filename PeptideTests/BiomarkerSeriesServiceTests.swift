import XCTest
@testable import Peptide

/// HealthKit-bound paths in BiomarkerSeriesService can't be mocked
/// without a fake HKHealthStore. The math that decides whether a
/// number is "increasing" / "holding" / "decreasing" — where bugs
/// would actually hide — is pure and tested here.
@MainActor
final class BiomarkerSeriesServiceTests: XCTestCase {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: - median

    func test_median_emptySeries_returnsNil() {
        XCTAssertNil(BiomarkerSeriesService.median([]))
    }

    func test_median_oddCount_returnsMiddleValue() {
        XCTAssertEqual(BiomarkerSeriesService.median([10, 20, 30, 40, 50]), 30)
    }

    func test_median_evenCount_returnsMeanOfMiddleTwo() {
        XCTAssertEqual(BiomarkerSeriesService.median([10, 20, 30, 40]), 25)
    }

    /// Median (not mean) means a single outlier doesn't shift the
    /// reported center. Important because users sometimes weigh
    /// themselves after a heavy meal and a mean-based trend would
    /// flip the direction.
    func test_median_singleOutlier_doesNotShiftCenter() {
        let withOutlier = BiomarkerSeriesService.median([70, 71, 72, 73, 150])
        XCTAssertEqual(withOutlier, 72)
    }

    // MARK: - inferTrend

    /// Below the sample-count floor → insufficient. The view's
    /// "no trend yet" copy lands instead of a misleading direction.
    func test_inferTrend_belowMinSamples_returnsInsufficient() {
        let result = BiomarkerSeriesService.inferTrend(samples: [70, 71, 72])
        XCTAssertEqual(result, .insufficient)
    }

    func test_inferTrend_clearUpward_returnsUp() {
        let samples: [Double] = [70, 70.2, 70.3, 70.5, 71.0, 71.5, 71.8, 72.0]
        XCTAssertEqual(BiomarkerSeriesService.inferTrend(samples: samples), .up)
    }

    func test_inferTrend_clearDownward_returnsDown() {
        let samples: [Double] = [72.0, 71.8, 71.5, 71.0, 70.5, 70.3, 70.2, 70.0]
        XCTAssertEqual(BiomarkerSeriesService.inferTrend(samples: samples), .down)
    }

    /// Small fluctuation below the flat threshold reads as flat
    /// — the user shouldn't see "Decreasing" for a 0.3 kg dip
    /// on a 70 kg body.
    func test_inferTrend_smallFluctuation_returnsFlat() {
        let samples: [Double] = [70.0, 70.1, 70.0, 69.9, 70.0, 70.1, 70.0, 69.95]
        XCTAssertEqual(BiomarkerSeriesService.inferTrend(samples: samples), .flat)
    }

    // MARK: - formatValue

    /// The contract is one decimal place, not a rounding mode.
    ///
    /// This asserted `72.05 → "72.1"`, which `%.1f` does not promise: 72.05 is
    /// not representable in binary and the nearest Double is a hair *below*
    /// it, so it formats as "72.0". The test was pinning the C library's
    /// half-even behaviour on a non-representable boundary value rather than
    /// anything the app decided. Both sides of the boundary are unambiguous.
    func test_formatValue_weightOneDecimal() {
        XCTAssertEqual(BiomarkerSeriesService.formatValue(72.06, for: .weight), "72.1")
        XCTAssertEqual(BiomarkerSeriesService.formatValue(72.04, for: .weight), "72.0")
        XCTAssertEqual(BiomarkerSeriesService.formatValue(72.0, for: .weight), "72.0")
    }

    func test_formatValue_hrvNoDecimal() {
        XCTAssertEqual(BiomarkerSeriesService.formatValue(58.7, for: .hrvBaseline), "59")
    }

    func test_formatValue_sleepOneDecimal() {
        XCTAssertEqual(BiomarkerSeriesService.formatValue(7.83, for: .sleepBaseline), "7.8")
    }

    // MARK: - changeText

    /// Weight uses "Increasing / Holding / Decreasing"; HRV uses
    /// "Trending up / Steady / Trending down". The vocabulary
    /// shift is the polish difference that makes the screen feel
    /// premium rather than mechanical.
    func test_changeText_weightUp() {
        let text = BiomarkerSeriesService.changeText(for: .weight, trend: .up, latest: 72.0)
        XCTAssertEqual(text, "Increasing · 72.0 kg")
    }

    func test_changeText_hrvFlat() {
        let text = BiomarkerSeriesService.changeText(for: .hrvBaseline, trend: .flat, latest: 58)
        XCTAssertEqual(text, "Steady · 58 ms")
    }

    func test_changeText_rhrDown() {
        let text = BiomarkerSeriesService.changeText(for: .rhrBaseline, trend: .down, latest: 53)
        XCTAssertEqual(text, "Lower · 53 bpm")
    }

    func test_changeText_sleepUp() {
        let text = BiomarkerSeriesService.changeText(for: .sleepBaseline, trend: .up, latest: 7.5)
        XCTAssertEqual(text, "More sleep · 7.5 h")
    }

    // MARK: - weightSnapshot

    func test_weightSnapshot_empty_returnsEmptySnapshot() {
        let snapshot = BiomarkerSeriesService.weightSnapshot(weightHistory: [])
        XCTAssertNil(snapshot.latest)
        XCTAssertEqual(snapshot.trend, .insufficient)
        XCTAssertTrue(snapshot.sparkline.isEmpty)
    }

    func test_weightSnapshot_picksLatestSample() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let history = (0..<8).map { i in
            WeightEntry(
                date: base.addingTimeInterval(TimeInterval(i * 86_400)),
                kg: 70.0 + Double(i) * 0.3
            )
        }
        let snapshot = BiomarkerSeriesService.weightSnapshot(
            weightHistory: history,
            now: base.addingTimeInterval(7 * 86_400),
            calendar: utc
        )
        XCTAssertEqual(snapshot.latest ?? .nan, 72.1, accuracy: 0.01)
        XCTAssertEqual(snapshot.trend, .up)
        XCTAssertEqual(snapshot.sparkline.count, 8)
        XCTAssertTrue(snapshot.changeText.contains("Increasing"))
    }

    /// Out-of-order history gets sorted before the snapshot
    /// reads the "latest" sample — guards against UserProfile
    /// preserving insertion order that doesn't match
    /// chronology.
    func test_weightSnapshot_outOfOrderHistory_stillUsesMostRecentDate() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let history = [
            WeightEntry(date: base.addingTimeInterval(3 * 86_400), kg: 71.0),
            WeightEntry(date: base,                                  kg: 72.0),
            WeightEntry(date: base.addingTimeInterval(7 * 86_400), kg: 73.0),
            WeightEntry(date: base.addingTimeInterval(5 * 86_400), kg: 72.5),
        ]
        let snapshot = BiomarkerSeriesService.weightSnapshot(
            weightHistory: history,
            now: base.addingTimeInterval(7 * 86_400),
            calendar: utc
        )
        XCTAssertEqual(snapshot.latest, 73.0)
    }

    func test_weightSnapshot_onlyStaleWeighIns_returnsEmpty() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let history = (0..<8).map { i in
            WeightEntry(date: base.addingTimeInterval(TimeInterval(i * 86_400)), kg: 82.0)
        }
        let snapshot = BiomarkerSeriesService.weightSnapshot(
            weightHistory: history,
            now: base.addingTimeInterval(120 * 86_400),
            calendar: utc
        )
        XCTAssertNil(snapshot.latest)
        XCTAssertEqual(snapshot.trend, .insufficient)
    }

    func test_weightSnapshot_severalWeighInsOneDay_keepsLatestOnly() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let history = [
            WeightEntry(date: base, kg: 70.0),
            WeightEntry(date: base.addingTimeInterval(3_600), kg: 71.0),
            WeightEntry(date: base.addingTimeInterval(86_400), kg: 71.5),
        ]
        let snapshot = BiomarkerSeriesService.weightSnapshot(
            weightHistory: history,
            now: base.addingTimeInterval(86_400),
            calendar: utc
        )
        XCTAssertEqual(snapshot.samples.map(\.value), [71.0, 71.5])
    }

    // MARK: - Latest reading date

    func test_weightSnapshot_carriesLatestWeighInDate() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let latestDate = base.addingTimeInterval(2 * 86_400)
        let snapshot = BiomarkerSeriesService.weightSnapshot(
            weightHistory: [WeightEntry(date: base, kg: 70), WeightEntry(date: latestDate, kg: 71)],
            now: base.addingTimeInterval(9 * 86_400),
            calendar: utc
        )
        XCTAssertEqual(snapshot.latestDate, latestDate)
    }

    /// A single-sample series drops its sparkline, but the hero still
    /// needs to know when that one reading was taken.
    func test_seriesSnapshot_singleReading_keepsItsDate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = BiomarkerSeriesService.seriesSnapshot(.hrvBaseline, series: [(date: date, value: 55)])
        XCTAssertTrue(snapshot.samples.isEmpty)
        XCTAssertEqual(snapshot.latestDate, date)
    }

    func test_staleNote_recentReading_isNil() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = BiomarkerSeriesService.seriesSnapshot(
            .rhrBaseline, series: [(date: now.addingTimeInterval(-86_400), value: 58)]
        )
        XCTAssertNil(snapshot.staleNote(now: now, calendar: utc))
    }

    func test_staleNote_readingOlderThanThreshold_namesItsDay() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let old = now.addingTimeInterval(-Double(BiomarkerSnapshot.staleAfterDays + 1) * 86_400)
        let snapshot = BiomarkerSeriesService.seriesSnapshot(.rhrBaseline, series: [(date: old, value: 58)])
        XCTAssertNotNil(snapshot.staleNote(now: now, calendar: utc))
    }

    // MARK: - completedDays

    func test_completedDays_partialTodayBucket_isDropped() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let today = utc.startOfDay(for: now)
        let yesterday = today.addingTimeInterval(-86_400)
        let series = [(date: yesterday, value: 9_000.0), (date: today, value: 812.0)]
        let completed = BiomarkerSeriesService.completedDays(series, now: now, calendar: utc)
        XCTAssertEqual(completed.map(\.value), [9_000])
    }

    // MARK: - seriesSnapshot

    func test_seriesSnapshot_empty_returnsEmpty() {
        let snapshot = BiomarkerSeriesService.seriesSnapshot(.hrvBaseline, series: [])
        XCTAssertNil(snapshot.latest)
        XCTAssertEqual(snapshot.trend, .insufficient)
    }

    func test_seriesSnapshot_8DayUpwardHrv_returnsUpTrend() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let values: [Double] = [40, 42, 44, 46, 48, 50, 52, 55]
        let series = values.enumerated().map { (date: base.addingTimeInterval(Double($0.offset) * 86_400), value: $0.element) }
        let snapshot = BiomarkerSeriesService.seriesSnapshot(.hrvBaseline, series: series)
        XCTAssertEqual(snapshot.latest, 55)
        XCTAssertEqual(snapshot.trend, .up)
        XCTAssertTrue(snapshot.changeText.contains("Trending up"))
    }

    /// HealthKit drops empty days, so each sample must keep its own
    /// date rather than being placed by index.
    func test_seriesSnapshot_gappySeries_keepsRealDates() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let series = [
            (date: base, value: 50.0),
            (date: base.addingTimeInterval(5 * 86_400), value: 52.0),
        ]
        let snapshot = BiomarkerSeriesService.seriesSnapshot(.hrvBaseline, series: series)
        XCTAssertEqual(snapshot.samples.map(\.date), series.map(\.date))
    }
}
