import Foundation

struct ProtocolEntry: Identifiable, Hashable {
    let id: UUID
    let protocolId: UUID
    let peptide: Peptide
    let date: Date
    let dose: String
    let notes: String
    var completed: Bool

    static func == (lhs: ProtocolEntry, rhs: ProtocolEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
