import XCTest
@testable import Peptide

final class StackAdjustmentEngineTests: XCTestCase {

    // MARK: - Test peptide factory

    private func peptide(
        id: UUID = UUID(),
        abbr: String,
        sideEffects: [String] = []
    ) -> Peptide {
        Peptide(
            id: id,
            name: abbr,
            abbreviation: abbr,
            category: .recovery,
            description: "test",
            benefits: [],
            dosageRange: "100mcg",
            frequency: "daily",
            halfLife: "1h",
            adminRoute: "Subcutaneous",
            researchLinks: [],
            imageSystemName: "circle",
            sideEffects: sideEffects
        )
    }

    private func makeProtocol(
        id: UUID = UUID(),
        name: String,
        peptides: [Peptide],
        status: ProtocolStatus = .active
    ) -> PeptideProtocol {
        PeptideProtocol(
            id: id,
            name: name,
            peptides: peptides,
            schedule: ProtocolSchedule(daysOfWeek: [1, 2, 3, 4, 5], timesPerDay: 1, preferredTimes: ["8:00 AM"]),
            cycleLengthWeeks: 8,
            startDate: Date(),
            status: status,
            notes: ""
        )
    }

    // MARK: - sideEffectKey

    func test_sideEffectKey_parsesCompoundingWarningTitle() {
        XCTAssertEqual(
            StackAdjustmentEngine.sideEffectKey(from: #"Compounding "headache" risk"#),
            "headache"
        )
        XCTAssertEqual(
            StackAdjustmentEngine.sideEffectKey(from: #"Compounding "joint pain" risk"#),
            "joint pain"
        )
    }

    func test_sideEffectKey_returnsNilForNonCompoundingTitle() {
        XCTAssertNil(StackAdjustmentEngine.sideEffectKey(from: "Heavy Recovery focus"))
        XCTAssertNil(StackAdjustmentEngine.sideEffectKey(from: ""))
    }

    func test_sideEffectKey_returnsNilForEmptyQuotedKey() {
        XCTAssertNil(StackAdjustmentEngine.sideEffectKey(from: #"Compounding "" risk"#))
    }

    // MARK: - candidateProtocols ordering

    func test_candidateProtocols_orderedByOverlapCountDescending() {
        let bpc = peptide(abbr: "BPC-157")
        let tb = peptide(abbr: "TB-500")
        let cjc = peptide(abbr: "CJC-1295")

        let oneHit = makeProtocol(name: "One", peptides: [bpc])
        let twoHits = makeProtocol(name: "Two", peptides: [bpc, tb])
        let zeroHits = makeProtocol(name: "Other", peptides: [cjc])

        let ordered = StackAdjustmentEngine.candidateProtocols(
            affectedAbbreviations: ["BPC-157", "TB-500"],
            in: [oneHit, twoHits, zeroHits]
        )

        XCTAssertEqual(ordered.map(\.name), ["Two", "One"])
    }

    func test_candidateProtocols_filtersOutZeroOverlapProtocols() {
        let bpc = peptide(abbr: "BPC-157")
        let cjc = peptide(abbr: "CJC-1295")

        let unrelated = makeProtocol(name: "Unrelated", peptides: [cjc])

        let ordered = StackAdjustmentEngine.candidateProtocols(
            affectedAbbreviations: [bpc.abbreviation],
            in: [unrelated]
        )

        XCTAssertTrue(ordered.isEmpty)
    }

    // MARK: - diff

    func test_diff_emptyChange_returnsAllUnchanged() {
        let bpc = peptide(abbr: "BPC-157")
        let tb = peptide(abbr: "TB-500")
        let diff = StackAdjustmentEngine.diff(original: [bpc, tb], proposed: [bpc, tb])
        XCTAssertTrue(diff.added.isEmpty)
        XCTAssertTrue(diff.removed.isEmpty)
        XCTAssertEqual(diff.unchanged.map(\.abbreviation), ["BPC-157", "TB-500"])
        XCTAssertFalse(diff.hasChanges)
        XCTAssertEqual(diff.summary, "No changes yet")
    }

    func test_diff_addOnly_summaryReflectsAddCount() {
        let bpc = peptide(abbr: "BPC-157")
        let tb = peptide(abbr: "TB-500")
        let diff = StackAdjustmentEngine.diff(original: [bpc], proposed: [bpc, tb])
        XCTAssertEqual(diff.added.map(\.abbreviation), ["TB-500"])
        XCTAssertTrue(diff.removed.isEmpty)
        XCTAssertEqual(diff.summary, "Adding 1")
    }

    func test_diff_removeOnly_summaryReflectsRemoveCount() {
        let bpc = peptide(abbr: "BPC-157")
        let tb = peptide(abbr: "TB-500")
        let diff = StackAdjustmentEngine.diff(original: [bpc, tb], proposed: [bpc])
        XCTAssertTrue(diff.added.isEmpty)
        XCTAssertEqual(diff.removed.map(\.abbreviation), ["TB-500"])
        XCTAssertEqual(diff.summary, "Removing 1")
    }

    func test_diff_addAndRemove_summaryReportsBoth() {
        let bpc = peptide(abbr: "BPC-157")
        let tb = peptide(abbr: "TB-500")
        let cjc = peptide(abbr: "CJC-1295")
        let diff = StackAdjustmentEngine.diff(original: [bpc, tb], proposed: [bpc, cjc])
        XCTAssertEqual(diff.added.map(\.abbreviation), ["CJC-1295"])
        XCTAssertEqual(diff.removed.map(\.abbreviation), ["TB-500"])
        XCTAssertTrue(diff.hasChanges)
        XCTAssertEqual(diff.summary, "Adding 1, removing 1")
    }

    // MARK: - relocations

    func test_relocations_emptyRemoved_returnsEmpty() {
        let result = StackAdjustmentEngine.relocations(
            for: [],
            sourceProtocolId: UUID(),
            sideEffectKey: nil,
            in: []
        )
        XCTAssertTrue(result.isEmpty)
    }

    /// Every relocation must always end with a "createStack" + "discard" option,
    /// regardless of what other targets exist.
    func test_relocations_alwaysIncludesCreateStackAndDiscard() {
        let dropped = peptide(abbr: "BPC-157")
        let result = StackAdjustmentEngine.relocations(
            for: [dropped],
            sourceProtocolId: UUID(),
            sideEffectKey: nil,
            in: []
        )
        let firstOptions = result.first?.options ?? []
        let hasCreate = firstOptions.contains { if case .createStack = $0 { return true } else { return false } }
        let hasDiscard = firstOptions.contains { if case .discard = $0 { return true } else { return false } }
        XCTAssertTrue(hasCreate, "createStack option must be present")
        XCTAssertTrue(hasDiscard, "discard option must be present")
    }

    /// A target protocol that already shares the same compounding cluster (≥2
    /// existing peptides with the same side effect) should NOT be offered as a
    /// relocation home — moving there would just recreate the warning.
    func test_relocations_skipsProtocolsThatWouldRecreateCluster() {
        let dropped = peptide(abbr: "DropMe", sideEffects: ["headache"])
        let bp1 = peptide(abbr: "Bp1", sideEffects: ["headache"])
        let bp2 = peptide(abbr: "Bp2", sideEffects: ["headache"])

        let crowded = makeProtocol(name: "CrowdedHeadaches", peptides: [bp1, bp2])
        let sourceId = UUID()

        let result = StackAdjustmentEngine.relocations(
            for: [dropped],
            sourceProtocolId: sourceId,
            sideEffectKey: "headache",
            in: [crowded]
        )

        let firstOptions = result.first?.options ?? []
        let movedToCrowded = firstOptions.contains {
            if case .moveTo(let id, _, _) = $0 { return id == crowded.id }
            return false
        }
        XCTAssertFalse(movedToCrowded, "Should not offer to move into a protocol that already has 2+ matching side-effect peptides")
    }

    /// A target protocol with no overlap on the offending side effect should be
    /// offered — the move is genuinely safer.
    func test_relocations_offersCleanProtocolAsTarget() {
        let dropped = peptide(abbr: "DropMe", sideEffects: ["headache"])
        let clean = peptide(abbr: "Clean", sideEffects: ["fatigue"])

        let cleanProtocol = makeProtocol(name: "CleanStack", peptides: [clean])
        let sourceId = UUID()

        let result = StackAdjustmentEngine.relocations(
            for: [dropped],
            sourceProtocolId: sourceId,
            sideEffectKey: "headache",
            in: [cleanProtocol]
        )

        let firstOptions = result.first?.options ?? []
        let movedToClean = firstOptions.contains {
            if case .moveTo(let id, _, _) = $0 { return id == cleanProtocol.id }
            return false
        }
        XCTAssertTrue(movedToClean)
    }

    /// Inactive protocols are never offered as relocation targets.
    func test_relocations_skipsInactiveProtocols() {
        let dropped = peptide(abbr: "DropMe")
        let other = peptide(abbr: "Other")
        let paused = makeProtocol(name: "Paused", peptides: [other], status: .paused)

        let result = StackAdjustmentEngine.relocations(
            for: [dropped],
            sourceProtocolId: UUID(),
            sideEffectKey: nil,
            in: [paused]
        )

        let firstOptions = result.first?.options ?? []
        let hasMoveOption = firstOptions.contains {
            if case .moveTo = $0 { return true } else { return false }
        }
        XCTAssertFalse(hasMoveOption)
    }

    /// `recommended` is the first non-discard option.
    func test_relocation_recommended_prefersFirstNonDiscardOption() {
        let dropped = peptide(abbr: "DropMe")
        let result = StackAdjustmentEngine.relocations(
            for: [dropped],
            sourceProtocolId: UUID(),
            sideEffectKey: nil,
            in: []
        )
        guard let relocation = result.first else { return XCTFail("Expected one relocation") }
        if case .discard = relocation.recommended {
            XCTFail("recommended must not default to .discard when other options exist")
        }
    }
}
