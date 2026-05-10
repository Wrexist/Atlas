import XCTest
@testable import Peptide

@MainActor
final class VialInventoryTests: XCTestCase {

    private func makeStore() -> DataStore {
        DataStore(seedSampleData: false)
    }

    private func makePeptide() -> Peptide {
        Peptide(
            name: "BPC-157",
            abbreviation: "BPC-157",
            category: .recovery,
            description: "",
            benefits: [],
            dosageRange: "200-500 mcg",
            frequency: "1x daily",
            halfLife: "4h",
            adminRoute: "SubQ",
            researchLinks: [],
            imageSystemName: "flask.fill"
        )
    }

    private func makeProtocol(with peptide: Peptide) -> PeptideProtocol {
        PeptideProtocol(
            id: UUID(),
            name: "Recovery",
            peptides: [peptide],
            schedule: ProtocolSchedule(daysOfWeek: [1, 2, 3, 4, 5, 6, 7], timesPerDay: 1, preferredTimes: ["8:00 AM"]),
            cycleLengthWeeks: 4,
            startDate: Date(),
            status: .active,
            notes: ""
        )
    }

    /// Brand-new shelf with no logged doses should render full vials —
    /// 1.0 not 0 — so the user doesn't open the app and see empty
    /// vials before they've taken anything.
    func test_liquidLevel_withZeroEntries_returnsFull() {
        let store = makeStore()
        let peptide = makePeptide()
        XCTAssertEqual(store.liquidLevel(for: peptide), 1.0, accuracy: 0.001)
    }

    /// Mid-vial: 10 logged doses out of 30 → 2/3 remaining.
    func test_liquidLevel_drainsLinearlyWithDoses() {
        let store = makeStore()
        let peptide = makePeptide()
        let proto = makeProtocol(with: peptide)
        store.addProtocol(proto)

        for _ in 0..<10 {
            store.entries.append(makeEntry(for: peptide, in: proto))
        }
        XCTAssertEqual(store.liquidLevel(for: peptide), 1.0 - 10.0 / 30.0, accuracy: 0.001)
    }

    /// Crossing the vial boundary should re-fill the visual rather
    /// than show 0 — the next dose drains a fresh vial from full.
    func test_liquidLevel_atVialBoundary_resetsToFull() {
        let store = makeStore()
        let peptide = makePeptide()
        let proto = makeProtocol(with: peptide)
        store.addProtocol(proto)

        for _ in 0..<DataStore.defaultDosesPerVial {
            store.entries.append(makeEntry(for: peptide, in: proto))
        }
        XCTAssertEqual(store.liquidLevel(for: peptide), 1.0, accuracy: 0.001)
    }

    /// A second vial in progress: 35 doses → wraps to 5/30 consumed.
    func test_liquidLevel_pastFirstVial_reflectsModuloRemainder() {
        let store = makeStore()
        let peptide = makePeptide()
        let proto = makeProtocol(with: peptide)
        store.addProtocol(proto)

        for _ in 0..<35 {
            store.entries.append(makeEntry(for: peptide, in: proto))
        }
        XCTAssertEqual(store.liquidLevel(for: peptide), 1.0 - 5.0 / 30.0, accuracy: 0.001)
    }

    /// Floor clamp: even at 29 doses the meniscus stays visible —
    /// the 0.05 minimum keeps the liquid-fill rectangle from
    /// disappearing entirely.
    func test_liquidLevel_neverDropsBelowFloor() {
        let store = makeStore()
        let peptide = makePeptide()
        let proto = makeProtocol(with: peptide)
        store.addProtocol(proto)

        for _ in 0..<29 {
            store.entries.append(makeEntry(for: peptide, in: proto))
        }
        XCTAssertGreaterThanOrEqual(store.liquidLevel(for: peptide), 0.05)
    }

    private func makeEntry(for peptide: Peptide, in proto: PeptideProtocol) -> ProtocolEntry {
        ProtocolEntry(
            id: UUID(),
            protocolId: proto.id,
            peptide: peptide,
            date: Date(),
            dose: "200 mcg",
            notes: "",
            completed: true
        )
    }
}
