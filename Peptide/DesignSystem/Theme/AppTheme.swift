import SwiftUI

enum AppThemeColor: String, CaseIterable, Codable, Identifiable {
    case forest
    case ocean
    case amethyst
    case sunset
    case rose
    case cyan

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .forest: "Forest"
        case .ocean: "Ocean"
        case .amethyst: "Amethyst"
        case .sunset: "Sunset"
        case .rose: "Rose"
        case .cyan: "Cyan"
        }
    }

    var primary: Color {
        switch self {
        case .forest: Color(hex: 0x4A7C59)
        case .ocean: Color(hex: 0x3B82C4)
        case .amethyst: Color(hex: 0x8B5CF6)
        case .sunset: Color(hex: 0xE07A3C)
        case .rose: Color(hex: 0xE85A8C)
        case .cyan: Color(hex: 0x14B8A6)
        }
    }

    var light: Color {
        switch self {
        case .forest: Color(hex: 0x6BAF7E)
        case .ocean: Color(hex: 0x60A5E8)
        case .amethyst: Color(hex: 0xA78BFA)
        case .sunset: Color(hex: 0xF2A062)
        case .rose: Color(hex: 0xFB7FA9)
        case .cyan: Color(hex: 0x2DD4BF)
        }
    }

    var dark: Color {
        switch self {
        case .forest: Color(hex: 0x3A6247)
        case .ocean: Color(hex: 0x2563A0)
        case .amethyst: Color(hex: 0x6D44C7)
        case .sunset: Color(hex: 0xB85C28)
        case .rose: Color(hex: 0xC04372)
        case .cyan: Color(hex: 0x0E8C7C)
        }
    }

    var highlight: Color {
        switch self {
        case .forest: Color(hex: 0xC8D8C0)
        case .ocean: Color(hex: 0xC0D4E8)
        case .amethyst: Color(hex: 0xD8CCF2)
        case .sunset: Color(hex: 0xF5D4B8)
        case .rose: Color(hex: 0xF8CCDC)
        case .cyan: Color(hex: 0xC0EDE6)
        }
    }
}

@Observable
final class ThemeManager: @unchecked Sendable {
    static let shared = ThemeManager()

    private static let defaultsKey = "appThemeColor"

    var theme: AppThemeColor {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Self.defaultsKey)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        self.theme = AppThemeColor(rawValue: raw) ?? .forest
    }
}
