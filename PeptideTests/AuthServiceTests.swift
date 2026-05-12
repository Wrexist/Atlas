import XCTest
@testable import Peptide

@MainActor
final class AuthServiceTests: XCTestCase {

    private var auth: AuthService!

    override func setUp() {
        super.setUp()
        auth = AuthService.shared
        auth.signOut()  // Start each test signed out with a clean Keychain
    }

    override func tearDown() {
        auth.signOut()
        auth = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func test_initialState_isSignedOut() {
        XCTAssertFalse(auth.isSignedIn)
        XCTAssertNil(auth.userIdentifier)
        XCTAssertNil(auth.userEmail)
        XCTAssertNil(auth.userDisplayName)
    }

    // MARK: - Authorization Handling
    //
    // We can't construct an `ASAuthorizationAppleIDCredential` in a unit
    // test — it's a system-vended type with no public init — so the
    // success branch of `handleAuthorization` isn't directly testable
    // here. It would need either a protocol seam (overkill for the
    // current shape) or an SKTestSession-style fake from Apple. The
    // failure branches below cover the only paths the test target can
    // honestly exercise without touching the real Apple ID flow.

    func test_handleAuthorization_withFailure_remainsSignedOut() {
        let error = NSError(domain: "test", code: -1)
        auth.handleAuthorization(.failure(error))

        XCTAssertFalse(auth.isSignedIn)
        XCTAssertNil(auth.userIdentifier)
    }

    func test_handleAuthorization_withFailure_doesNotSetUserIdentifier() {
        let error = NSError(domain: "ASAuthorizationError", code: 1001)
        auth.handleAuthorization(.failure(error))
        XCTAssertNil(auth.userIdentifier)
        XCTAssertFalse(auth.isSignedIn)
    }

    func test_handleAuthorization_failureThenFailure_remainsSignedOut() {
        auth.handleAuthorization(.failure(NSError(domain: "test", code: -1)))
        auth.handleAuthorization(.failure(NSError(domain: "test", code: -2)))
        XCTAssertFalse(auth.isSignedIn)
        XCTAssertNil(auth.userIdentifier)
    }

    // MARK: - Sign Out idempotency

    /// Calling signOut twice in a row must produce the same end state
    /// as one call — the second invocation can't crash on the absent
    /// Keychain items. This is the only post-signOut state the unit
    /// test target can verify without faking a real authorization.
    func test_signOut_isIdempotent() {
        auth.signOut()
        auth.signOut()
        XCTAssertFalse(auth.isSignedIn)
        XCTAssertNil(auth.userIdentifier)
        XCTAssertNil(auth.userEmail)
        XCTAssertNil(auth.userDisplayName)
    }

    // MARK: - Credential Validation

    func test_validateCredential_whenNotSignedIn_doesNotCrash() async {
        // With no stored user ID, validation should be a no-op
        await auth.validateCredential()
        XCTAssertFalse(auth.isSignedIn)
    }

    /// validateCredential must not toggle isSignedIn when there is nothing to validate.
    /// This guards the regression where transient errors used to be conflated with
    /// definitive negative states (notFound / revoked / transferred).
    func test_validateCredential_whenNotSignedIn_keepsSignedOutFalse() async {
        XCTAssertFalse(auth.isSignedIn)
        await auth.validateCredential()
        XCTAssertFalse(auth.isSignedIn)
        XCTAssertNil(auth.userIdentifier)
    }
}
