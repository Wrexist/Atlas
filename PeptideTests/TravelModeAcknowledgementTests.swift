import XCTest
@testable import Peptide

/// C236: the acknowledged travel zone is device-local, so two devices on
/// one account in different zones don't re-prompt each other.
final class TravelModeAcknowledgementTests: XCTestCase {

    private let suiteName = "TravelModeAcknowledgementTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_acknowledgedTimezone_syncedValueFromAnotherDevice_doesNotPrompt() throws {
        let home = try XCTUnwrap(TimeZone(identifier: "Europe/Stockholm"))
        defaults.set(home.identifier, forKey: TravelModeLogic.acknowledgedTimezoneKey)

        let acknowledged = TravelModeLogic.acknowledgedTimezone(seededFrom: "America/New_York", defaults: defaults)

        XCTAssertEqual(acknowledged, home.identifier)
        XCTAssertNil(TimezoneChangeDetector.detect(previousIdentifier: acknowledged, currentZone: home))
    }

    func test_acknowledgedTimezone_nothingRecorded_seedsFromSyncedValueOnce() {
        XCTAssertEqual(
            TravelModeLogic.acknowledgedTimezone(seededFrom: "Europe/Stockholm", defaults: defaults),
            "Europe/Stockholm"
        )
        XCTAssertEqual(
            TravelModeLogic.acknowledgedTimezone(seededFrom: "Asia/Tokyo", defaults: defaults),
            "Europe/Stockholm",
            "Later synced values must not overwrite this device's own acknowledgment"
        )
    }

    func test_acknowledgeTimezoneChange_recordsTheZoneOnThisDevice() {
        var profile = UserProfile.fresh
        TravelModeLogic.acknowledgeTimezoneChange(in: &profile, to: "Asia/Tokyo", defaults: defaults)
        XCTAssertEqual(TravelModeLogic.acknowledgedTimezone(seededFrom: nil, defaults: defaults), "Asia/Tokyo")
    }
}
