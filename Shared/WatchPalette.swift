import SwiftUI

/// Colour tokens for the Watch app and its complications. Neither watch
/// target compiles the iPhone design system, so the brand values that
/// matter on the wrist are reproduced here, once, instead of per file.
/// It lives in `Shared/` so the iPhone app and its widgets read the same
/// values (tier tints, the widgets' dark-mode accents) instead of copying
/// the hex.
///
/// The Watch is dark-only, so these are single values rather than
/// light/dark pairs. Each page blooms its accent over true black (see
/// `pageBackground(_:)` in the Watch app), so the accents double as page
/// tints and there is no separate set of background colours.
enum WatchPalette {

    // MARK: Habit rings (mirror the iPhone's health = green, training = blue)

    static let health = hex(0x5BC489)
    static let training = hex(0x378ADD)
    static let protocolDose = hex(0xA78BFA)

    // MARK: Recovery

    /// Apple's Heart Rate red, not `AppColor.metricHeartRate`: the wrist
    /// follows the system Health apps it sits beside.
    static let heart = hex(0xFF375F)

    // MARK: Sleep

    /// Apple's Sleep blues, not `AppColor.metricSleep`'s amber, for the
    /// same reason as `heart`.

    static let sleepAccent = hex(0x8DB6FF)
    static let stageAwake = hex(0xFF8A65)
    static let stageREM = hex(0x5AC8FA)
    static let stageCore = hex(0x3D7BFF)
    static let stageDeep = hex(0x7B61FF)

    // MARK: Nutrition

    /// The iPhone's own nutrition colours (dark variants), so a calorie
    /// ring reads the same on the wrist as on the Meals tab: the default
    /// brand emerald (`AppTheme.teal`, which the calorie ring takes),
    /// `AppColor.macroProtein`'s amber and `AppColor.macroWater`'s blue.
    static let calories = hex(0x10B981)
    static let protein = hex(0xEF9F27)
    static let water = hex(0x378ADD)

    /// Ring and progress-bar track behind a coloured fill.
    static let track = Color.white.opacity(0.12)

    /// The Atlas Score prestige colour for a `MomentumEngine.Tier` raw
    /// value, so the wrist and the phone show the same band.
    static func tier(_ raw: String?) -> Color {
        hex(tierHex(raw))
    }

    /// 24-bit RGB behind `tier(_:)`; `MomentumEngine.Tier.tintHex` reads it.
    /// Unknown or missing tiers fall back to bronze.
    static func tierHex(_ raw: String?) -> UInt32 {
        switch raw {
        case "silver": return 0xB8C0C8
        case "gold": return 0xD4A844
        case "platinum": return 0x8FD0C4
        case "diamond": return 0x7CC5FF
        default: return 0xCD7F4F
        }
    }

    private static func hex(_ value: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
