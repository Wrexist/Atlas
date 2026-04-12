import Foundation

struct ProtocolEntry: Identifiable, Hashable, Codable {
    let id: UUID
    let protocolId: UUID
    let peptide: Peptide
    let date: Date
    let dose: String
    let notes: String
    var completed: Bool
    var actualDose: String?
    var actualTime: Date?
    var injectionSite: String?

    static func == (lhs: ProtocolEntry, rhs: ProtocolEntry) -> Bool {
        lhs.id == rhs.id && lhs.completed == rhs.completed
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(completed)
    }
}

enum InjectionSite: String, CaseIterable, Codable {
    case leftDeltoid = "Left Deltoid"
    case rightDeltoid = "Right Deltoid"
    case leftAbdomen = "Left Abdomen"
    case rightAbdomen = "Right Abdomen"
    case leftThigh = "Left Thigh"
    case rightThigh = "Right Thigh"
    case leftGlute = "Left Glute"
    case rightGlute = "Right Glute"
}
