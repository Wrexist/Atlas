import SwiftUI

/// Profile entry into the peptide Library — the database, Protocols, and
/// AI research. This is the Library's home after the Habits tab took its
/// slot in the bar. Tapping closes Profile and opens the Library as a
/// full-screen modal after the sheet's dismiss animation (presenting a
/// cover while the sheet is still up gets silently dropped — the app's
/// `sheetDismissDelay` handoff convention).
struct PeptideLibraryEntryCard: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private var peptideCount: Int { PeptideDatabase.shared.count }
    private var activeProtocols: Int { dataStore.activeProtocols.count }

    var body: some View {
        Button {
            Haptics.impact(.light)
            let app = appState
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(for: AppAnimation.sheetDismissDelay)
                app.showLibrary = true
            }
        } label: {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(AppColor.accentPrimary.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppColor.accentLight)
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Peptide Library")
                        .font(AppFont.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                    .fill(AppColor.surfaceSecondary.opacity(0.6))
                    .overlay {
                        RoundedRectangle(cornerRadius: Spacing.cardCornerRadius, style: .continuous)
                            .strokeBorder(AppColor.glassBorder, lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel("Peptide Library")
        .accessibilityHint("Opens the peptide database, protocols, and AI research")
    }

    private var subtitle: String {
        let peptides = "\(peptideCount) peptides"
        if activeProtocols == 1 {
            return "\(peptides) · 1 active protocol"
        } else if activeProtocols > 1 {
            return "\(peptides) · \(activeProtocols) active protocols"
        }
        return "\(peptides) · research & protocols"
    }
}
