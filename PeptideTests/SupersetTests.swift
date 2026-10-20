import XCTest
@testable import Peptide

final class SupersetTests: XCTestCase {

    private func entry(_ index: Int, sets: Int = 2, group: UUID? = nil) -> WorkoutExerciseEntry {
        WorkoutExerciseEntry(
            exerciseID: "ex\(index)", index: index,
            sets: (1...sets).map { SetEntry(index: $0, weightKg: 20, reps: 10) },
            supersetGroup: group
        )
    }

    private func completing(_ session: WorkoutSession, entry position: Int, set: Int) -> WorkoutSession {
        var copy = session
        copy.exercises[position].sets[set].completed = true
        return copy
    }

    // MARK: - Linking

    func test_linkWithNext_groupsTheTwoAndLettersThem() {
        var session = WorkoutSession(exercises: [entry(0), entry(1), entry(2)])
        session.linkSupersetWithNext(session.exercises[0].id)

        XCTAssertNotNil(session.exercises[0].supersetGroup)
        XCTAssertEqual(session.exercises[0].supersetGroup, session.exercises[1].supersetGroup)
        XCTAssertNil(session.exercises[2].supersetGroup)
        XCTAssertEqual(session.supersetLetter(for: session.exercises[1].id), "A")
        XCTAssertNil(session.supersetLetter(for: session.exercises[2].id))
    }

    func test_linkingTheSecondMemberOnward_buildsOneGiantSet() {
        var session = WorkoutSession(exercises: [entry(0), entry(1), entry(2)])
        session.linkSupersetWithNext(session.exercises[0].id)
        session.linkSupersetWithNext(session.exercises[1].id)

        XCTAssertEqual(Set(session.exercises.map(\.supersetGroup)).count, 1)
        XCTAssertEqual(session.supersetPartners(of: session.exercises[0].id).count, 2)
    }

    func test_unlinkingFromAPair_releasesTheOtherMemberToo() {
        var session = WorkoutSession(exercises: [entry(0), entry(1)])
        session.linkSupersetWithNext(session.exercises[0].id)
        session.unlinkSuperset(session.exercises[1].id)

        XCTAssertTrue(session.exercises.allSatisfy { $0.supersetGroup == nil })
    }

    func test_lastExercise_hasNothingBelowToLink() {
        var session = WorkoutSession(exercises: [entry(0)])
        session.linkSupersetWithNext(session.exercises[0].id)
        XCTAssertNil(session.exercises[0].supersetGroup)
    }

    // MARK: - Rounds

    func test_nextSet_alternatesBetweenMembers() {
        let group = UUID()
        var session = WorkoutSession(exercises: [entry(0, group: group), entry(1, group: group), entry(2)])
        let a = session.exercises[0], b = session.exercises[1]

        session = completing(session, entry: 0, set: 0)
        XCTAssertEqual(session.nextPendingSet(after: a.id)?.entry, b.id)
        XCTAssertTrue(session.continuesSuperset(from: a.id, to: b.id))

        session = completing(session, entry: 1, set: 0)
        XCTAssertEqual(session.nextPendingSet(after: b.id)?.entry, a.id)
        XCTAssertFalse(session.continuesSuperset(from: b.id, to: a.id), "The round is over, so rest")
    }

    func test_standaloneExercise_keepsGoingOnItself() {
        let session = WorkoutSession(exercises: [entry(0), entry(1)])
        let first = session.exercises[0]
        XCTAssertEqual(session.nextPendingSet(after: first.id)?.entry, first.id)
        XCTAssertFalse(session.continuesSuperset(from: first.id, to: session.exercises[1].id))
    }

    func test_partnerFinished_returnsToTheSourceAndRests() {
        let group = UUID()
        var session = WorkoutSession(exercises: [entry(0, sets: 3, group: group), entry(1, sets: 1, group: group)])
        session = completing(session, entry: 1, set: 0)
        session = completing(session, entry: 0, set: 0)
        let a = session.exercises[0]

        XCTAssertEqual(session.nextPendingSet(after: a.id)?.entry, a.id)
        XCTAssertFalse(session.continuesSuperset(from: a.id, to: a.id))
    }
}
