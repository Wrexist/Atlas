import XCTest
@testable import Peptide

/// The record of what the last set completion moved must survive a relaunch,
/// or a correction made after iOS killed the app mid-rest leaves the
/// lowered sets lowered.
final class DeviceSessionMemoryTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "DeviceSessionMemoryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func test_savedCompletion_survivesReload_andStillRestoresTheMovedSets() throws {
        let done = SetEntry(index: 1, weightKg: 80, reps: 6, completed: true)
        let second = SetEntry(index: 2, weightKg: 80, reps: 8)
        let third = SetEntry(index: 3, weightKg: 80, reps: 8)
        var lowered = [done, second, third]
        lowered[1].weightKg = 77.5
        lowered[2].weightKg = 77.5
        let effect = SetCompletionEffect(
            entryID: UUID(), setID: done.id, fromKg: 80,
            before: [done, second, third], after: lowered
        )

        SetCompletionEffect.save(effect, to: defaults)
        let reloaded = try XCTUnwrap(SetCompletionEffect.load(from: defaults))

        XCTAssertEqual(reloaded, effect)
        XCTAssertEqual(reloaded.reverted(lowered).map(\.weightKg), [80, 80, 80])
    }

    func test_reloadedCompletion_leavesAHandEditedSetAlone() throws {
        let done = SetEntry(index: 1, weightKg: 80, reps: 6, completed: true)
        let pending = SetEntry(index: 2, weightKg: 80, reps: 8)
        var lowered = pending
        lowered.weightKg = 77.5
        SetCompletionEffect.save(
            SetCompletionEffect(entryID: UUID(), setID: done.id, fromKg: 80, before: [done, pending], after: [done, lowered]),
            to: defaults
        )
        var handEdited = lowered
        handEdited.weightKg = 75

        let reloaded = try XCTUnwrap(SetCompletionEffect.load(from: defaults))

        XCTAssertEqual(reloaded.reverted([done, handEdited]).map(\.weightKg), [80, 75])
    }

    func test_savingNil_clearsTheCompletion() {
        let effect = SetCompletionEffect(entryID: UUID(), setID: UUID(), fromKg: 80, before: [], after: [])
        SetCompletionEffect.save(effect, to: defaults)

        SetCompletionEffect.save(nil, to: defaults)

        XCTAssertNil(SetCompletionEffect.load(from: defaults))
    }
}
