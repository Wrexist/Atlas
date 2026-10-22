import CryptoKit
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

    /// True once the user has logged anything against this dose.
    var isLogged: Bool {
        completed || actualDose != nil || !notes.isEmpty
    }

    /// The id of a scheduled dose, derived from its slot — protocol,
    /// peptide and local wall-clock minute — so every device that
    /// generates today's doses produces the same rows, and a sync
    /// converges on one dose instead of showing each twice.
    static func scheduledID(protocolId: UUID, peptideId: UUID, date: Date, calendar: Calendar) -> UUID {
        let slot = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let key = [
            protocolId.uuidString, peptideId.uuidString,
            "\(slot.year ?? 0)-\(slot.month ?? 0)-\(slot.day ?? 0)T\(slot.hour ?? 0):\(slot.minute ?? 0)",
        ].joined(separator: "|")
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50   // name-based version
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
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
