import Foundation

enum PeptideCategory: String, CaseIterable, Identifiable, Codable {
    case growth
    case recovery
    case cognitive
    case antiAging
    case immune
    case metabolic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .growth: "Growth"
        case .recovery: "Recovery"
        case .cognitive: "Cognitive"
        case .antiAging: "Anti-Aging"
        case .immune: "Immune"
        case .metabolic: "Metabolic"
        }
    }

    var iconName: String {
        switch self {
        case .growth: "arrow.up.right.circle.fill"
        case .recovery: "heart.circle.fill"
        case .cognitive: "brain.head.profile.fill"
        case .antiAging: "sparkles"
        case .immune: "shield.checkered"
        case .metabolic: "flame.fill"
        }
    }
}
