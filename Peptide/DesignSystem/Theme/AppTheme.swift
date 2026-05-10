import SwiftUI

/// Brand color identities surfaced on the onboarding "Make it yours"
/// step and reapplied across the app via `AppColor.accent*`. The first
/// case (`purpleGradient`) is the brand default; its `primary` / `light`
/// pair are the two stops of the marketing purple→pink gradient — every
/// `LinearGradient(colors: [primary, light])` site in the app renders
/// as that gradient automatically without per-site changes.
enum AppThemeColor: String, CaseIterable, Codable, Identifiable {
    case purpleGradient
    case ocean
    case teal
    case amber
    case onyx

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .purpleGradient: "Iris"
        case .ocean: "Ocean"
        case .teal: "Teal"
        case .amber: "Amber"
        case .onyx: "Onyx"
        }
    }

    var primary: Color {
        switch self {
        case .purpleGradient: Color(hex: 0x7F77DD)
        case .ocean: Color(hex: 0x378ADD)
        case .teal: Color(hex: 0x1D9E75)
        case .amber: Color(hex: 0xBA7517)
        case .onyx: Color(hex: 0x2C2C2A)
        }
    }

    /// Second stop for the marketing gradient. For solid-colour themes
    /// it's a slightly lifted version of `primary` so the existing
    /// `[primary, light]` gradient sites still produce a tasteful sheen.
    var light: Color {
        switch self {
        case .purpleGradient: Color(hex: 0xD4537E)
        case .ocean: Color(hex: 0x6CA9E6)
        case .teal: Color(hex: 0x35BC91)
        case .amber: Color(hex: 0xD89438)
        case .onyx: Color(hex: 0x4A4A48)
        }
    }

    var dark: Color {
        switch self {
        case .purpleGradient: Color(hex: 0x534B96)
        case .ocean: Color(hex: 0x256AAA)
        case .teal: Color(hex: 0x167A5A)
        case .amber: Color(hex: 0x8E5A12)
        case .onyx: Color(hex: 0x1A1A18)
        }
    }

    var highlight: Color {
        switch self {
        case .purpleGradient: Color(hex: 0xE8D2E2)
        case .ocean: Color(hex: 0xC4DCF1)
        case .teal: Color(hex: 0xC0E8D8)
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
        default: return .purpleGradient
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
