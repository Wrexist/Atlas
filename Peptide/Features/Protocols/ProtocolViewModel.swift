import SwiftUI

@Observable
final class ProtocolViewModel {
    var protocols = MockProtocols.all
    var showingBuilder = false
    var selectedProtocol: PeptideProtocol?

    var activeProtocols: [PeptideProtocol] {
        protocols.filter { $0.status == .active }
    }

    var pausedProtocols: [PeptideProtocol] {
        protocols.filter { $0.status == .paused }
    }

    var completedProtocols: [PeptideProtocol] {
        protocols.filter { $0.status == .completed }
    }

    func entriesFor(_ protocol_: PeptideProtocol) -> [ProtocolEntry] {
        MockEntries.generateEntries(for: protocol_, days: 14)
    }
}
