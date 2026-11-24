import XCTest
@testable import Peptide

@MainActor
final class WorkoutTypeOverrideStoreTests: XCTestCase {

    private func healthWorkout(_ activity: CardioActivity) -> ImportedCardioWorkout {
        ImportedCardioWorkout(
            id: UUID(),
            activity: activity,
            start: Date(timeIntervalSince1970: 1_800_000_000),
            end: Date(timeIntervalSince1970: 1_800_003_600),
            duration: 3_600,
            distanceMeters: nil,
            activeKilocalories: 320,
            averageHeartRate: 98,
            sourceName: "Apple Watch"
        )
    }

    func test_pickedType_replacesHealthsTypeAndKeepsEverythingElse() {
        let dive = healthWorkout(.other)
        let overrides = WorkoutTypeOverrideStore.setting(.diving, for: dive.id, in: [:])

        let shown = WorkoutTypeOverrideStore.applied(overrides, to: [dive])

        XCTAssertEqual(shown.first?.activity, .diving)
        XCTAssertEqual(shown.first?.id, dive.id)
        XCTAssertEqual(shown.first?.duration, dive.duration)
        XCTAssertEqual(shown.first?.activeKilocalories, dive.activeKilocalories)
    }

    func test_workoutWithoutPick_keepsHealthsType() {
        let run = healthWorkout(.running)
        let overrides = WorkoutTypeOverrideStore.setting(.diving, for: UUID(), in: [:])

        XCTAssertEqual(WorkoutTypeOverrideStore.applied(overrides, to: [run]).first?.activity, .running)
    }

    func test_clearingPick_returnsToHealthsType() {
        let dive = healthWorkout(.other)
        var overrides = WorkoutTypeOverrideStore.setting(.diving, for: dive.id, in: [:])
        overrides = WorkoutTypeOverrideStore.setting(nil, for: dive.id, in: overrides)

        XCTAssertNil(WorkoutTypeOverrideStore.activity(for: dive.id, in: overrides))
        XCTAssertEqual(WorkoutTypeOverrideStore.applied(overrides, to: [dive]).first?.activity, .other)
    }

    func test_pick_survivesTheProfilesStorageAndBackupEncoding() throws {
        let dive = healthWorkout(.other)
        var profile = UserProfile.fresh
        profile.workoutTypeOverrides = WorkoutTypeOverrideStore.setting(.diving, for: dive.id, in: [:])

        let stored = try StoredProfile.make(from: profile).toUserProfile()
        let backedUp = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(profile))

        XCTAssertEqual(WorkoutTypeOverrideStore.activity(for: dive.id, in: stored.workoutTypeOverrides), .diving)
        XCTAssertEqual(WorkoutTypeOverrideStore.activity(for: dive.id, in: backedUp.workoutTypeOverrides), .diving)
    }

    func test_profileDecode_olderProfileWithoutPicks_decodesEmpty() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(UserProfile.fresh)) as? [String: Any])
        object.removeValue(forKey: "workoutTypeOverrides")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(try JSONDecoder().decode(UserProfile.self, from: legacy).workoutTypeOverrides, [:])
    }

    func test_rebasing_twoDevicesPickDifferentWorkouts_keepsBothAndLocalClear() {
        let cleared = UUID().uuidString, phone = UUID().uuidString, ipad = UUID().uuidString
        var baseline = UserProfile.fresh
        baseline.workoutTypeOverrides = [cleared: CardioActivity.diving.rawValue]
        var local = baseline
        local.workoutTypeOverrides = [phone: CardioActivity.running.rawValue]
        var remote = baseline
        remote.workoutTypeOverrides[ipad] = CardioActivity.diving.rawValue

        let merged = ProfileMergeEngine.rebasing(local: local, baseline: baseline, remote: remote)

        XCTAssertEqual(merged.workoutTypeOverrides, [
            phone: CardioActivity.running.rawValue,
            ipad: CardioActivity.diving.rawValue,
        ])
    }

    func test_reconcile_duplicateRows_keepPicksFromBoth() {
        let shared = UUID().uuidString, other = UUID().uuidString
        var primary = UserProfile.fresh
        primary.workoutTypeOverrides = [shared: CardioActivity.running.rawValue]
        var second = UserProfile.fresh
        second.workoutTypeOverrides = [shared: CardioActivity.diving.rawValue, other: CardioActivity.diving.rawValue]

        let merged = ProfileMergeEngine.reconcile(primary, with: second)

        XCTAssertEqual(merged.workoutTypeOverrides, [
            shared: CardioActivity.running.rawValue,
            other: CardioActivity.diving.rawValue,
        ])
    }

    func test_legacy_readsDevicePicksUntilDeleted() throws {
        let suite = "WorkoutTypeOverrideStoreTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID().uuidString
        defaults.set([id: CardioActivity.diving.rawValue], forKey: "workoutTypeOverrides.v1")

        XCTAssertEqual(WorkoutTypeOverrideStore.legacy(from: defaults), [id: CardioActivity.diving.rawValue])
        XCTAssertEqual(WorkoutTypeOverrideStore.legacy(from: defaults), [id: CardioActivity.diving.rawValue])
        WorkoutTypeOverrideStore.deleteLegacy(from: defaults)
        XCTAssertNil(WorkoutTypeOverrideStore.legacy(from: defaults))
    }
}
