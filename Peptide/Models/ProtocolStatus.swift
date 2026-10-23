import Foundation

enum ProtocolStatus: String, CaseIterable, Identifiable, Codable, Sendable {
    case active
    case paused
    case completed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .active: String(localized: "Active")
        case .paused: String(localized: "Paused")
        case .completed: String(localized: "Completed")
        }
    }

    var iconName: String {
        switch self {
        case .active: "circle.fill"
        case .paused: "pause.circle.fill"
        case .completed: "checkmark.circle.fill"
        }
    }
}
