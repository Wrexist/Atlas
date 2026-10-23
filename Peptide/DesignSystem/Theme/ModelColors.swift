import SwiftUI

extension ProtocolStatus {
    var color: Color {
        switch self {
        case .active: AppColor.accentPrimary
        case .paused: AppColor.warning
        case .completed: AppColor.textTertiary
        }
    }
}

extension PeptideCategory {
    /// Category hue. Badges, chips and pickers print it as 11–13pt text on
    /// its own 0.15–0.2 wash, so both schemes clear 4.5:1 there: the light
    /// values are deepened and the dark values lifted.
    var color: Color {
        switch self {
        case .growth: Color(light: 0x35603F, dark: 0x75AD86)
        case .recovery: Color(light: 0x285F84, dark: 0x7BA5C7)
        case .cognitive: Color(light: 0x6B44A3, dark: 0xB394DB)
        case .antiAging: Color(light: 0x73570D, dark: 0xD4A844)
        case .immune: Color(light: 0x963A3A, dark: 0xD88D8D)
        case .metabolic: Color(light: 0x8E4815, dark: 0xE88D4F)
        case .other: Color(light: 0x5B5B63, dark: 0xA0A0A0)
        }
    }
}

extension MomentumEngine.Tier {
    /// Tier hue. The dark value is the hex the Watch shares (`tintHex`); the
    /// light value is deepened so the tier name, printed in this tint, holds
    /// 4.5:1 on every light surface.
    var tint: Color {
        switch self {
        case .bronze: Color(light: 0xA45B2E, dark: UInt(tintHex))
        case .silver: Color(light: 0x61707E, dark: UInt(tintHex))
        case .gold: Color(light: 0x88681F, dark: UInt(tintHex))
        case .platinum: Color(light: 0x337A6C, dark: UInt(tintHex))
        case .diamond: Color(light: 0x0070C8, dark: UInt(tintHex))
        }
    }
}
