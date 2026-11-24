import XCTest
@testable import Peptide

/// Custom peptides ride the synced profile's residual blob, with
/// custom-peptides.json as this device's cache.
@MainActor
final class CustomPeptideSyncTests: XCTestCase {

    private func peptide(_ name: String) -> Peptide {
        Peptide(
            name: name, abbreviation: name, category: .recovery, description: "",
            benefits: [], dosageRange: "", frequency: "", halfLife: "", adminRoute: "",
            researchLinks: [], imageSystemName: "pills"
        )
    }

    func test_storedProfile_roundTrip_keepsCustomPeptides() throws {
        var profile = UserProfile.fresh
        profile.customPeptides = [peptide("X-1"), peptide("X-2")]

        let roundTripped = try StoredProfile.make(from: profile).toUserProfile()

        XCTAssertEqual(roundTripped.customPeptides, profile.customPeptides)
    }

    func test_storedProfile_blobWithoutCustomPeptides_decodesEmpty() throws {
        let stored = try StoredProfile.make(from: .fresh)
        stored.extensionData = Data(#"{"supplements":[]}"#.utf8)

        XCTAssertEqual(try stored.toUserProfile().customPeptides, [])
    }

    func test_mergedCustomPeptides_unionsByID_syncedFirst() {
        let shared = peptide("Shared")
        let syncedOnly = peptide("Synced")
        let localOnly = peptide("Local")

        let merged = DataStore.mergedCustomPeptides(synced: [shared, syncedOnly], local: [localOnly, shared])

        XCTAssertEqual(merged.map(\.id), [shared.id, syncedOnly.id, localOnly.id])
    }

    func test_reconcile_duplicateRows_keepsCustomPeptidesFromBoth() {
        var primary = UserProfile.fresh
        primary.customPeptides = [peptide("A")]
        var other = UserProfile.fresh
        other.customPeptides = [primary.customPeptides[0], peptide("B")]

        let merged = ProfileMergeEngine.reconcile(primary, with: other)

        XCTAssertEqual(merged.customPeptides.map(\.name), ["A", "B"])
    }

    func test_rebasing_bothDevicesAddedCompounds_keepsBoth() {
        let baseline = UserProfile.fresh
        var local = baseline
        local.customPeptides = [peptide("Mine")]
        var remote = baseline
        remote.customPeptides = [peptide("Theirs")]

        let merged = ProfileMergeEngine.rebasing(local: local, baseline: baseline, remote: remote)

        XCTAssertEqual(merged.customPeptides.map(\.name), ["Theirs", "Mine"])
    }
}
