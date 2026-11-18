import CloudKit
import SwiftData
import XCTest
@testable import Peptide

/// C233: CloudKit's account, not iCloud Drive's ubiquity token, decides
/// whether the store syncs and whether the account changed. The token is
/// nil whenever Drive is off although the CloudKit account works.
@MainActor
final class CloudAccountChangeTests: XCTestCase {

    private struct FakeCloudAccount: CloudAccountProviding {
        struct NoRecord: Error {}

        let status: CKAccountStatus
        let recordName: String?

        static func signedIn(_ name: String) -> FakeCloudAccount {
            FakeCloudAccount(status: .available, recordName: name)
        }

        func accountStatus() async throws -> CKAccountStatus { status }

        func userRecordName() async throws -> String {
            guard let recordName else { throw NoRecord() }
            return recordName
        }
    }

    private var repo: SwiftDataRepository!
    private var token: NSString?

    override func setUp() {
        super.setUp()
        repo = SwiftDataRepository.shared
        repo.configureForTesting()
    }

    override func tearDown() {
        repo.configureForTesting()
        repo.deleteAll()
        repo = nil
        token = nil
        super.tearDown()
    }

    private func use(_ account: FakeCloudAccount) {
        repo.useCloudAccountForTesting(account) { [weak self] in self?.token }
    }

    /// Signs in to `account` with data in the store and an Apple Health
    /// weigh-in among the device-local records.
    private func signedInWithData(as account: String) async -> WeightEntry {
        token = "drive-token" as NSString
        use(.signedIn(account))
        await repo.refreshCloudAccount()
        repo.saveProfile(.fresh)
        let weighIn = WeightEntry(date: Date(timeIntervalSince1970: 1_700_000_000), kg: 80)
        XCTAssertTrue(repo.recordHealthWeightImports([weighIn]))
        XCTAssertTrue(repo.hasAnyData)
        return weighIn
    }

    func test_tokenNilAccountAvailable_opensCloudKitStore() async {
        token = nil
        use(.signedIn("account-a"))

        await repo.refreshCloudAccount()

        XCTAssertEqual(repo.cloudSyncState, .active)
        XCTAssertTrue(repo.isCloudSyncEnabled)
        XCTAssertFalse(repo.isAwaitingAccountDecision)
    }

    func test_iCloudDriveToggled_sameAccount_keepsDataAndSyncs() async {
        let weighIn = await signedInWithData(as: "account-a")

        token = nil
        await repo.refreshCloudAccount()

        XCTAssertFalse(repo.isAwaitingAccountDecision)
        XCTAssertTrue(repo.isCloudSyncEnabled)
        XCTAssertTrue(repo.hasAnyData)
        XCTAssertTrue(repo.isHealthWeightImport(weighIn.id))

        token = "drive-token" as NSString
        await repo.refreshCloudAccount()

        XCTAssertFalse(repo.isAwaitingAccountDecision)
        XCTAssertTrue(repo.isCloudSyncEnabled)
        XCTAssertTrue(repo.hasAnyData)
        XCTAssertTrue(repo.isHealthWeightImport(weighIn.id))
    }

    func test_accountSwitchedWithData_holdsWithoutWiping() async {
        let weighIn = await signedInWithData(as: "account-a")

        use(.signedIn("account-b"))
        await repo.refreshCloudAccount()

        XCTAssertTrue(repo.isAwaitingAccountDecision)
        XCTAssertTrue(repo.isHealthWeightImport(weighIn.id))
    }

    func test_accountUnknown_leavesStoreAndRecordsAlone() async {
        let weighIn = await signedInWithData(as: "account-a")

        use(FakeCloudAccount(status: .couldNotDetermine, recordName: nil))
        await repo.refreshCloudAccount()

        XCTAssertFalse(repo.isAwaitingAccountDecision)
        XCTAssertTrue(repo.isCloudSyncEnabled)
        XCTAssertTrue(repo.hasAnyData)
        XCTAssertTrue(repo.isHealthWeightImport(weighIn.id))
    }

    func test_availableButUserRecordUnreadable_neverWipes() async {
        let weighIn = await signedInWithData(as: "account-a")

        use(FakeCloudAccount(status: .available, recordName: nil))
        await repo.refreshCloudAccount()

        XCTAssertFalse(repo.isAwaitingAccountDecision)
        XCTAssertTrue(repo.hasAnyData)
        XCTAssertTrue(repo.isHealthWeightImport(weighIn.id))
    }

    func test_syncState_availableAccountWithoutCloudStore_isUnavailableNotNoAccount() {
        XCTAssertEqual(SwiftDataRepository.syncState(refining: .noAccount, with: .available), .unavailable)
        XCTAssertEqual(SwiftDataRepository.syncState(refining: .unavailable, with: .noAccount), .noAccount)
        XCTAssertEqual(SwiftDataRepository.syncState(refining: .unavailable, with: .restricted), .restricted)
        XCTAssertEqual(SwiftDataRepository.syncState(refining: .unavailable, with: nil), .unavailable)
    }
}
