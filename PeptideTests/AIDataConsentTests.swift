import XCTest
@testable import Peptide

/// `AIDataConsent` gates what leaves the device. The diet coach's derived
/// nutrition summary must not ride on consent given to the research chat.
final class AIDataConsentTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AIDataConsent.revoke()
    }

    override func tearDown() {
        AIDataConsent.revoke()
        super.tearDown()
    }

    func test_generalConsentOnly_blocksCoachSummary() {
        AIDataConsent.grant()

        XCTAssertTrue(AIDataConsent.allowsSend(includesCoachSummary: false))
        XCTAssertFalse(AIDataConsent.allowsSend(includesCoachSummary: true))
        XCTAssertFalse(AIDataConsent.isCoachSummaryGranted)
    }

    func test_coachSummaryConsent_allowsBothKindsOfSend() {
        AIDataConsent.grantCoachSummary()

        XCTAssertTrue(AIDataConsent.allowsSend(includesCoachSummary: true))
        XCTAssertTrue(AIDataConsent.allowsSend(includesCoachSummary: false))
    }

    func test_noConsent_blocksEverySend() {
        XCTAssertFalse(AIDataConsent.allowsSend(includesCoachSummary: false))
        XCTAssertFalse(AIDataConsent.allowsSend(includesCoachSummary: true))
    }

    func test_revoke_clearsCoachSummaryConsent() {
        AIDataConsent.grantCoachSummary()
        AIDataConsent.revoke()

        XCTAssertFalse(AIDataConsent.isGranted)
        XCTAssertFalse(AIDataConsent.isCoachSummaryGranted)
    }
}
