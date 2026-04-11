import SwiftUI

enum ProtocolStatus: String, CaseIterable, Identifiable, Codable {
    case active
    case paused
    case completed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .active: "Active"
        case .paused: "Paused"
        case .completed: "Completed"
        }
    }

    var color: Color {
        switch self {
        case .active: AppColor.accentPrimary
        case .paused: AppColor.warning
        case .completed: AppColor.textTertiary
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
