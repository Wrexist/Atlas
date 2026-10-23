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
}
