import XCTest
@testable import Peptide

@MainActor
final class ProtocolReminderSwitchTests: XCTestCase {

    private var calls: [String] = []

    private func effects(authorized: Bool) -> ProtocolReminderSwitch.Effects {
        ProtocolReminderSwitch.Effects(
            requestAuthorization: { [unowned self] in
                calls.append("authorize")
                return authorized
            },
            schedule: { [unowned self] in calls.append("schedule") },
            cancel: { [unowned self] in calls.append("cancel") }
        )
    }

    override func setUp() {
        super.setUp()
        calls = []
    }

    func test_turnOnWithPermission_asksThenSchedules() async {
        let outcome = await ProtocolReminderSwitch.apply(enabled: true, effects: effects(authorized: true))

        XCTAssertEqual(outcome, .scheduled)
        XCTAssertEqual(calls, ["authorize", "schedule"])
    }

    func test_turnOnWithPermissionDenied_schedulesNothing() async {
        let outcome = await ProtocolReminderSwitch.apply(enabled: true, effects: effects(authorized: false))

        XCTAssertEqual(outcome, .denied)
        XCTAssertEqual(calls, ["authorize"])
    }

    func test_turnOff_cancelsWithoutAskingForPermission() async {
        let outcome = await ProtocolReminderSwitch.apply(enabled: false, effects: effects(authorized: true))

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(calls, ["cancel"])
    }
}
