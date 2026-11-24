import XCTest
@testable import Peptide

/// The adaptive calorie-targets switch rides the synced profile, so one
/// device turning it off stops every device moving the shared targets.
@MainActor
final class AdaptiveTargetsSyncTests: XCTestCase {

    private let accepted = NutritionTargets(calories: 2400, proteinG: 160, carbsG: 250, fatG: 80, fiberG: 30)

    func test_storedProfile_roundTrip_keepsAdaptiveSwitch() throws {
        var profile = UserProfile.fresh
        profile.adaptiveTargets = AdaptiveTargetsSetting(isEnabled: false, followedTargets: accepted)

        let roundTripped = try StoredProfile.make(from: profile).toUserProfile()

        XCTAssertEqual(roundTripped.adaptiveTargets, profile.adaptiveTargets)
    }

    func test_storedProfile_blobWithoutSwitch_decodesNil() throws {
        let stored = try StoredProfile.make(from: .fresh)
        stored.extensionData = Data(#"{"supplements":[]}"#.utf8)

        XCTAssertNil(try stored.toUserProfile().adaptiveTargets)
    }

    func test_rebasing_switchTurnedOffElsewhere_survivesLocalTargetEdit() {
        var baseline = UserProfile.fresh
        baseline.adaptiveTargets = AdaptiveTargetsSetting(isEnabled: true, followedTargets: accepted)
        var local = baseline
        local.nutritionTargets = accepted
        var remote = baseline
        remote.adaptiveTargets = AdaptiveTargetsSetting(isEnabled: false, followedTargets: nil)

        let merged = ProfileMergeEngine.rebasing(local: local, baseline: baseline, remote: remote)

        XCTAssertEqual(merged.adaptiveTargets?.isEnabled, false)
        XCTAssertEqual(merged.nutritionTargets, accepted)
    }

    func test_reconcile_freshRowWithoutSwitch_adoptsOtherRows() {
        var other = UserProfile.fresh
        other.adaptiveTargets = AdaptiveTargetsSetting(isEnabled: false, followedTargets: nil)

        let merged = ProfileMergeEngine.reconcile(.fresh, with: other)

        XCTAssertEqual(merged.adaptiveTargets?.isEnabled, false)
    }
}
