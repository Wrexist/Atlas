import SwiftUI

/// Settings switch for sending crash reports. On by default; read by
/// `CrashReportUploader` whenever MetricKit delivers a diagnostic.
struct CrashReportToggleRow: View {
    @AppStorage(CrashReportUploader.enabledKey) private var isEnabled = true

    var body: some View {
        Toggle(isOn: $isEnabled) {
            HStack(spacing: Spacing.md) {
                IconTile("ladybug.fill", size: 36)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Share crash reports")
                        .font(AppFont.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Crash details only — never health data")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(AppColor.accentPrimary)
        .padding(.vertical, Spacing.xs)
    }
}
