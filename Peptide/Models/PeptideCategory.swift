import Foundation

enum PeptideCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case growth
    case recovery
    case cognitive
    case antiAging
    case immune
    case metabolic
    /// Fallback bucket for peptides whose category is unrecognized.
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .growth: "Growth"
        case .recovery: "Recovery"
        case .cognitive: "Cognitive"
        case .antiAging: "Anti-Aging"
        case .immune: "Immune"
        case .metabolic: "Metabolic"
        case .other: "Other"
        }
    }
    // The localized title for UI lives in DesignSystem/Theme/ModelLocalization.swift
    // so the Model layer stays free of a SwiftUI dependency.

    var iconName: String {
        switch self {
        case .growth: "arrow.up.right.circle.fill"
        case .recovery: "heart.circle.fill"
        case .cognitive: "brain.head.profile.fill"
        case .antiAging: "sparkles"
        case .immune: "shield.checkered"
        case .metabolic: "flame.fill"
        case .other: "square.grid.2x2.fill"
        }
    }
}
