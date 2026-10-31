import SwiftUI

/// Settings switch for sending crash reports. On by default; read by
/// `CrashReportUploader` whenever MetricKit delivers a diagnostic.
struct CrashReportToggleRow: View {
    @AppStorage(CrashReportUploader.enabledKey) private var isEnabled = true

    var body: some View {
        Toggle(isOn: $isEnabled) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "ladybug.fill")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: 36, height: 36)
                    .background {
                        RoundedRectangle(cornerRadius: Spacing.smallCornerRadius, style: .continuous)
                            .fill(AppColor.accentPrimary.opacity(0.18))
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Share crash reports")
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("When Atlas crashes or freezes, send the technical report so it can be fixed: app version, device model and where in the code it happened. No health data, nothing that identifies you.")
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
