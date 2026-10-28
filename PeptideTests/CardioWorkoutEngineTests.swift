import HealthKit
import UIKit
import XCTest
@testable import Peptide

final class CardioWorkoutEngineTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        c.firstWeekday = 2
        return c
    }()

    private func october(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour)) ?? Date()
    }

    private func workout(
        start: Date,
        minutes: Double,
        meters: Double? = nil,
        kcal: Double? = nil,
        source: String = "Strava"
    ) -> ImportedCardioWorkout {
        ImportedCardioWorkout(
            id: UUID(),
            activity: .running,
            start: start,
            duration: minutes * 60,
            distanceMeters: meters,
            activeKilocalories: kcal,
            averageHeartRate: nil,
            sourceName: source
        )
    }

    // MARK: - Activity mapping

    func test_commonCardioTypes_mapToTheirOwnActivity() {
        XCTAssertEqual(CardioActivity(.running), .running)
        XCTAssertEqual(CardioActivity(.walking), .walking)
        XCTAssertEqual(CardioActivity(.cycling), .cycling)
        XCTAssertEqual(CardioActivity(.swimming), .swimming)
        XCTAssertEqual(CardioActivity(.highIntensityIntervalTraining), .hiit)
    }

    func test_relatedTypes_shareOneActivity() {
        XCTAssertEqual(CardioActivity(.handCycling), .cycling)
        XCTAssertEqual(CardioActivity(.stairClimbing), .stairs)
        XCTAssertEqual(CardioActivity(.stepTraining), .stairs)
        XCTAssertEqual(CardioActivity(.functionalStrengthTraining), .strength)
        XCTAssertEqual(CardioActivity(.pickleball), .racketSports)
        XCTAssertEqual(CardioActivity(.rugby), .teamSports)
    }

    func test_unlistedType_mapsToOther() {
        XCTAssertEqual(CardioActivity(.archery), .other)
        XCTAssertEqual(CardioActivity(.fishing), .other)
    }

    func test_everyActivity_hasANameAndAnExistingSymbol() {
        for activity in CardioActivity.allCases {
            XCTAssertFalse(activity.name.isEmpty, "\(activity) has no name")
            XCTAssertNotNil(UIImage(systemName: activity.symbol), "\(activity) symbol \(activity.symbol) doesn't exist")
        }
    }

    func test_activityNames_areDistinct() {
        let names = CardioActivity.allCases.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
    }

    // MARK: - Distance

    func test_metricDistance_isInKilometres() throws {
        let distance = try XCTUnwrap(CardioWorkoutEngine.distance(meters: 5_230, unit: .metric))
        XCTAssertEqual(distance.unit, .kilometers)
        XCTAssertEqual(distance.value, 5.23, accuracy: 0.0001)
    }

    func test_imperialDistance_isInMiles() throws {
        let distance = try XCTUnwrap(CardioWorkoutEngine.distance(meters: 1_609.344, unit: .imperial))
        XCTAssertEqual(distance.unit, .miles)
        XCTAssertEqual(distance.value, 1, accuracy: 0.0001)
    }

    func test_missingOrZeroDistance_hasNoLabel() {
        XCTAssertNil(CardioWorkoutEngine.distanceLabel(meters: nil, unit: .metric))
        XCTAssertNil(CardioWorkoutEngine.distanceLabel(meters: 0, unit: .metric))
    }

    func test_shortDistanceLabel_showsTwoDecimalsInTheLocale() throws {
        let label = try XCTUnwrap(
            CardioWorkoutEngine.distanceLabel(meters: 5_230, unit: .metric, locale: Locale(identifier: "sv_SE"))
        )
        XCTAssertTrue(label.contains("5,23"), label)
        XCTAssertTrue(label.contains("km"), label)
    }

    func test_longDistanceLabel_showsOneDecimal() throws {
        let label = try XCTUnwrap(
            CardioWorkoutEngine.distanceLabel(meters: 42_195, unit: .metric, locale: Locale(identifier: "en_US"))
        )
        XCTAssertTrue(label.contains("42.2"), label)
        XCTAssertFalse(label.contains("42.20"), label)
    }

    // MARK: - Weekly minutes

    func test_minutesThisWeek_countsOnlyWorkoutsStartedThisWeek() {
        // Wednesday 28 Oct 2026; the week runs Monday 26 Oct – Sunday 1 Nov.
        let now = october(28, 12)
        let workouts = [
            workout(start: october(26, 7), minutes: 30),
            workout(start: october(28, 6), minutes: 45.4),
            workout(start: october(25, 18), minutes: 60),
        ]

        XCTAssertEqual(CardioWorkoutEngine.minutesThisWeek(workouts, now: now, calendar: calendar), 75)
    }

    func test_minutesThisWeek_withNoWorkouts_isZero() {
        XCTAssertEqual(CardioWorkoutEngine.minutesThisWeek([], now: october(28, 12), calendar: calendar), 0)
    }

    // MARK: - Labels

    func test_summary_leavesOutWhatWasNotRecorded() {
        let bare = workout(start: october(28, 6), minutes: 30, source: "Apple Watch")
        XCTAssertEqual(CardioWorkoutEngine.summary(of: bare, unit: .metric), "Apple Watch")
    }

    func test_summary_joinsDistanceEnergyAndSource() {
        let full = workout(start: october(28, 6), minutes: 30, meters: 5_000, kcal: 312.6, source: "Strava")
        let summary = CardioWorkoutEngine.summary(of: full, unit: .metric, locale: Locale(identifier: "en_US"))
        let parts = summary.components(separatedBy: " · ")

        XCTAssertEqual(parts.count, 3, summary)
        XCTAssertTrue(parts[0].contains("5.00"), summary)
        XCTAssertTrue(parts[1].contains("313"), summary)
        XCTAssertEqual(parts[2], "Strava")
    }

    func test_energyAndHeartRate_withoutValues_haveNoLabel() {
        XCTAssertNil(CardioWorkoutEngine.energyLabel(nil))
        XCTAssertNil(CardioWorkoutEngine.energyLabel(0.4))
        XCTAssertNil(CardioWorkoutEngine.heartRateLabel(nil))
        XCTAssertNil(CardioWorkoutEngine.heartRateLabel(0))
    }
}
