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
        XCTAssertTrue(decision(.signedOut, hasData: true, hadEarlier: true))
    }

    func test_needsUserDecision_switchedAccountWithData_holdsStore() {
        XCTAssertTrue(decision(.switchedAccount, hasData: true, hadEarlier: true))
    }

    func test_needsUserDecision_emptyStore_neverAsks() {
        for kind: CloudIdentityChange in [.unchanged, .signedIn, .signedOut, .switchedAccount] {
            XCTAssertFalse(decision(kind, hasData: false, hadEarlier: true), "\(kind)")
        }
    }

    func test_needsUserDecision_unchanged_neverAsks() {
        XCTAssertFalse(decision(.unchanged, hasData: true, hadEarlier: true))
    }

    func test_needsUserDecision_firstEverSignInWithData_syncsWithoutAsking() {
        XCTAssertFalse(decision(.signedIn, hasData: true, hadEarlier: false))
    }

    func test_needsUserDecision_signInAfterEarlierAccountWithData_asks() {
        XCTAssertTrue(decision(.signedIn, hasData: true, hadEarlier: true))
    }

    private func decision(_ change: CloudIdentityChange, hasData: Bool, hadEarlier: Bool) -> Bool {
        CloudIdentityChangeEngine.needsUserDecision(
            change,
            storeHasData: hasData,
            hadEarlierIdentity: hadEarlier
        )
    }

    private func change(_ previous: Bool, _ current: Bool, sameAccount: Bool) -> CloudIdentityChange {
        CloudIdentityChangeEngine.change(
            previousSignedIn: previous,
            currentSignedIn: current,
            sameAccount: sameAccount
        )
    }
}
