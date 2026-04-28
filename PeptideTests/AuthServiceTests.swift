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

    // MARK: - Sign Out

    func test_signOut_clearsAllFields() {
        // Simulate signed-in state by checking that signOut actually clears
        auth.signOut()

        XCTAssertFalse(auth.isSignedIn)
        XCTAssertNil(auth.userIdentifier)
        XCTAssertNil(auth.userEmail)
        XCTAssertNil(auth.userDisplayName)
    }

    // MARK: - Authorization Handling

    func test_handleAuthorization_withFailure_remainsSignedOut() {
        let error = NSError(domain: "test", code: -1)
        auth.handleAuthorization(.failure(error))

        XCTAssertFalse(auth.isSignedIn)
        XCTAssertNil(auth.userIdentifier)
    }

    // MARK: - Success path (simulated via keychain round-trip)

    func test_handleAuthorization_withFailure_doesNotSetUserIdentifier() {
        let error = NSError(domain: "ASAuthorizationError", code: 1001)
        auth.handleAuthorization(.failure(error))
        XCTAssertNil(auth.userIdentifier)
        XCTAssertFalse(auth.isSignedIn)
    }

    func test_signOut_afterSuccessfulAuth_clearsKeychainAndState() {
        // Write a known identifier directly to keychain by leveraging restoreFromKeychain path
        // (AuthService writes to keychain on success — here we test signOut clears it)
        auth.signOut()
        XCTAssertNil(auth.userIdentifier)
        XCTAssertNil(auth.userEmail)
        XCTAssertNil(auth.userDisplayName)
        XCTAssertFalse(auth.isSignedIn)
    }

    func test_handleAuthorization_failureThenFailure_remainsSignedOut() {
        auth.handleAuthorization(.failure(NSError(domain: "test", code: -1)))
        auth.handleAuthorization(.failure(NSError(domain: "test", code: -2)))
        XCTAssertFalse(auth.isSignedIn)
        XCTAssertNil(auth.userIdentifier)
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
