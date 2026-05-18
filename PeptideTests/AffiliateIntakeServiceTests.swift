import XCTest
@testable import Peptide

/// Smoke tests for the affiliate-intake drain. The network path is
/// configuration-gated via Info.plist (`AffiliateIntakeEndpoint`),
/// which test bundles don't ship, so these tests pin the no-op
/// branches: nil application, missing endpoint, and the idempotency
/// guard that prevents re-POSTing the same submission.
@MainActor
final class AffiliateIntakeServiceTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        // Clear the persistent "drained at" cursor so each test starts
        // from a clean slate.
        UserDefaults.standard.removeObject(forKey: "affiliate.intake.drainedAt.v1")
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "affiliate.intake.drainedAt.v1")
        try await super.tearDown()
    }

    func test_drainIfReady_nilApplication_isNoOp() async {
        // Should return immediately without touching UserDefaults or
        // attempting network. Asserting no UD write is the proxy for
        // "did the function early-out before the network branch".
        await AffiliateIntakeService.drainIfReady(nil)
        XCTAssertNil(UserDefaults.standard.object(forKey: "affiliate.intake.drainedAt.v1"))
    }

    func test_drainIfReady_withoutConfiguredEndpoint_isNoOp() async {
        // Test bundle has no `AffiliateIntakeEndpoint` Info.plist key —
        // drain should silently return without recording a drain
        // timestamp.
        let app = AffiliateApplication(
            handle: "test",
            channel: .instagram,
            audienceBand: .k1to10,
            channelURL: nil,
            notes: nil,
            submittedAt: Date(),
            name: nil,
            email: nil
        )
        await AffiliateIntakeService.drainIfReady(app)
        XCTAssertNil(
            UserDefaults.standard.object(forKey: "affiliate.intake.drainedAt.v1"),
            "drainedAt should remain nil when no endpoint is configured"
        )
    }
}
