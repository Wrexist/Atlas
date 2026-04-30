import XCTest
@testable import Peptide

final class DailyScheduleEngineTests: XCTestCase {

    // MARK: - Helpers

    private func peptide(_ abbrev: String) -> Peptide {
        if let match = PeptideDatabase.shared.first(where: { $0.abbreviation == abbrev }) {
            return match
        }
        return Peptide(
            name: abbrev,
            abbreviation: abbrev,
            category: .other,
            description: "",
            benefits: [],
            dosageRange: "",
            frequency: "",
            halfLife: "",
            adminRoute: "",
            researchLinks: [],
            imageSystemName: "flask.fill"
        )
    }

    private func entry(
        _ abbrev: String,
        hour: Int,
        minute: Int = 0,
        completed: Bool = false
    ) -> ProtocolEntry {
        let date = Calendar.current.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: Date()
        ) ?? Date()
        return ProtocolEntry(
            id: UUID(),
            protocolId: UUID(),
            peptide: peptide(abbrev),
            date: date,
            dose: "100 mcg",
            notes: "",
            completed: completed
        )
    }

    // MARK: - Empty state

    func test_plan_emptyEntries_returnsEmptyPlan() {
        let plan = DailyScheduleEngine.plan(for: [])
        XCTAssertEqual(plan.totalDoses, 0)
        XCTAssertTrue(plan.slots.isEmpty)
        XCTAssertFalse(plan.hasAny)
    }

    // MARK: - Slot classification

    func test_plan_groupsBpc157IntoMorningFastedSlot() {
        let plan = DailyScheduleEngine.plan(for: [entry("BPC-157", hour: 7)])
        XCTAssertEqual(plan.slots.count, 1)
        XCTAssertEqual(plan.slots.first?.slot, .morningFasted)
        XCTAssertEqual(plan.slots.first?.doses.count, 1)
    }

    func test_plan_routesEpitalonToPreBed() {
        let plan = DailyScheduleEngine.plan(for: [entry("Epitalon", hour: 22)])
        XCTAssertEqual(plan.slots.first?.slot, .preBed)
    }

    func test_plan_classifiesUnknownPeptideByClockHour() {
        let plan = DailyScheduleEngine.plan(for: [entry("UnknownXYZ", hour: 13)])
        XCTAssertEqual(plan.slots.first?.slot, .midday)
    }

    // MARK: - Ordering

    func test_plan_putsFastedPeptideFirstWithinSlot() {
        // BPC-157 is fasted/morning. AOD-9604 is also fasted (must be fasted).
        // Use a non-fasted morning peptide alongside one to verify ordering.
        let entries = [
            entry("Semax", hour: 7, minute: 30),  // morningFasted, but its note doesn't say "fasted"
            entry("AOD-9604", hour: 7, minute: 0) // explicitly fasted
        ]
        let plan = DailyScheduleEngine.plan(for: entries)
        guard let firstSlot = plan.slots.first else {
            return XCTFail("Expected at least one slot")
        }
        XCTAssertEqual(firstSlot.doses.first?.entry.peptide.abbreviation, "AOD-9604",
                       "Fasted-required peptide should be first within the slot")
        XCTAssertTrue(firstSlot.doses.first?.mustBeFasted == true)
    }

    func test_plan_ordersGhrhBeforeGhrpInSameSlot() {
        let entries = [
            entry("Ipamorelin", hour: 22),
            entry("CJC-1295 DAC", hour: 22)
        ]
        let plan = DailyScheduleEngine.plan(for: entries)
        let preBed = plan.slots.first { $0.slot == .preBed }
        XCTAssertNotNil(preBed)
        XCTAssertEqual(preBed?.doses.first?.entry.peptide.abbreviation, "CJC-1295 DAC",
                       "GHRH analog should land before its GHRP partner")
    }

    func test_plan_ordersAcrossSlots_morningBeforePreBed() {
        let entries = [
            entry("Epitalon", hour: 22),    // pre-bed
            entry("BPC-157", hour: 7)       // morning fasted
        ]
        let plan = DailyScheduleEngine.plan(for: entries)
        XCTAssertEqual(plan.slots.first?.slot, .morningFasted)
        XCTAssertEqual(plan.slots.last?.slot, .preBed)
    }

    func test_plan_assignsSequentialOrderWithinSlot() {
        let entries = [
            entry("CJC-1295 DAC", hour: 22),
            entry("Ipamorelin", hour: 22),
            entry("Epitalon", hour: 22)
        ]
        let plan = DailyScheduleEngine.plan(for: entries)
        let preBed = plan.slots.first { $0.slot == .preBed }
        XCTAssertEqual(preBed?.doses.map(\.order), [1, 2, 3])
    }

    // MARK: - Combinations

    func test_plan_detectsValidatedStack_cjcIpamorelin() {
        let entries = [
            entry("CJC-1295 DAC", hour: 22),
            entry("Ipamorelin", hour: 22)
        ]
        let plan = DailyScheduleEngine.plan(for: entries)
        let preBed = plan.slots.first { $0.slot == .preBed }
        let cjc = preBed?.doses.first { $0.entry.peptide.abbreviation == "CJC-1295 DAC" }
        XCTAssertNotNil(cjc)
        XCTAssertTrue(
            cjc?.combinations.contains(where: { $0.withAbbreviation == "Ipamorelin" }) == true,
            "CJC-1295 DAC should propose co-injection with Ipamorelin"
        )
    }

    func test_plan_detectsBpc157TB500Synergy() {
        let entries = [
            entry("BPC-157", hour: 7),
            entry("TB-500", hour: 7)
        ]
        let plan = DailyScheduleEngine.plan(for: entries)
        let dose = plan.slots
            .flatMap(\.doses)
            .first { $0.entry.peptide.abbreviation == "BPC-157" }
        XCTAssertTrue(
            dose?.combinations.contains(where: { $0.withAbbreviation == "TB-500" }) == true,
            "Wolverine stack synergy should be surfaced"
        )
    }

    // MARK: - Conflicts

    func test_plan_flagsIntranasalSpacing_semaxSelank() {
        let entries = [
            entry("Semax", hour: 7),
            entry("Selank", hour: 7)
        ]
        let plan = DailyScheduleEngine.plan(for: entries)
        let semax = plan.slots
            .flatMap(\.doses)
            .first { $0.entry.peptide.abbreviation == "Semax" }
        XCTAssertNotNil(semax)
        XCTAssertTrue(
            semax?.conflicts.contains(where: { $0.title.contains("Selank") }) == true,
            "Semax should warn about spacing from Selank"
        )
    }

    func test_plan_flagsSamePathway_ghsR_ipamorelinHexarelin() {
        let entries = [
            entry("Ipamorelin", hour: 22),
            entry("Hexarelin", hour: 22)
        ]
        let plan = DailyScheduleEngine.plan(for: entries)
        let dose = plan.slots
            .flatMap(\.doses)
            .first { $0.entry.peptide.abbreviation == "Ipamorelin" }
        XCTAssertNotNil(dose)
        XCTAssertFalse(
            dose?.conflicts.isEmpty == true,
            "Ipamorelin + Hexarelin must surface a same-pathway conflict"
        )
    }

    func test_plan_flagsGlp1Stacking() {
        let entries = [
            entry("Semaglutide", hour: 9),
            entry("Tirzepatide", hour: 9)
        ]
        let plan = DailyScheduleEngine.plan(for: entries)
        let conflictsExist = plan.slots
            .flatMap(\.doses)
            .contains { dose in
                !dose.conflicts.isEmpty && dose.entry.peptide.abbreviation == "Semaglutide"
            }
        XCTAssertTrue(conflictsExist, "Stacking two GLP-1s should produce a conflict")
    }

    // MARK: - Plan summary

    func test_dailyPlan_summary_includesCounts() {
        let entries = [
            entry("CJC-1295 DAC", hour: 22),
            entry("Ipamorelin", hour: 22)
        ]
        let plan = DailyScheduleEngine.plan(for: entries)
        XCTAssertGreaterThanOrEqual(plan.combinationCount, 1)
        XCTAssertTrue(plan.summary.contains("2 doses"))
    }

    func test_dailyPlan_headline_promptsFastedPeptideFirst() {
        let plan = DailyScheduleEngine.plan(for: [entry("BPC-157", hour: 7)])
        XCTAssertTrue(plan.headline.contains("BPC-157"))
        XCTAssertTrue(plan.headline.lowercased().contains("fasted"))
    }
}
