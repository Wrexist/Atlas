import SwiftUI

/// Settings switch for on-device AI summaries. Only rendered when this
/// device can run Apple's on-device model — elsewhere there is nothing to
/// turn on, and the deterministic copy is all anyone sees.
struct OnDeviceSummaryToggleRow: View {
    @State private var service = OnDeviceSummaryService.shared

    var body: some View {
        if service.isSupported {
            Toggle(isOn: Binding(get: { service.isEnabled }, set: { service.setEnabled($0) })) {
                HStack(spacing: Spacing.md) {
                    IconTile("sparkles", size: 36)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("On-device AI summaries")
                            .font(AppFont.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("Short workout and coaching recaps written by Apple Intelligence on this device. Nothing is sent anywhere.")
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .tint(AppColor.accentPrimary)
            .padding(Spacing.md)
            .insetRowBackground()
        }
    }
}
