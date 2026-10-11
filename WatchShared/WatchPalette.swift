import SwiftUI

/// Colour tokens for the Watch app and its complications. Neither watch
/// target compiles the iPhone design system, so the brand values that
/// matter on the wrist are reproduced here, once, instead of per file.
///
/// The Watch is dark-only, so these are single values rather than
/// light/dark pairs. Page tints are deliberately deep: they sit behind
/// white text as a full-bleed `containerBackground`, the way the system
/// Heart Rate and Sleep apps paint theirs.
enum WatchPalette {

    // MARK: Habit rings (mirror the iPhone's health = green, training = blue)

    static let health = hex(0x5BC489)
    static let training = hex(0x378ADD)
    static let protocolDose = hex(0xA78BFA)

    // MARK: Recovery

    static let heart = hex(0xFF375F)
    static let heartPage = hex(0x6B0F1F)

    // MARK: Sleep

    static let sleepPage = hex(0x0F2F7A)
    static let sleepAccent = hex(0x8DB6FF)
    static let stageAwake = hex(0xFF8A65)
    static let stageREM = hex(0x5AC8FA)
    static let stageCore = hex(0x3D7BFF)
    static let stageDeep = hex(0x7B61FF)

    // MARK: Nutrition

    static let caloriesStart = hex(0xFF9E4D)
    static let caloriesEnd = hex(0xF26690)
    static let protein = hex(0x5CC78C)
    static let water = hex(0x4FA3FF)
    static let nutritionPage = hex(0x5A2A0C)

    // MARK: Protocol

    static let protocolPage = hex(0x2E1A66)

    /// Ring and progress-bar track behind a coloured fill.
    static let track = Color.white.opacity(0.14)

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
