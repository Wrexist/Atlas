import XCTest
@testable import Peptide

/// A116: the decision logic behind holding the shared store closed after
/// an iCloud identity change. The container swap itself is device-only.
final class CloudIdentityChangeEngineTests: XCTestCase {

    func test_change_noAccountBeforeOrAfter_isUnchanged() {
        XCTAssertEqual(change(false, false, sameAccount: false), .unchanged)
    }

    func test_change_sameAccount_isUnchanged() {
        XCTAssertEqual(change(true, true, sameAccount: true), .unchanged)
    }

    func test_change_differentAccount_isSwitchedAccount() {
        XCTAssertEqual(change(true, true, sameAccount: false), .switchedAccount)
    }

    func test_change_accountGone_isSignedOut() {
        XCTAssertEqual(change(true, false, sameAccount: false), .signedOut)
    }

    func test_change_accountAppears_isSignedIn() {
        XCTAssertEqual(change(false, true, sameAccount: false), .signedIn)
    }

    func test_needsUserDecision_signedOutWithData_holdsStore() {
        XCTAssertTrue(CloudIdentityChangeEngine.needsUserDecision(.signedOut, storeHasData: true))
    }

    func test_needsUserDecision_switchedAccountWithData_holdsStore() {
        XCTAssertTrue(CloudIdentityChangeEngine.needsUserDecision(.switchedAccount, storeHasData: true))
    }

    func test_needsUserDecision_emptyStore_neverAsks() {
        for kind: CloudIdentityChange in [.unchanged, .signedIn, .signedOut, .switchedAccount] {
            XCTAssertFalse(CloudIdentityChangeEngine.needsUserDecision(kind, storeHasData: false), "\(kind)")
        }
    }

    func test_needsUserDecision_firstSignInWithData_syncsWithoutAsking() {
        XCTAssertFalse(CloudIdentityChangeEngine.needsUserDecision(.signedIn, storeHasData: true))
    }

    private func change(_ previous: Bool, _ current: Bool, sameAccount: Bool) -> CloudIdentityChange {
        CloudIdentityChangeEngine.change(
            previousSignedIn: previous,
            currentSignedIn: current,
            sameAccount: sameAccount
        )
    }
}
