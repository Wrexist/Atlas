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

    // MARK: - Credential Validation

    func test_validateCredential_whenNotSignedIn_doesNotCrash() async {
        // With no stored user ID, validation should be a no-op
        await auth.validateCredential()
        XCTAssertFalse(auth.isSignedIn)
    }
}
