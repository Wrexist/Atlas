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

    private var defaultVisible: [TodaySection] {
        TodaySection.allCases.filter(\.isShownByDefault)
    }

    func test_visibleSections_freshLayout_showsOnlyDefaultSections() {
        let visible = TodayLayoutEngine.visibleSections(storedOrder: [], hidden: [])
        XCTAssertEqual(visible, defaultVisible)
        XCTAssertEqual(visible.first, .coaching)
        XCTAssertFalse(visible.contains(.healthMonitor))
        XCTAssertFalse(visible.contains(.timeline))
    }

    func test_visibleSections_hiddenSections_areSkipped() {
        let visible = TodayLayoutEngine.visibleSections(storedOrder: [], hidden: ["weeklyRecap", "habits"])
        XCTAssertFalse(visible.contains(.weeklyRecap))
        XCTAssertFalse(visible.contains(.habits))
        XCTAssertEqual(visible.count, defaultVisible.count - 2)
    }

    func test_visibleSections_unknownHiddenId_isIgnored() {
        let visible = TodayLayoutEngine.visibleSections(storedOrder: [], hidden: ["retiredSection"])
        XCTAssertEqual(visible, defaultVisible)
    }

    func test_visibleSections_shownExtra_appearsInItsOrderSlot() {
        let visible = TodayLayoutEngine.visibleSections(storedOrder: [], hidden: [], shownExtras: ["timeline"])
        XCTAssertEqual(visible, TodaySection.allCases.filter { $0.isShownByDefault || $0 == .timeline })
    }

    func test_visibleSections_extraInHiddenOnly_staysOff() {
        // A layout saved before opt-in sections existed lists only what
        // the user hid; an extra it never hid still starts off.
        let visible = TodayLayoutEngine.visibleSections(storedOrder: [], hidden: ["doses"])
        XCTAssertFalse(visible.contains(.explore))
        XCTAssertFalse(visible.contains(.doses))
    }

    func test_visibleSections_newSection_isShownByDefault() {
        let defaults: [TodaySection] = [.atAGlance, .habits, .checklist]
        let visible = TodayLayoutEngine.visibleSections(
            storedOrder: ["habits", "atAGlance"],
            hidden: ["atAGlance"],
            defaults: defaults
        )
        XCTAssertEqual(visible, [.habits, .checklist])
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

    func test_setHidden_extraSection_togglesShownExtras() {
        var layout = TodayLayout.default
        XCTAssertTrue(layout.isHidden(.timeline))

        layout.setHidden(.timeline, false)
        layout.setHidden(.timeline, false)
        XCTAssertEqual(layout.shownExtras, ["timeline"])
        XCTAssertTrue(layout.hidden.isEmpty)
        XCTAssertTrue(layout.visibleSections.contains(.timeline))

        layout.setHidden(.timeline, true)
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
        XCTAssertEqual(layout.sections, TodayLayoutEngine.sections(storedOrder: ["timeline"]))
        XCTAssertEqual(layout.visibleSections, layout.sections.filter(\.isShownByDefault))
        XCTAssertFalse(layout.sections.map(\.rawValue).contains("futureSection"))
    }

    func test_decode_layoutFromOlderBuild_hasNoExtrasAndRoundTrips() throws {
        let json = #"{"order":[],"hidden":["habits"]}"#
        let layout = try JSONDecoder().decode(TodayLayout.self, from: Data(json.utf8))
        XCTAssertTrue(layout.shownExtras.isEmpty)
        XCTAssertFalse(layout.visibleSections.contains(.habits))

        var withExtra = layout
        withExtra.setHidden(.steps, false)
        let decoded = try JSONDecoder().decode(TodayLayout.self, from: JSONEncoder().encode(withExtra))
        XCTAssertEqual(decoded, withExtra)
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
