import SwiftUI
import UIKit

/// Opens the app's page in iOS Settings, where the per-app language lives.
/// `String(localized:)` resolves through the bundle's language and ignores
/// SwiftUI's locale, so an in-app switch left most of the app in the old
/// language; the system setting relaunches the app in the new one.
struct LanguagePickerRow: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            Haptics.impact(.light)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "character.bubble.fill")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: settingsIconColumnWidth)
                    .accessibilityHidden(true)

                Text("Language")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColor.textPrimary)

                Spacer()

                HStack(spacing: Spacing.xs) {
                    Text(AppLanguage.current?.nativeName ?? String(localized: "System Default"))
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                    Image(systemName: "arrow.up.right")
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens Settings"))
    }
}
