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
    /// Category hue. Badges and pickers print it as 13pt text on its own
    /// 0.15 wash, so the light values are deepened to clear 4.5:1 there.
    var color: Color {
        switch self {
        case .growth: Color(light: 0x35603F, dark: 0x4A7C59)
        case .recovery: Color(light: 0x285F84, dark: 0x5B8FB9)
        case .cognitive: Color(light: 0x6B44A3, dark: 0x9B72CF)
        case .antiAging: Color(light: 0x7A5C0E, dark: 0xD4A844)
        case .immune: Color(light: 0x963A3A, dark: 0xCF7272)
        case .metabolic: Color(light: 0x8E4815, dark: 0xE88D4F)
        case .other: Color(light: 0x5B5B63, dark: 0x808080)
        }
    }
}
