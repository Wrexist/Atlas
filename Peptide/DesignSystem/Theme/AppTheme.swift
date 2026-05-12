import SwiftUI

/// Brand color identities surfaced on the onboarding "Make it yours"
/// step and reapplied across the app via `AppColor.accent*`. The first
/// case (`.teal`) is the brand default — a refined emerald→cyan pair
/// that renders every `LinearGradient(colors: [primary, light])` site
/// in the app as the signature green-to-cool-cyan gradient.
enum AppThemeColor: String, CaseIterable, Codable, Identifiable {
    case teal
    case purpleGradient
    case ocean
    case amber
    case onyx

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .teal: "Emerald"
        case .purpleGradient: "Iris"
        case .ocean: "Ocean"
        case .amber: "Amber"
        case .onyx: "Graphite"
        }
    }

    var primary: Color {
        switch self {
        case .teal: Color(hex: 0x10B981)          // emerald-500
        case .purpleGradient: Color(hex: 0x7F77DD)
        case .ocean: Color(hex: 0x378ADD)
        case .amber: Color(hex: 0xBA7517)
        case .onyx: Color(hex: 0x3F3F3D)
        }
    }

    /// Second stop for the marketing gradient. For the default emerald
    /// theme this is a cool cyan partner so every `[primary, light]`
    /// gradient renders as a green→cyan sweep without per-site changes.
    var light: Color {
        switch self {
        case .teal: Color(hex: 0x22D3EE)          // cyan-400
        case .purpleGradient: Color(hex: 0xD4537E)
        case .ocean: Color(hex: 0x6CA9E6)
        case .amber: Color(hex: 0xD89438)
        case .onyx: Color(hex: 0x5C5C5A)
        }
    }

    var dark: Color {
        switch self {
        case .teal: Color(hex: 0x047857)          // emerald-700
        case .purpleGradient: Color(hex: 0x534B96)
        case .ocean: Color(hex: 0x256AAA)
        case .amber: Color(hex: 0x8E5A12)
        case .onyx: Color(hex: 0x1F1F1D)
        }
    }

    var highlight: Color {
        switch self {
        case .teal: Color(hex: 0xA7F3D0)          // emerald-200
        case .purpleGradient: Color(hex: 0xE8D2E2)
        case .ocean: Color(hex: 0xC4DCF1)
        case .amber: Color(hex: 0xF1D8B0)
        case .onyx: Color(hex: 0xC9C9C7)
        }
    }

    /// Maps a UserDefaults rawValue to a current case, including the
    /// 6-theme palette this replaces (`forest`, `amethyst`, `sunset`,
    /// `rose`, `cyan`). Unknown values fall back to the brand default.
    static func resolving(rawValue: String) -> AppThemeColor {
        if let direct = AppThemeColor(rawValue: rawValue) { return direct }
        switch rawValue {
        case "forest", "cyan": return .teal
        case "amethyst", "rose": return .purpleGradient
        case "sunset": return .amber
        default: return .teal
        }
    }
}

enum DisplayMode: String, Codable, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var preferredScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }
}

@Observable
final class ThemeManager: @unchecked Sendable {
    static let shared = ThemeManager()

    private static let colorKey = "appThemeColor"
    private static let displayModeKey = "appDisplayMode"

    var theme: AppThemeColor {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Self.colorKey)
        }
    }

    /// Persisted display-mode preference. The current build keeps the app
    /// pinned to dark — every surface uses dark hexes, every component
    /// preview is dark — so flipping this to `.light` will make panels
    /// hard to read until the design system gains light-mode variants.
    /// Stored anyway so the onboarding choice survives the upgrade.
    var displayMode: DisplayMode {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: Self.displayModeKey)
        }
    }

    private init() {
        let rawColor = UserDefaults.standard.string(forKey: Self.colorKey) ?? ""
        self.theme = AppThemeColor.resolving(rawValue: rawColor)

        let rawMode = UserDefaults.standard.string(forKey: Self.displayModeKey) ?? ""
        self.displayMode = DisplayMode(rawValue: rawMode) ?? .dark
    }
}
