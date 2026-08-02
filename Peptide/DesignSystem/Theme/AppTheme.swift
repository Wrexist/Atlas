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

    /// Four stops of one hue. Each carries a light-mode partner: the dark-mode
    /// hexes are the original brand values, and the light-mode ones are the
    /// same hue pushed deeper so accent *text* — `AppColor.accentLight` is
    /// used as ink in 150+ places — clears WCAG AA on a white card instead of
    /// washing out.
    private struct Ramp {
        let primary: Color
        let light: Color
        let dark: Color
        let highlight: Color
    }

    // Stored, not computed. `AppColor.accentPrimary` is read many times per
    // render pass, and each `Color(light:dark:)` allocates a UIColor with a
    // trait-resolving closure — cheap once, wasteful per frame.
    private static let tealRamp = Ramp(
        primary:   Color(light: 0x0A8F63, dark: 0x10B981),   // emerald-500
        light:     Color(light: 0x0E7490, dark: 0x22D3EE),   // cyan-400
        dark:      Color(light: 0x065F46, dark: 0x047857),   // emerald-700
        highlight: Color(light: 0x047857, dark: 0xA7F3D0)    // emerald-200
    )
    private static let purpleRamp = Ramp(
        primary:   Color(light: 0x5B52B8, dark: 0x7F77DD),
        light:     Color(light: 0xB03060, dark: 0xD4537E),
        dark:      Color(light: 0x3E3773, dark: 0x534B96),
        highlight: Color(light: 0x534B96, dark: 0xE8D2E2)
    )
    private static let oceanRamp = Ramp(
        primary:   Color(light: 0x1F6FC0, dark: 0x378ADD),
        light:     Color(light: 0x2F7FC8, dark: 0x6CA9E6),
        dark:      Color(light: 0x1A5386, dark: 0x256AAA),
        highlight: Color(light: 0x256AAA, dark: 0xC4DCF1)
    )
    private static let amberRamp = Ramp(
        primary:   Color(light: 0x9A6112, dark: 0xBA7517),
        light:     Color(light: 0xB07A1E, dark: 0xD89438),
        dark:      Color(light: 0x714810, dark: 0x8E5A12),
        highlight: Color(light: 0x8E5A12, dark: 0xF1D8B0)
    )
    /// Graphite already reads on either surface, so it's the one ramp whose
    /// first three stops don't shift between schemes.
    private static let onyxRamp = Ramp(
        primary:   Color(hex: 0x3F3F3D),
        light:     Color(hex: 0x5C5C5A),
        dark:      Color(hex: 0x1F1F1D),
        highlight: Color(light: 0x3F3F3D, dark: 0xC9C9C7)
    )

    private var ramp: Ramp {
        switch self {
        case .teal: Self.tealRamp
        case .purpleGradient: Self.purpleRamp
        case .ocean: Self.oceanRamp
        case .amber: Self.amberRamp
        case .onyx: Self.onyxRamp
        }
    }

    var primary: Color { ramp.primary }

    /// Second stop for the marketing gradient. For the default emerald
    /// theme this is a cool cyan partner so every `[primary, light]`
    /// gradient renders as a green→cyan sweep without per-site changes.
    var light: Color { ramp.light }

    var dark: Color { ramp.dark }

    var highlight: Color { ramp.highlight }

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
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var iconName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    /// `nil` hands the decision back to iOS — that's what `.system` means to
    /// `View.preferredColorScheme(_:)`.
    var preferredScheme: ColorScheme? {
        switch self {
        case .system: nil
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

    /// Persisted display-mode preference. Every surface token in `AppColor`
    /// now resolves per trait collection, so all three modes render
    /// correctly; `.dark` stays the default so existing installs keep the
    /// appearance they were shipped with.
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
