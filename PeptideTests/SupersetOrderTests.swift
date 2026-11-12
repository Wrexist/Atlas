import XCTest
@testable import Peptide

/// The shared ordering the phone's session and the Watch's snapshot both
/// search, so the wrist's guess at the next set matches the phone's.
final class SupersetOrderTests: XCTestCase {

    private struct Item: Equatable {
        let id = UUID()
        let group: UUID?
    }

    private func order(after source: Item, in items: [Item]) -> [Item] {
        SupersetOrder.searchOrder(after: source.id, in: items, id: \.id, group: \.group)
    }

    func test_standaloneSource_leadsThenWorkoutOrder() {
        let a = Item(group: nil), b = Item(group: nil), c = Item(group: nil)
        XCTAssertEqual(order(after: b, in: [a, b, c]), [b, a, c])
    }

    func test_supersetSource_partnerComesBeforeItself() {
        let group = UUID()
        let a = Item(group: group), b = Item(group: group), c = Item(group: nil)
        XCTAssertEqual(order(after: a, in: [a, b, c]), [b, a, c])
    }

    func test_lastSupersetMember_wrapsRoundToTheFirst() {
        let group = UUID()
        let a = Item(group: group), b = Item(group: group), d = Item(group: group), c = Item(group: nil)
        XCTAssertEqual(order(after: d, in: [a, b, d, c]), [a, b, d, c])
    }

    func test_unknownSource_keepsWorkoutOrder() {
        let a = Item(group: nil), b = Item(group: nil)
        XCTAssertEqual(order(after: Item(group: nil), in: [a, b]), [a, b])
    }

    func test_continuesRound_whenPartnerIsBehind() {
        let group = UUID()
        XCTAssertTrue(SupersetOrder.continuesRound(
            sourceID: UUID(), sourceGroup: group, sourceCompleted: 2,
            targetID: UUID(), targetGroup: group, targetCompleted: 1
        ))
    }

    func test_continuesRound_isFalseOnceRoundIsEven() {
        let group = UUID()
        XCTAssertFalse(SupersetOrder.continuesRound(
            sourceID: UUID(), sourceGroup: group, sourceCompleted: 2,
            targetID: UUID(), targetGroup: group, targetCompleted: 2
        ))
    }

    func test_continuesRound_isFalseAcrossGroupsOrForSelf() {
        let id = UUID()
        XCTAssertFalse(SupersetOrder.continuesRound(
            sourceID: UUID(), sourceGroup: UUID(), sourceCompleted: 1,
            targetID: UUID(), targetGroup: UUID(), targetCompleted: 0
        ))
        XCTAssertFalse(SupersetOrder.continuesRound(
            sourceID: id, sourceGroup: nil, sourceCompleted: 1,
            targetID: UUID(), targetGroup: nil, targetCompleted: 0
        ))
        let group = UUID()
        XCTAssertFalse(SupersetOrder.continuesRound(
            sourceID: id, sourceGroup: group, sourceCompleted: 1,
            targetID: id, targetGroup: group, targetCompleted: 0
        ))
    }
}
