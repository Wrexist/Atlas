import XCTest
@testable import Peptide

/// `AIDataConsent` gates what leaves the device. A derived summary — the
/// diet coach's or Ask Atlas's — must not ride on consent given to the
/// research chat, nor on the other summary's.
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

        XCTAssertTrue(AIDataConsent.allowsSend(attaching: nil))
        XCTAssertFalse(AIDataConsent.allowsSend(attaching: .nutrition))
        XCTAssertFalse(AIDataConsent.isCoachSummaryGranted)
    }

    func test_coachSummaryConsent_allowsBothKindsOfSend() {
        AIDataConsent.grantCoachSummary()

        XCTAssertTrue(AIDataConsent.allowsSend(attaching: .nutrition))
        XCTAssertTrue(AIDataConsent.allowsSend(attaching: nil))
    }

    func test_noConsent_blocksEverySend() {
        XCTAssertFalse(AIDataConsent.allowsSend(attaching: nil))
        XCTAssertFalse(AIDataConsent.allowsSend(attaching: .nutrition))
    }

    func test_revoke_clearsCoachSummaryConsent() {
        AIDataConsent.grantCoachSummary()
        AIDataConsent.revoke()

        XCTAssertFalse(AIDataConsent.isGranted)
        XCTAssertFalse(AIDataConsent.isCoachSummaryGranted)
    }

    func test_coachConsent_doesNotCoverBiologySummary() {
        AIDataConsent.grantCoachSummary()

        XCTAssertFalse(AIDataConsent.allowsSend(attaching: .biology))
    }

    func test_biologyConsent_allowsChatAndBiologyButNotCoach() {
        AIDataConsent.grantBiologySummary()

        XCTAssertTrue(AIDataConsent.allowsSend(attaching: .biology))
        XCTAssertTrue(AIDataConsent.allowsSend(attaching: nil))
        XCTAssertFalse(AIDataConsent.allowsSend(attaching: .nutrition))
    }

    func test_revoke_clearsBiologySummaryConsent() {
        AIDataConsent.grantBiologySummary()
        AIDataConsent.revoke()

        XCTAssertFalse(AIDataConsent.isBiologySummaryGranted)
    }
}
