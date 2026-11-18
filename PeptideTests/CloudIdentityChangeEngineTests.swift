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

    // MARK: - Device-local records (C234)

    func test_forgetsDeviceLocalRecords_switchOpenedWithoutPrompt_erases() {
        XCTAssertTrue(CloudIdentityChangeEngine.forgetsDeviceLocalRecords(.switchedAccount, heldForDecision: false))
        XCTAssertTrue(CloudIdentityChangeEngine.forgetsDeviceLocalRecords(.signedOut, heldForDecision: false))
    }

    func test_forgetsDeviceLocalRecords_heldForDecision_leavesThemToTheAnswer() {
        for kind: CloudIdentityChange in [.unchanged, .signedIn, .signedOut, .switchedAccount] {
            XCTAssertFalse(CloudIdentityChangeEngine.forgetsDeviceLocalRecords(kind, heldForDecision: true), "\(kind)")
        }
    }

    func test_forgetsDeviceLocalRecords_firstSignIn_keeps() {
        XCTAssertFalse(CloudIdentityChangeEngine.forgetsDeviceLocalRecords(.signedIn, heldForDecision: false))
        XCTAssertFalse(CloudIdentityChangeEngine.forgetsDeviceLocalRecords(.unchanged, heldForDecision: false))
    }

    // MARK: - CloudKit account fingerprint (C233)

    func test_changeFromRecorded_sameAccount_isUnchanged() {
        XCTAssertEqual(CloudIdentityChangeEngine.change(from: .account("a"), to: "a"), .unchanged)
    }

    func test_changeFromRecorded_otherAccount_isSwitchedAccount() {
        XCTAssertEqual(CloudIdentityChangeEngine.change(from: .account("a"), to: "b"), .switchedAccount)
    }

    func test_changeFromRecorded_noAccountNow_isSignedOut() {
        XCTAssertEqual(CloudIdentityChangeEngine.change(from: .account("a"), to: nil), .signedOut)
        XCTAssertEqual(CloudIdentityChangeEngine.change(from: .unidentified, to: nil), .signedOut)
    }

    func test_changeFromRecorded_firstAccount_isSignedIn() {
        XCTAssertEqual(CloudIdentityChangeEngine.change(from: .noAccount, to: "a"), .signedIn)
        XCTAssertEqual(CloudIdentityChangeEngine.change(from: .noAccount, to: nil), .unchanged)
    }

    func test_unverifiedAccount_asksOnlyWithDataAndNeverErases() {
        XCTAssertEqual(CloudIdentityChangeEngine.change(from: .unidentified, to: "a"), .unverified)
        XCTAssertTrue(decision(.unverified, hasData: true, hadEarlier: true))
        XCTAssertFalse(decision(.unverified, hasData: false, hadEarlier: true))
        XCTAssertFalse(CloudIdentityChangeEngine.forgetsDeviceLocalRecords(.unverified, heldForDecision: false))
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
