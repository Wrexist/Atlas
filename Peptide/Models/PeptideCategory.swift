import SwiftUI

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

    var color: Color {
        switch self {
        case .growth: Color(hex: 0x4A7C59)
        case .recovery: Color(hex: 0x5B8FB9)
        case .cognitive: Color(hex: 0x9B72CF)
        case .antiAging: Color(hex: 0xD4A844)
        case .immune: Color(hex: 0xCF7272)
        case .metabolic: Color(hex: 0xE88D4F)
        }
    }
}
