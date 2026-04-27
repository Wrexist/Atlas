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
    var color: Color {
        switch self {
        case .growth: Color(hex: 0x4A7C59)
        case .recovery: Color(hex: 0x5B8FB9)
        case .cognitive: Color(hex: 0x9B72CF)
        case .antiAging: Color(hex: 0xD4A844)
        case .immune: Color(hex: 0xCF7272)
        case .metabolic: Color(hex: 0xE88D4F)
        case .other: Color(hex: 0x808080)
        }
    }
}
