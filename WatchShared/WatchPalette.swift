import SwiftUI

/// Colour tokens for the Watch app and its complications. Neither watch
/// target compiles the iPhone design system, so the brand values that
/// matter on the wrist are reproduced here, once, instead of per file.
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

    static let heart = hex(0xFF375F)

    // MARK: Sleep

    static let sleepAccent = hex(0x8DB6FF)
    static let stageAwake = hex(0xFF8A65)
    static let stageREM = hex(0x5AC8FA)
    static let stageCore = hex(0x3D7BFF)
    static let stageDeep = hex(0x7B61FF)

    // MARK: Nutrition

    /// Lime and teal: fresh against black, and clear of the orange that
    /// went muddy where it bloomed into the background.
    static let calories = hex(0xB4E85A)
    static let protein = hex(0x3DD6C2)
    static let water = hex(0x4FA3FF)

    /// Ring and progress-bar track behind a coloured fill.
    static let track = Color.white.opacity(0.12)

    /// Mirrors `MomentumEngine.Tier.tintHex` so the Atlas Score reads in
    /// the same prestige colour the phone shows.
    static func tier(_ raw: String?) -> Color {
        switch raw {
        case "silver": return hex(0xB8C0C8)
        case "gold": return hex(0xD4A844)
        case "platinum": return hex(0x8FD0C4)
        case "diamond": return hex(0x7CC5FF)
        default: return hex(0xCD7F4F)
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
