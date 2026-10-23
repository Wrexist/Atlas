import XCTest
@testable import Peptide

@MainActor
final class ProtocolBuilderViewTests: XCTestCase {

    func test_selectablePeptides_protocolPeptideMissingFromCatalogue_staysSelectable() {
        let catalogue = [MockPeptides.bpc157]
        let fromOtherDevice = MockPeptides.tb500

        let selectable = ProtocolBuilderView.selectablePeptides(
            catalogue: catalogue,
            protocolPeptides: [MockPeptides.bpc157, fromOtherDevice]
        )

        XCTAssertEqual(selectable.map(\.id), [MockPeptides.bpc157.id, fromOtherDevice.id])
    }

    func test_selectablePeptides_noEditedProtocol_isTheCatalogue() {
        let catalogue = [MockPeptides.bpc157, MockPeptides.tb500]

        let selectable = ProtocolBuilderView.selectablePeptides(catalogue: catalogue, protocolPeptides: [])

        XCTAssertEqual(selectable.map(\.id), catalogue.map(\.id))
    }

    func test_suggestedName_twoPeptides_joinsAbbreviations() {
        let name = ProtocolBuilderView.suggestedName(for: [MockPeptides.bpc157, MockPeptides.tb500])

        XCTAssertEqual(name, "BPC-157 + TB-500")
    }

    func test_suggestedName_moreThanThreePeptides_countsTheRest() {
        let peptides = [MockPeptides.bpc157, MockPeptides.tb500, MockPeptides.igf1lr3, MockPeptides.bpc157]

        let name = ProtocolBuilderView.suggestedName(for: peptides)

        XCTAssertEqual(name, "BPC-157 + TB-500 + IGF-1 LR3 +1")
    }

    func test_suggestedName_noPeptides_fallsBackToGenericName() {
        XCTAssertFalse(ProtocolBuilderView.suggestedName(for: []).isEmpty)
    }
}
