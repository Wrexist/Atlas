import Foundation

struct ProtocolEntry: Identifiable, Hashable, Codable, Sendable {
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

    // Equality and hash intentionally fold in the mutable `completed`
    // flag so value-equality reflects completion state (SwiftUI sees a
    // toggle as a change). HAZARD: because `completed` is a `var` that
    // participates in `hash(into:)`, a ProtocolEntry must never be stored
    // in a `Set` or used as a dictionary key — mutating `completed` would
    // change its hash and orphan it in the bucket. Today every use site
    // holds `[ProtocolEntry]` arrays, which is safe; keep it that way.
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

    /// Localized label for display; `rawValue` is the persisted value.
    var displayName: LocalizedStringResource {
        switch self {
        case .leftDeltoid: return "Left Deltoid"
        case .rightDeltoid: return "Right Deltoid"
        case .leftAbdomen: return "Left Abdomen"
        case .rightAbdomen: return "Right Abdomen"
        case .leftThigh: return "Left Thigh"
        case .rightThigh: return "Right Thigh"
        case .leftGlute: return "Left Glute"
        case .rightGlute: return "Right Glute"
        }
    }
}
