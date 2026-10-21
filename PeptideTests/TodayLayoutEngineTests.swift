import XCTest
@testable import Peptide

/// Pins how a stored Today arrangement survives app updates: unknown
/// ids drop out, sections new to the stored order take their default
/// slot, and hidden sections stay out of what Today renders.
final class TodayLayoutEngineTests: XCTestCase {

    private func ids(_ sections: [TodaySection]) -> [String] {
        sections.map(\.rawValue)
    }

    // MARK: - Order

    func test_sections_emptyStoredOrder_isDefaultOrder() {
        XCTAssertEqual(TodayLayoutEngine.sections(storedOrder: []), TodaySection.allCases)
    }

    func test_sections_fullStoredOrder_keepsStoredOrder() {
        let reversed = Array(TodaySection.allCases.reversed())
        XCTAssertEqual(TodayLayoutEngine.sections(storedOrder: ids(reversed)), reversed)
    }

    func test_sections_unknownIds_areDropped() {
        let stored = ["sleepCoach", "habits", "", "atAGlance"]
        let defaults: [TodaySection] = [.atAGlance, .habits]
        XCTAssertEqual(
            TodayLayoutEngine.sections(storedOrder: stored, defaults: defaults),
            [.habits, .atAGlance]
        )
    }

    func test_sections_duplicateIds_keepFirstPosition() {
        let defaults: [TodaySection] = [.atAGlance, .habits, .timeline]
        XCTAssertEqual(
            TodayLayoutEngine.sections(storedOrder: ["timeline", "habits", "timeline", "atAGlance"], defaults: defaults),
            [.timeline, .habits, .atAGlance]
        )
    }

    func test_sections_sectionRemovedFromBuild_isDropped() {
        // `.coaching` is a known id but this build's defaults no longer ship it.
        let defaults: [TodaySection] = [.atAGlance, .habits]
        XCTAssertEqual(
            TodayLayoutEngine.sections(storedOrder: ["coaching", "habits", "atAGlance"], defaults: defaults),
            [.habits, .atAGlance]
        )
    }

    func test_sections_newSection_insertedAfterItsDefaultPredecessor() {
        // Stored by a build that shipped without `.checklist`; the user
        // had moved `.timeline` to the top.
        let defaults: [TodaySection] = [.atAGlance, .habits, .checklist, .doses, .timeline]
        let stored = ["timeline", "atAGlance", "habits", "doses"]
        XCTAssertEqual(
            TodayLayoutEngine.sections(storedOrder: stored, defaults: defaults),
            [.timeline, .atAGlance, .habits, .checklist, .doses]
        )
    }

    func test_sections_newFirstSection_insertedAtTop() {
        let defaults: [TodaySection] = [.coaching, .habits, .doses]
        XCTAssertEqual(
            TodayLayoutEngine.sections(storedOrder: ["doses", "habits"], defaults: defaults),
            [.coaching, .doses, .habits]
        )
    }

    func test_sections_consecutiveNewSections_keepDefaultSequence() {
        let defaults: [TodaySection] = [.atAGlance, .habits, .checklist, .doses]
        XCTAssertEqual(
            TodayLayoutEngine.sections(storedOrder: ["doses", "atAGlance"], defaults: defaults),
            [.doses, .atAGlance, .habits, .checklist]
        )
    }

    func test_sections_alwaysContainsEveryDefaultExactlyOnce() {
        let stored = ["timeline", "nope", "habits", "habits"]
        let result = TodayLayoutEngine.sections(storedOrder: stored)
        XCTAssertEqual(result.count, TodaySection.allCases.count)
        XCTAssertEqual(Set(result), Set(TodaySection.allCases))
    }

    // MARK: - Hidden

    func test_visibleSections_hiddenSections_areSkipped() {
        let visible = TodayLayoutEngine.visibleSections(storedOrder: [], hidden: ["weeklyRecap", "explore"])
        XCTAssertFalse(visible.contains(.weeklyRecap))
        XCTAssertFalse(visible.contains(.explore))
        XCTAssertEqual(visible.count, TodaySection.allCases.count - 2)
    }

    func test_visibleSections_unknownHiddenId_isIgnored() {
        let visible = TodayLayoutEngine.visibleSections(storedOrder: [], hidden: ["retiredSection"])
        XCTAssertEqual(visible, TodaySection.allCases)
    }

    func test_visibleSections_newSection_isShownByDefault() {
        let defaults: [TodaySection] = [.atAGlance, .habits, .timeline]
        let visible = TodayLayoutEngine.visibleSections(
            storedOrder: ["habits", "atAGlance"],
            hidden: ["atAGlance"],
            defaults: defaults
        )
        XCTAssertEqual(visible, [.habits, .timeline])
    }

    // MARK: - TodayLayout edits

    func test_move_persistsFullResolvedOrder() {
        var layout = TodayLayout.default
        layout.move(fromOffsets: IndexSet(integer: 0), toOffset: TodaySection.allCases.count)
        XCTAssertEqual(layout.order.count, TodaySection.allCases.count)
        XCTAssertEqual(layout.sections.last, TodaySection.allCases.first)
    }

    func test_setHidden_togglesWithoutDuplicates() {
        var layout = TodayLayout.default
        layout.setHidden(.habits, true)
        layout.setHidden(.habits, true)
        XCTAssertEqual(layout.hidden, ["habits"])
        XCTAssertTrue(layout.isHidden(.habits))
        XCTAssertFalse(layout.visibleSections.contains(.habits))

        layout.setHidden(.habits, false)
        XCTAssertFalse(layout.isHidden(.habits))
        XCTAssertEqual(layout, .default)
    }

    func test_hiddenSection_keepsItsPlaceInOrder() {
        var layout = TodayLayout.default
        layout.setHidden(.doses, true)
        XCTAssertEqual(layout.sections, TodaySection.allCases)
    }

    // MARK: - Persistence

    func test_decode_profileWithoutTodayLayout_usesDefault() throws {
        let json = #"{"name":"A","goals":[],"memberSince":0,"healthConnected":false}"#
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data(json.utf8))
        XCTAssertEqual(profile.todayLayout, .default)
    }

    func test_decode_layoutFromNewerBuild_keepsUnknownIdsOutOfSections() throws {
        let json = #"{"order":["futureSection","timeline"],"hidden":["futureSection"]}"#
        let layout = try JSONDecoder().decode(TodayLayout.self, from: Data(json.utf8))
        XCTAssertEqual(layout.sections.first, .timeline)
        XCTAssertFalse(layout.sections.map(\.rawValue).contains("futureSection"))
    }

    func test_decode_layoutMissingKeys_isDefault() throws {
        let layout = try JSONDecoder().decode(TodayLayout.self, from: Data("{}".utf8))
        XCTAssertEqual(layout, .default)
    }

    func test_rawValues_areUniqueAndStable() {
        XCTAssertEqual(Set(TodaySection.allCases.map(\.rawValue)).count, TodaySection.allCases.count)
        XCTAssertEqual(TodaySection.atAGlance.rawValue, "atAGlance")
        XCTAssertEqual(TodaySection.healthMonitor.rawValue, "healthMonitor")
    }
}
