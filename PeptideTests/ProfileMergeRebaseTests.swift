import XCTest
@testable import Peptide

/// Two devices adding to the same residual list before either reloads:
/// the rebase must keep both adds, not let one device's whole list win.
@MainActor
final class ProfileMergeRebaseTests: XCTestCase {

    func test_rebasing_twoDevicesAddProgressPhotos_keepsBothInOrder() {
        var baseline = UserProfile.fresh
        baseline.progressPhotoFilenames = ["first.jpg", "old.jpg"]
        var local = baseline
        local.progressPhotoFilenames.removeAll { $0 == "old.jpg" }
        local.progressPhotoFilenames.append("phone.jpg")
        var remote = baseline
        remote.progressPhotoFilenames.append("ipad.jpg")

        let merged = ProfileMergeEngine.rebasing(local: local, baseline: baseline, remote: remote)

        XCTAssertEqual(merged.progressPhotoFilenames, ["first.jpg", "ipad.jpg", "phone.jpg"])
    }

    func test_rebasing_twoDevicesFreezeDifferentDays_keepsBothFreezes() {
        var baseline = UserProfile.fresh
        baseline.streakFreezeDays = ["2026-11-01"]
        var local = baseline
        local.streakFreezeDays.insert("2026-11-10")
        var remote = baseline
        remote.streakFreezeDays.insert("2026-11-12")

        let merged = ProfileMergeEngine.rebasing(local: local, baseline: baseline, remote: remote)

        XCTAssertEqual(merged.streakFreezeDays, ["2026-11-01", "2026-11-10", "2026-11-12"])
    }

    func test_rebasing_twoDevicesLogLegacyWorkouts_keepsBoth() {
        let baseline = UserProfile.fresh
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let phone = WorkoutEntry(date: date, name: "Hill sprints", sets: 1, reps: 1, durationMinutes: 20)
        let ipad = WorkoutEntry(date: date, name: "Push day", sets: 3, reps: 10, durationMinutes: 45)
        var local = baseline
        local.workoutHistory = [phone]
        var remote = baseline
        remote.workoutHistory = [ipad]

        let merged = ProfileMergeEngine.rebasing(local: local, baseline: baseline, remote: remote)

        XCTAssertEqual(merged.workoutHistory.map(\.id), [ipad.id, phone.id])
    }

    func test_rebasing_progressPhotosUnchangedHere_takesRemote() {
        var baseline = UserProfile.fresh
        baseline.progressPhotoFilenames = ["a.jpg", "b.jpg"]
        var remote = baseline
        remote.progressPhotoFilenames = ["b.jpg"]

        let merged = ProfileMergeEngine.rebasing(local: baseline, baseline: baseline, remote: remote)

        XCTAssertEqual(merged.progressPhotoFilenames, ["b.jpg"])
    }
}
