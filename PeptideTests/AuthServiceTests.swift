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

    // MARK: - Delete All Data

    /// A guest has no account, but must still be able to erase their data.
    func test_deleteAllData_asGuest_erasesStoreAndResetsInMemoryState() {
        SwiftDataRepository.shared.configureForTesting()
        let store = DataStore(seedSampleData: true)
        XCTAssertFalse(SwiftDataRepository.shared.loadProtocols().isEmpty)
        XCTAssertFalse(auth.isSignedIn)

        auth.deleteAllData()

        XCTAssertTrue(SwiftDataRepository.shared.loadProtocols().isEmpty)
        XCTAssertTrue(SwiftDataRepository.shared.loadEntries().isEmpty)
        XCTAssertTrue(store.protocols.isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.profile.name, "")
        XCTAssertTrue(store.customPeptides.isEmpty)
    }

    /// An unsaved in-memory edit made just before the erase must not be
    /// written back to disk by a later save.
    func test_deleteAllData_withUnsavedEdit_doesNotResurrectItOnNextSave() {
        SwiftDataRepository.shared.configureForTesting()
        let store = DataStore(seedSampleData: true)
        store.profile.name = "Unsaved Name"

        auth.deleteAllData()
        store.flushPendingSave()

        XCTAssertNotEqual(SwiftDataRepository.shared.loadProfile()?.name, "Unsaved Name")
        XCTAssertTrue(SwiftDataRepository.shared.loadProtocols().isEmpty)
    }

    func test_deleteAllData_removesBackupSnapshotsAndExports() {
        SwiftDataRepository.shared.configureForTesting()
        let store = DataStore(seedSampleData: true)
        XCTAssertNotNil(BackupSnapshotService.snapshotCurrentState(dataStore: store))
        let export = ExportService.shared.writeCSV("a,b", filename: "erase-test.csv")
        XCTAssertNotNil(export)

        auth.deleteAllData()

        XCTAssertTrue(BackupSnapshotService.availableSnapshots().isEmpty)
        if let export {
            XCTAssertFalse(FileManager.default.fileExists(atPath: export.path))
        }
    }

    /// A minimized workout lives in memory; the erase must end it, or its
    /// next set edit writes it back into the wiped store.
    func test_deleteAllData_endsTheActiveWorkout() {
        SwiftDataRepository.shared.configureForTesting()
        _ = DataStore(seedSampleData: true)
        WorkoutSessionService.shared.startWorkout()
        XCTAssertNotNil(WorkoutSessionService.shared.activeSession)

        auth.deleteAllData()

        XCTAssertNil(WorkoutSessionService.shared.activeSession)
        XCTAssertTrue(SwiftDataRepository.shared.loadAllWorkoutSessions().isEmpty)
    }

    func test_deleteAllData_resetsAchievements() {
        SwiftDataRepository.shared.configureForTesting()
        _ = DataStore(seedSampleData: true)
        AchievementService.shared.checkAchievements(
            totalDoses: 500, currentStreak: 100, bestStreak: 100, protocolCount: 10, daysLogged: 365
        )
        XCTAssertTrue(AchievementService.shared.achievements.contains(where: \.isUnlocked))

        auth.deleteAllData()

        XCTAssertFalse(AchievementService.shared.achievements.contains(where: \.isUnlocked))
        XCTAssertNil(UserDefaults.standard.data(forKey: "achievements"))
    }

    func test_deleteAccount_whenSignedOut_leavesDataIntact() {
        SwiftDataRepository.shared.configureForTesting()
        _ = DataStore(seedSampleData: true)

        auth.deleteAccount()

        XCTAssertFalse(SwiftDataRepository.shared.loadProtocols().isEmpty)
        SwiftDataRepository.shared.deleteAll()
    }
}
